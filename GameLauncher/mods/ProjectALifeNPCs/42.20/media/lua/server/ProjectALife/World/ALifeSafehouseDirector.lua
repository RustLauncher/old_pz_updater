require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/World/ALifeSafehouseEvents"
require "ProjectALife/World/ALifeSafehouseDoor"
require "ProjectALife/World/ALifeSafehouseFx"
require "ProjectALife/World/ALifeSafehouseMarks"
require "ProjectALife/World/ALifeSafehouseScript"
require "ProjectALife/Records/ALifeRepLevels"

ProjectALife = ProjectALife or {}

local Director = {
    settings = {
        enabled = true,
        frequency = 3,
        betrayal = true,
        attacks = true,
        entry = 1,
        inviteMinutes = 10,
        visitorHoldSeconds = 30,
        knockSounds = true,
        squatPercent = 15,
        ladderGapHours = 48,
        bittenPercent = 15,
        guestHours = 1,
        quietDays = 3,
        dedicated = false,
        chancePercent = 12,
        checkHours = 2,
        gapDays = 2,
        visitGapDays = 1,
        visitCooldownHours = 2,
        visitAwayHours = 0.5,
        attackGapDays = 1,
        attackMinDay = 14,
        densityMid = 10,
        densityHigh = 30,
        densityExtreme = 60,
        awayTiles = 40,
        hiddenTiles = 20,
        dropDeadlineDays = 3,
        mailboxTiles = 10,
        baseFlag = true,
        baseScore = 100,
        sampleRadius = 40,
        sampleBudget = 400,
        sampleMs = 3,
        sampleMaxAgeHours = 48,
        fightTiles = 60,
        zombieThreatTiles = 8,
        coneRange = 60,
        coneHalfCos = 0.5,
        deedHours = 48,
        huntedHours = 168,
        pruneDays = 21,
        residentCap = 8,
        pendingCap = 4,
        historyCap = 8,
        deedsCap = 8,
        passesCap = 32,
        linesCap = 130,
        refusedHours = 1,
        hostileVisitors = false,
        scriptedEffects = true,
        traderVisits = false,
        radioActivate = true,
        wallMarks = true,
    },
    adapters = {},
    metrics = {},
    cursor = 0,
    playerCursor = 0,
    coopHosts = {},
    lastSquare = {},
    sample = nil,
    lastOutcome = "idle",
}
ProjectALife.SafehouseDirector = Director

Director.tierRank = { h_hunted = 1, h_disliked = 2, h_unknown = 3, h_known = 4, h_trusted = 5 }
Director.tierByRank = { "h_hunted", "h_disliked", "h_unknown", "h_known", "h_trusted" }
Director.frequencyNames = { "Off", "Rare", "Normal", "Often" }
Director.gateOrder = { "enabled", "house", "residents", "quiet_days", "excluded", "zombies_inside",
    "density", "in_fight", "running", "pacing", "door" }
Director.timerGates = { quiet_days = true, pacing = true }
Director.deliveryGates = { "enabled", "residents", "excluded", "zombies_inside", "density", "in_fight" }
Director.directGates = { "enabled", "residents", "excluded" }

function Director.freshMetrics()
    return { ticks = 0, checks = 0, picked = 0, delivered = 0, expired = 0, refused = 0,
        deedsDropped = 0, deedsKept = 0, samples = 0, debugTriggers = 0, visitsDirect = 0, visitsFar = 0,
        windowVisits = 0, visitStarts = 0, visitQueuedMax = 0, visitExpired = 0, visitGapRefused = 0,
        rateSince = nil, partMs = {} }
end
Director.metrics = Director.freshMetrics()

function Director.reset()
    Director.adapters = {}
    Director.metrics = Director.freshMetrics()
    Director.cursor, Director.playerCursor, Director.jobCursor = 0, 0, 0
    Director.lastSquare = {}
    Director.coopHosts = {}
    Director.sample = nil
    Director.lastOutcome = "idle"
    local door = ProjectALife.SafehouseDoor
    if door ~= nil then door.reset() end
    if ProjectALife.SafehouseFx ~= nil then ProjectALife.SafehouseFx.reset() end
    if ProjectALife.SafehouseScript ~= nil then ProjectALife.SafehouseScript.reset() end
end

function Director.configure(adapters)
    adapters = type(adapters) == "table" and adapters or {}
    for name, value in pairs(adapters) do
        if Director.settings[name] ~= nil and type(value) == type(Director.settings[name]) then
            Director.settings[name] = value
        end
    end
    Director.adapters = type(adapters.hooks) == "table" and adapters.hooks or {}
    local door = ProjectALife.SafehouseDoor
    if door ~= nil then door.settings.mailboxTiles = Director.settings.mailboxTiles end
    return true
end

function Director.hours()
    if type(Director.adapters.worldHours) == "function" then return tonumber(Director.adapters.worldHours()) or 0 end
    if type(getGameTime) ~= "function" then return 0 end
    local time = getGameTime()
    return tonumber(time ~= nil and Director.ask(time, "getWorldAgeHours")) or 0
end

function Director.ask(object, name, a, b)
    return ProjectALife.SafehouseDoor.ask(object, name, a, b)
end

function Director.rand(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 1 then return 0 end
    if type(ZombRand) ~= "function" then return 0 end
    return math.floor(tonumber(ZombRand(n)) or 0)
end

function Director.isPlayer(player)
    if player == nil or type(instanceof) ~= "function" then return false end
    return instanceof(player, "IsoPlayer") == true
end

function Director.players()
    if type(Director.adapters.players) == "function" then return Director.adapters.players() or {} end
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then return locator.list() end
    local result = {}
    if type(getSpecificPlayer) == "function" then
        local player = getSpecificPlayer(0)
        if player ~= nil then result[1] = player end
    end
    return result
end

function Director.username(player)
    local name = Director.ask(player, "getUsername")
    if name == nil then return nil end
    return tostring(name)
end

function Director.playerKey(player)
    if type(player) == "string" then return player end
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.playerKey) == "function" then
        local key = reputation.playerKey(player)
        if key ~= nil then return tostring(key) end
    end
    return Director.username(player)
end

function Director.displayName(player)
    local descriptor = Director.ask(player, "getDescriptor")
    local forename = descriptor ~= nil and Director.ask(descriptor, "getForename") or nil
    if forename ~= nil and tostring(forename) ~= "" then return tostring(forename) end
    return Director.username(player) or "friend"
end

function Director.position(player)
    local x, y = tonumber(Director.ask(player, "getX")), tonumber(Director.ask(player, "getY"))
    if x == nil or y == nil then return nil end
    return x, y, tonumber(Director.ask(player, "getZ")) or 0
end

function Director.store()
    if type(Director.adapters.store) == "function" then
        local supplied = Director.adapters.store()
        supplied.houses = type(supplied.houses) == "table" and supplied.houses or {}
        return supplied
    end
    local persistence = ProjectALife.Persistence
    local bucket = persistence ~= nil and persistence.bucket("baseHeat", { players = {} }) or nil
    if type(bucket) ~= "table" then
        Director.fallback = Director.fallback or { players = {}, houses = {} }
        bucket = Director.fallback
    end
    bucket.houses = type(bucket.houses) == "table" and bucket.houses or {}
    return bucket
end

function Director.dirty()
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
end

function Director.worldKind()
    if type(Director.adapters.worldKind) == "function" then return Director.adapters.worldKind() end
    if not (type(isServer) == "function" and isServer() == true) then return "sp" end
    local players = Director.players()
    for index = 1, #players do
        local name = Director.username(players[index])
        if name ~= nil and Director.coopHosts[name] == true then return "coop" end
    end
    return "dedicated"
end

function Director.noteCoopHost(player, claimed)
    local name = Director.username(player)
    if name == nil or claimed ~= true then return false end
    Director.coopHosts[name] = true
    print("[ALIFE-SAFEHOUSE] co-op host announced user=" .. name)
    return true
end

function Director.enabledHere()
    local settings = Director.settings
    if settings.enabled ~= true then return false, "runtime_off" end
    if (tonumber(settings.frequency) or 3) <= 1 then return false, "events_off (sandbox Safehouse_Events)" end
    if Director.worldKind() == "dedicated" and settings.dedicated ~= true then
        return false, "dedicated_server_off (sandbox Safehouse_Dedicated)"
    end
    return true, nil
end

function Director.frequencyScale()
    local frequency = math.floor(tonumber(Director.settings.frequency) or 3)
    if frequency == 2 then return 2, 0.5 end
    if frequency == 4 then return 0.5, 1.5 end
    return 1, 1
end

function Director.boundsOf(building)
    local definition = Director.ask(building, "getDef")
    if definition == nil then return nil end
    local x1, y1 = tonumber(Director.ask(definition, "getX")), tonumber(Director.ask(definition, "getY"))
    local x2, y2 = tonumber(Director.ask(definition, "getX2")), tonumber(Director.ask(definition, "getY2"))
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
    return { key = x1 .. ":" .. y1 .. ":" .. x2 .. ":" .. y2, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = 0 }
end

function Director.newHouse(key, source, bounds, now)
    return {
        key = key, source = source, x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2,
        z = bounds.z or 0, cx = bounds.cx or (bounds.x1 + bounds.x2) / 2, cy = bounds.cy or (bounds.y1 + bounds.y2) / 2,
        home = key, flaggedHours = now, residents = {}, passes = {},
        last = {}, ladder = {}, pending = {}, paid = {}, refused = {}, history = {},
        zeds = nil, mods = {}, cooldowns = {}, deeds = {}, checkedHours = nil,
    }
end

function Director.adopt(key, source, bounds, player, now)
    local houses = Director.store().houses
    local house = houses[key]
    if type(house) ~= "table" then
        house = Director.newHouse(key, source, bounds, now)
        houses[key] = house
        Director.dirty()
    end
    house.residents = type(house.residents) == "table" and house.residents or {}
    local playerKey = Director.playerKey(player)
    if playerKey ~= nil then
        local resident = house.residents[playerKey]
        if type(resident) ~= "table" then
            resident = { since = now }
            house.residents[playerKey] = resident
            Director.capResidents(house)
        end
        resident.seenHours, resident.name = now, Director.displayName(player)
    end
    return house
end

function Director.capResidents(house)
    local count, oldestKey, oldest = 0, nil, nil
    for key, resident in pairs(house.residents) do
        count = count + 1
        local seen = tonumber(resident.seenHours) or tonumber(resident.since) or 0
        if oldest == nil or seen < oldest then oldestKey, oldest = key, seen end
    end
    if count > Director.settings.residentCap and oldestKey ~= nil then house.residents[oldestKey] = nil end
end

function Director.claimOf(player)
    if SafeHouse == nil or SafeHouse.getSafehouseList == nil then return nil end
    local name = Director.username(player)
    if name == nil then return nil end
    local ok, list = pcall(SafeHouse.getSafehouseList)
    if not ok or list == nil then return nil end
    local count = tonumber(Director.ask(list, "size")) or 0
    for index = 0, math.min(count, 256) - 1 do
        local claim = list:get(index)
        local owner = Director.ask(claim, "getOwner")
        local member = owner ~= nil and tostring(owner) == name
        if not member then
            local members = Director.ask(claim, "getPlayers")
            local size = members ~= nil and tonumber(Director.ask(members, "size")) or 0
            for position = 0, math.min(size, 32) - 1 do
                if tostring(members:get(position)) == name then member = true end
            end
        end
        if member then
            local x1, y1 = tonumber(Director.ask(claim, "getX")), tonumber(Director.ask(claim, "getY"))
            local x2, y2 = tonumber(Director.ask(claim, "getX2")), tonumber(Director.ask(claim, "getY2"))
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                return { key = "sh:" .. x1 .. ":" .. y1 .. ":" .. x2 .. ":" .. y2, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = 0 }
            end
        end
    end
    return nil
end

function Director.baseOf(player)
    local heat = ProjectALife.BaseHeat
    if heat == nil or type(heat.bases) ~= "function" or type(heat.keyOf) ~= "function" then return nil end
    local owner = heat.keyOf(player)
    local bases, best = heat.bases(), nil
    for index = 1, #bases do
        local base = bases[index]
        if type(base) == "table" and base.owner == owner and base.flagged == true and base.legacy ~= true
                and tonumber(base.x1) ~= nil
                and Director.homeBetter(base, best) then
            best = base
        end
    end
    if best == nil then return nil end
    return { key = Director.sharedHouseKey(best) or tostring(best.key), x1 = best.x1, y1 = best.y1,
        x2 = best.x2, y2 = best.y2, z = best.z or 0, cx = best.x, cy = best.y, round2 = true }
end

function Director.homeBetter(base, best)
    if best == nil then return true end
    local nights, bestNights = tonumber(base.nights) or 0, tonumber(best.nights) or 0
    if nights ~= bestNights then return nights > bestNights end
    return (tonumber(base.days) or 0) > (tonumber(best.days) or 0)
end

function Director.sharedHouseKey(base)
    for key, house in pairs(Director.store().houses) do
        if type(house) == "table" and house.source == "baseheat" and tonumber(house.x1) ~= nil
                and tonumber(house.x2) ~= nil and base.x1 <= house.x2 and house.x1 <= base.x2
                and base.y1 <= house.y2 and house.y1 <= base.y2 then
            return key
        end
    end
    return nil
end

function Director.markOf(playerKey)
    for _, house in pairs(Director.store().houses) do
        if type(house) == "table" and type(house.mark) == "table" and house.mark.by == playerKey then return house end
    end
    return nil
end

function Director.houseFor(player, now)
    if not Director.isPlayer(player) then return nil, "no_player" end
    now = now or Director.hours()
    local marked = Director.markOf(Director.playerKey(player))
    if marked ~= nil then return Director.adopt(marked.key, "mark", marked, player, now), "mark" end
    local claim = Director.claimOf(player)
    if claim ~= nil then return Director.adopt(claim.key, "safehouse", claim, player, now), "safehouse" end
    local base = Director.baseOf(player)
    if base ~= nil then
        local house = Director.adopt(base.key, "baseheat", base, player, now)
        house.round2 = true
        return house, "baseheat"
    end
    return nil, "no_house"
end

function Director.squareAt(player, at)
    if type(at) ~= "table" or type(getCell) ~= "function" then return nil end
    local ax, ay, az = tonumber(at.x), tonumber(at.y), tonumber(at.z) or 0
    if ax == nil or ay == nil or ax ~= ax or ay ~= ay or math.abs(ax) > 1000000 or math.abs(ay) > 1000000 then return nil end
    local px, py = Director.position(player)
    if px ~= nil and (math.abs(ax - px) > 80 or math.abs(ay - py) > 80) then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local ok, square = pcall(cell.getGridSquare, cell, math.floor(ax), math.floor(ay), math.max(0, math.min(7, math.floor(az))))
    if ok then return square end
    return nil
end

function Director.mark(player, now, at)
    if not Director.isPlayer(player) then return false, "no_player" end
    now = now or Director.hours()
    local clicked = Director.squareAt(player, at)
    local building = Director.ask(clicked, "getBuilding")
    local square = Director.ask(player, "getCurrentSquare") or Director.ask(player, "getSquare")
    if building == nil then
        clicked = nil
        building = Director.ask(player, "getBuilding") or Director.ask(square, "getBuilding")
    end
    local bounds = Director.boundsOf(building)
    if bounds == nil then return false, "not_in_a_building" end
    Director.clearMark(player)
    local x, y, z = Director.position(player)
    if clicked ~= nil then x, y, z = tonumber(at.x) or x, tonumber(at.y) or y, tonumber(at.z) or z end
    bounds.cx, bounds.cy, bounds.z = math.floor(x or bounds.x1) + 0.5, math.floor(y or bounds.y1) + 0.5, 0
    local house = Director.adopt(bounds.key, "mark", bounds, player, now)
    house.source, house.cx, house.cy = "mark", bounds.cx, bounds.cy
    house.mark = { by = Director.playerKey(player), name = Director.displayName(player), atHours = now,
        x = math.floor(x or 0), y = math.floor(y or 0), z = math.floor(z or 0) }
    house.flaggedHours = now
    house.door = nil
    Director.dirty()
    return true, nil, house
end

function Director.clearMark(player)
    local key = Director.playerKey(player)
    local cleared = 0
    local houses = Director.store().houses
    for houseKey, house in pairs(houses) do
        if type(house) == "table" and type(house.mark) == "table" and house.mark.by == key then
            house.mark = nil
            if house.source == "mark" then
                Director.cleanTraces(house)
                if ProjectALife.SafehouseMarks ~= nil then ProjectALife.SafehouseMarks.clean(house) end
                houses[houseKey] = nil
            end
            cleared = cleared + 1
        end
    end
    if cleared > 0 then Director.dirty() end
    return cleared
end

function Director.residentKeys(house)
    local keys = {}
    for key in pairs(type(house.residents) == "table" and house.residents or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function Director.onlineResidents(house)
    local result = {}
    local players = Director.players()
    for index = 1, #players do
        local player = players[index]
        local key = Director.playerKey(player)
        if key ~= nil and house.residents[key] ~= nil and Director.ask(player, "isDead") ~= true then
            result[#result + 1] = player
        end
    end
    return result
end

function Director.standOf(house)
    local door = house.door
    if type(door) == "table" and type(door.stand) == "table" then return door.stand end
    return nil
end

function Director.dropOf(house)
    local door = house.door
    if type(door) ~= "table" then return nil end
    if type(door.mailbox) == "table" then return door.mailbox end
    return door.stand
end

Director.softModules = { personal = "Personal", standing = "Standing" }

function Director.soft(key)
    if key == "personal" and ProjectALife.PersonalRep ~= nil then return ProjectALife.PersonalRep end
    local name = Director.softModules[key]
    if name == nil then return nil end
    return ProjectALife[name]
end

function Director.houseTier(house)
    local personal = Director.soft("personal")
    if personal ~= nil and type(personal.houseView) == "function" then
        local ok, view = pcall(personal.houseView, Director.residentKeys(house))
        if ok and type(view) == "table" then
            if Director.tierRank[view.tier] ~= nil then return view.tier, "personal" end
            local byLevel = { worst = "h_hunted", bad = "h_disliked", neutral = "h_unknown", good = "h_known", best = "h_trusted" }
            if byLevel[view.averageLevel] ~= nil then return byLevel[view.averageLevel], "personal" end
            local levels = ProjectALife.RepLevels
            if levels ~= nil and type(levels.rowOf) == "function" and type(levels.tiers) == "function" then
                local known, row = pcall(levels.rowOf, view.averageLevel)
                if known and row ~= nil then
                    local read, tiers = pcall(levels.tiers, view.averageLevel)
                    if read and type(tiers) == "table" and byLevel[tiers[1]] ~= nil then return byLevel[tiers[1]], "personal" end
                end
            end
        end
    end
    return "h_unknown", "personal reputation not in this build"
end

function Director.liveResident(key)
    local players = Director.players()
    for index = 1, #players do
        if Director.playerKey(players[index]) == key then return players[index] end
    end
    return nil
end

function Director.grudgeOf(key, factionId)
    local reputation = ProjectALife.Reputation
    if reputation == nil then return nil end
    local live = Director.liveResident(key)
    if live ~= nil and type(reputation.snapshotFor) == "function" then
        local ok, snapshot = pcall(reputation.snapshotFor, live)
        if ok and type(snapshot) == "table" and type(snapshot.relations) == "table" then
            for index = 1, #snapshot.relations do
                local relation = snapshot.relations[index]
                if relation.factionId == factionId and relation.status == "hostile" then return relation end
            end
            return nil
        end
    end
    if type(reputation.recordedStatus) == "function" then
        local ok, status = pcall(reputation.recordedStatus, key, factionId)
        if ok and status == "hostile" then return { status = "hostile", factionId = factionId } end
    end
    return nil
end

function Director.standingTier(key, factionId)
    local standing = Director.soft("standing")
    if standing == nil or type(standing.tierFor) ~= "function" then return nil end
    local ok, word = pcall(standing.tierFor, key, factionId)
    if not ok then return nil end
    local byWord = { hated = "h_hunted", hostile = "h_disliked", careful = "h_disliked",
        neutral = "h_unknown", friendly = "h_known", allied = "h_trusted" }
    return byWord[tostring(word)]
end

function Director.baselineTier(key, factionId)
    local reputation = ProjectALife.Reputation
    if reputation == nil or type(reputation.baselineFor) ~= "function" then return nil end
    local ok, word = pcall(reputation.baselineFor, Director.liveResident(key) or key, factionId)
    if not ok then return nil end
    local byWord = { hostile = "h_disliked", careful = "h_disliked", neutral = "h_unknown",
        friendly = "h_known", allied = "h_trusted" }
    return byWord[tostring(word)]
end

function Director.factionTier(house, factionId, now)
    now = now or Director.hours()
    local memo = Director.memo
    if memo ~= nil and memo[factionId] ~= nil then return memo[factionId] end
    local tier = Director.averageTier(house, factionId, now)
    if memo ~= nil then memo[factionId] = tier end
    return tier
end

function Director.averageTier(house, factionId, now)
    local sum, count = 0, 0
    for key in pairs(type(house.residents) == "table" and house.residents or {}) do
        local tier = Director.standingTier(key, factionId)
        if tier == nil then
            local grudge = Director.grudgeOf(key, factionId)
            if grudge ~= nil then
                tier = "h_disliked"
                if grudge.cause == "kill" and now - (tonumber(grudge.atHours) or -math.huge) < Director.settings.huntedHours then
                    tier = "h_hunted"
                end
            end
        end
        tier = tier or Director.baselineTier(key, factionId) or "h_unknown"
        sum, count = sum + Director.tierRank[tier], count + 1
    end
    if count == 0 then return "h_unknown" end
    return Director.tierByRank[math.max(1, math.min(5, math.floor(sum / count + 0.5)))]
end

Director.personalOnly = { rude_no = true, let_in = true }

function Director.deed(kind, playerKey, factionId, uid, token, extra)
    local forwarded = false
    local reason = Director.personalOnly[kind] and "personal_deed_unsupported" or "standing_deed_unsupported"
    for _, key in ipairs({ "personal", "standing" }) do
        local owner = Director.soft(key)
        local intended = key == "personal" or Director.personalOnly[kind] ~= true
        if owner ~= nil and type(owner.onDeed) == "function" and intended then
            local ok, accepted, why = pcall(owner.onDeed, kind, playerKey, factionId, uid, token, extra)
            if ok and accepted == true then forwarded = true else reason = ok and (why or reason) or "deed_provider_failed" end
        end
    end
    if not forwarded then Director.metrics.deedsDropped = Director.metrics.deedsDropped + 1 end
    if playerKey == nil then return false end
    if kind == "let_in" then return forwarded end
    local now = Director.hours()
    local kept = false
    for _, house in pairs(Director.store().houses) do
        if type(house) == "table" and type(house.residents) == "table" and house.residents[tostring(playerKey)] ~= nil then
            house.deeds = type(house.deeds) == "table" and house.deeds or {}
            table.insert(house.deeds, 1, { kind = tostring(kind), by = tostring(playerKey),
                faction = factionId, uid = uid, hours = now })
            while #house.deeds > Director.settings.deedsCap do table.remove(house.deeds) end
            kept = true
        end
    end
    if kept then
        Director.metrics.deedsKept = Director.metrics.deedsKept + 1
        Director.dirty()
    end
    if not forwarded and (kind == "rude_no" or kind == "gave_food" or kind == "fair_trade" or kind == "census_answer") then return false, reason end
    return kept
end

Director.goodDeeds = { helped_fight = true, fair_trade = true, gave_food = true, let_sleep = true, treated_wounded = true,
    sheltered_chased = true, neighbour_watch = true, finished_job = true, answered_call = true }

Director.needs = {}

function Director.needs.deed48h(house, now)
    local result = {}
    for _, deed in ipairs(type(house.deeds) == "table" and house.deeds or {}) do
        if Director.goodDeeds[deed.kind] and deed.faction ~= nil
                and now - (tonumber(deed.hours) or -math.huge) <= Director.settings.deedHours then
            result[#result + 1] = { factionId = deed.faction, target = deed.by, fact = deed.kind }
        end
    end
    return result
end

function Director.grudges(house, softOnly)
    local result = {}
    for _, key in ipairs(Director.residentKeys(house)) do
        local live = Director.liveResident(key)
        local reputation = ProjectALife.Reputation
        if live ~= nil and reputation ~= nil and type(reputation.snapshotFor) == "function" then
            local ok, snapshot = pcall(reputation.snapshotFor, live)
            if ok and type(snapshot) == "table" then
                for _, relation in ipairs(type(snapshot.relations) == "table" and snapshot.relations or {}) do
                    local soft = relation.cause == "wound" or relation.cause == "provoked"
                    if relation.status == "hostile" and (softOnly ~= true or soft) then
                        result[#result + 1] = { factionId = relation.factionId, target = key, fact = relation.cause }
                    end
                end
            end
        end
    end
    return result
end

function Director.needs.grudge(house)
    return Director.grudges(house, false)
end

function Director.needs.grudgeSoft(house)
    return Director.grudges(house, true)
end

function Director.needs.grudgeNear(house)
    return Director.grudges(house, false)
end

function Director.needs.poiNear(house)
    local poi = ProjectALife.POI
    if poi == nil or type(poi.search) ~= "function" then return {} end
    local x, y = (house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2
    local ok, found = pcall(poi.search, x, y, 400, { "medical", "warehouse", "guns", "police", "fire" })
    if not ok or type(found) ~= "table" then return {} end
    local result = {}
    for index = 1, math.min(#found, 8) do
        local place = found[index]
        local dx, dy = (tonumber(place.x) or x) - x, (tonumber(place.y) or y) - y
        local distance = math.floor(math.sqrt(dx * dx + dy * dy))
        if distance >= 30 then
            result[#result + 1] = { place = { name = tostring(place.category or place.name or "place"),
                dist = distance, dir = Director.compass(dx, dy), x = place.x, y = place.y } }
        end
    end
    return result
end

function Director.compass(dx, dy)
    local ns, ew = "", ""
    if dy < -math.abs(dx) * 0.4 then ns = "north" elseif dy > math.abs(dx) * 0.4 then ns = "south" end
    if dx > math.abs(dy) * 0.4 then ew = "east" elseif dx < -math.abs(dy) * 0.4 then ew = "west" end
    if ns ~= "" and ew ~= "" then return ns .. "-" .. ew end
    if ns ~= "" then return ns end
    return ew ~= "" and ew or "north"
end

Director.bindingNeeds = { deed48h = true, grudge = true, grudgeSoft = true }

function Director.needs.generatorHome(house)
    local heat = ProjectALife.BaseHeat
    if heat == nil or type(heat.bases) ~= "function" then return {} end
    for _, base in ipairs(heat.bases()) do
        if (tonumber(base.generators) or 0) > 0 and base.x1 <= house.x2 and house.x1 <= base.x2
                and base.y1 <= house.y2 and house.y1 <= base.y2 then
            return { { generator = true } }
        end
    end
    return {}
end

function Director.needs.radioOn(house)
    local fx = ProjectALife.SafehouseFx
    if fx == nil or type(fx.houseRadio) ~= "function" then return {} end
    local stand = Director.standOf(house)
    for _, player in ipairs(Director.onlineResidents(house)) do
        local found = fx.houseRadio(player, house, stand)
        if found ~= nil then return { { radio = true, kind = found.kind } } end
    end
    return {}
end

function Director.needs.tracesRecent(house, now)
    for _, entry in ipairs(type(house.history) == "table" and house.history or {}) do
        if entry.event == "camp_traces" and now - (tonumber(entry.hours) or -math.huge) <= 96 then return { { traces = true } } end
    end
    return {}
end

function Director.needs.entryAllowed(house)
    if Director.settings.entry == 2 then return {} end
    return { { entry = true } }
end

function Director.needs.stationNear(house)
    local poi = ProjectALife.POI
    if poi == nil or type(poi.search) ~= "function" then return {} end
    local ok, places = pcall(poi.search, house.cx, house.cy, 400, { "police" })
    if not ok or type(places) ~= "table" then return {} end
    for _, place in ipairs(places) do
        if place.category == "police" and tonumber(place.x) and tonumber(place.y)
                and (place.x - house.cx)^2 + (place.y - house.cy)^2 <= 160000 then return { { place = place } } end
    end
    return {}
end

function Director.needs.returningPerson(house, now)
    local visitors = ProjectALife.VisitorDirector
    if visitors == nil or type(visitors.returning) ~= "function" then return {} end
    local list = visitors.returning(house, now or Director.hours(), ProjectALife.SafehouseEvents.row("returning_guest"))
    if #list == 0 then return {} end
    return { { fact = "returning" } }
end

function Director.needs.badWeather(house)
    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    if climate == nil then return {} end
    local rain = tonumber(Director.ask(climate, "getRainIntensity")) or 0
    local cold = tonumber(Director.ask(climate, "getTemperature"))
    if rain >= 0.15 or (cold ~= nil and cold <= 2) then return { { fact = "weather" } } end
    return {}
end

function Director.catalogFactionIds()
    local catalog = ProjectALife.Catalog
    local current = catalog ~= nil and catalog.current or nil
    if type(current) ~= "table" or type(current.factionOrder) ~= "table" then return {} end
    local ids = {}
    for index = 1, #current.factionOrder do
        local entry = current.factionOrder[index]
        local id = type(entry) == "table" and entry.id or entry
        if id ~= nil then ids[#ids + 1] = tostring(id) end
    end
    return ids
end

function Director.faction(id)
    local catalog = ProjectALife.Catalog
    if catalog == nil or type(catalog.faction) ~= "function" then return nil end
    return catalog.faction(id)
end

function Director.factionName(id)
    local faction = Director.faction(id)
    local general = type(faction) == "table" and faction.general or nil
    return type(general) == "table" and general.name and tostring(general.name) or tostring(id)
end

function Director.factionHostile(faction)
    local rules = ProjectALife.FactionSpawnRules
    if rules == nil or type(rules.hostile) ~= "function" then return false end
    return rules.hostile(faction) == true
end

function Director.span(range)
    if type(range) ~= "table" then return nil end
    local low, high = tonumber(range[1]) or 0, tonumber(range[2]) or tonumber(range[1]) or 0
    return low + Director.rand(math.max(0, high - low) + 1)
end

Director.betrayBase = { friendly = 0, careful = 5, neutral = 10, crime = 35 }
Director.betrayTier = { h_trusted = 0.2, h_known = 0.5, h_unknown = 1, h_disliked = 1.5, h_hunted = 2 }

function Director.betrayChance(pick, houseTier, house)
    local faction = Director.faction(pick.factionId)
    local bloc = faction ~= nil and Director.blocOf(faction) or nil
    local relations = faction ~= nil and type(faction.relations) == "table" and faction.relations or {}
    local base = Director.betrayBase[bloc == "crime" and "crime" or tostring(relations.player)] or Director.betrayBase.neutral
    local scale = Director.betrayTier[tostring(pick.tier or houseTier)] or 1
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and house ~= nil and type(opinion.betrayScale) == "function" then
        scale = scale * opinion.betrayScale(pick.factionId, Director.residentKeys(house))
    end
    return math.min(60, base * scale)
end

function Director.blocOf(faction)
    local rules = ProjectALife.FactionSpawnRules
    if rules ~= nil and type(rules.blocOf) == "function" then return rules.blocOf(faction) end
    return nil
end

function Director.personsOn()
    local visitors = ProjectALife.VisitorDirector
    if visitors == nil or type(visitors.cast) ~= "function" then return false end
    local settings = ProjectALife.Settings
    local block = settings ~= nil and type(settings.visitors) == "function" and settings.visitors() or nil
    return type(block) ~= "table" or block.persons ~= false
end

function Director.visitorOnly(faction)
    local rules = ProjectALife.FactionSpawnRules
    return faction ~= nil and rules ~= nil and type(rules.visitorOnly) == "function" and rules.visitorOnly(faction) == true
end

function Director.castPerson(house, row, pick, now)
    if not Director.personsOn() then return nil, "persons_off" end
    return ProjectALife.VisitorDirector.cast(house, row, pick, now)
end

function Director.personsReady(house, row, now)
    if not Director.personsOn() then return false, "persons_off" end
    local ready, why = ProjectALife.VisitorDirector.ready(house, row, now)
    if not ready then return false, "persons_" .. tostring(why) end
    return true
end

function Director.visitorOnlyBlocked(faction, row)
    local rules = ProjectALife.FactionSpawnRules
    if rules == nil or type(rules.visitorOnly) ~= "function" or not rules.visitorOnly(faction) then return false end
    return not (type(row) == "table" and row.lane == "visit" and ProjectALife.VisitorDirector ~= nil)
end

function Director.candidates(house, row, now, relaxed)
    if row.persons == true or row.lane == "visit" then
        local ready, why = Director.personsReady(house, row, now)
        if not ready then return {}, why end
    end
    local bound, extra = nil, {}
    for _, need in ipairs(type(row.needs) == "table" and row.needs or {}) do
        local generator = Director.needs[need]
        if generator == nil then return {}, "unknown_need_" .. tostring(need) end
        local list = generator(house, now)
        if #list == 0 and relaxed ~= true then return {}, "needs_" .. need end
        if Director.bindingNeeds[need] and #list > 0 then bound = list else extra[need] = list end
    end
    local source = {}
    if bound ~= nil and relaxed ~= true then
        source = bound
    else
        for _, id in ipairs(Director.catalogFactionIds()) do source[#source + 1] = { factionId = id } end
    end
    local result = {}
    local offerVisitors = row.lane == "visit" and Director.personsOn()
    if offerVisitors and row.persons ~= true then offerVisitors = Director.personsReady(house, row, now) == true end
    for index = 1, #source do
        local entry = source[index]
        local faction = Director.faction(entry.factionId)
        local hostile = faction ~= nil and Director.factionHostile(faction)
        local tier = faction ~= nil and Director.factionTier(house, entry.factionId, now) or nil
        local fits = faction ~= nil and (row.hostileOk == true or not hostile)
        if fits and Director.visitorOnlyBlocked(faction, row) then fits = false end
        if fits and not offerVisitors and Director.visitorOnly(faction) then fits = false end
        if fits and relaxed == true then fits = Director.relaxedFits(row, hostile) end
        if fits and row.lane == "visit" and hostile and Director.settings.hostileVisitors ~= true then fits = false end
        if fits and relaxed ~= true then
            if type(row.blocs) == "table" and not ProjectALife.SafehouseEvents.contains(row.blocs, Director.blocOf(faction)) then fits = false end
            if type(row.tiers) == "table" and not ProjectALife.SafehouseEvents.contains(row.tiers, tier) then fits = false end
        end
        if fits and row.ladder ~= nil and relaxed ~= true and not Director.ladderFits(house, row, entry.factionId, now) then
            fits = false
        end
        if fits and type(row.racket) == "table" and type(house.paid) == "table"
                and (tonumber(house.paid[entry.factionId]) or -math.huge) > now then
            fits = false
        end
        if fits and row.untilCollapse == true then
            local rules = ProjectALife.FactionSpawnRules
            fits = rules ~= nil and type(rules.collapsed) == "function" and not rules.collapsed(faction, math.floor(now / 24))
        end
        if fits then
            local pick = { factionId = entry.factionId, tier = tier, target = entry.target, fact = entry.fact }
            for _, other in ipairs(extra.grudgeNear or {}) do
                if other.factionId ~= entry.factionId then pick.hostile = other.factionId; break end
            end
            local places = extra.poiNear or {}
            if #places > 0 then pick.place = places[1 + Director.rand(#places)].place end
            result[#result + 1] = pick
        end
    end
    if #result == 0 then return result, "no_faction_fits" end
    return result, nil
end

function Director.relaxedFits(row, hostile)
    if type(row.tiers) ~= "table" or #row.tiers == 0 then return true end
    local low, high = 0, 0
    for index = 1, #row.tiers do
        if (Director.tierRank[row.tiers[index]] or 3) <= 2 then low = low + 1 else high = high + 1 end
    end
    if high == 0 then return hostile == true end
    if low == 0 then return hostile ~= true end
    return true
end

function Director.fresh(house, now)
    local zeds = house.zeds
    return type(zeds) == "table" and now - (tonumber(zeds.atHours) or -math.huge) <= Director.settings.sampleMaxAgeHours
end

function Director.densityBand(house, now)
    if not Director.fresh(house, now) then return "unknown" end
    local n, settings = tonumber(house.zeds.n) or 0, Director.settings
    if n > settings.densityExtreme then return "extreme" end
    if n > settings.densityHigh then return "high" end
    if n > settings.densityMid then return "mid" end
    return "low"
end

function Director.inFight(house, now)
    if Director.fresh(house, now) and (tonumber(house.zeds.targeting) or 0) > 0 then
        return true, "a zombie is on a resident"
    end
    local registry = ProjectALife.ActorRegistry
    local stand = Director.standOf(house) or { x = (house.x1 + house.x2) / 2, y = (house.y1 + house.y2) / 2 }
    if registry == nil or type(registry.each) ~= "function" then return false, nil end
    local reach = Director.settings.fightTiles * Director.settings.fightTiles
    local found = nil
    registry.each(function(record)
        if found ~= nil or type(record) ~= "table" or record.lifecycle ~= "active" then return end
        local memory = type(record.memory) == "table" and record.memory or nil
        local target = memory ~= nil and memory.combatTargetPlayerKey or nil
        if target == nil or house.residents[tostring(target)] == nil then return end
        local at = type(record.worldPosition) == "table" and record.worldPosition or record
        local x, y = tonumber(at.x), tonumber(at.y)
        if x ~= nil and y ~= nil and (x - stand.x) ^ 2 + (y - stand.y) ^ 2 <= reach then found = record.uid end
    end)
    if found ~= nil then return true, "npc " .. tostring(found) .. " is fighting a resident" end
    return false, nil
end

function Director.hasPending(house)
    for _, pending in ipairs(type(house.pending) == "table" and house.pending or {}) do
        if pending.state == "queued" or (pending.lane == "visit" and pending.resolved ~= true) then return pending end
    end
    return nil
end

function Director.liveVisit(pending)
    return type(pending) == "table" and pending.lane == "visit" and pending.resolved ~= true
        and (pending.state ~= "queued" or pending.started == true)
end

function Director.visitActive(house, ignore)
    for _, pending in ipairs(type(house.pending) == "table" and house.pending or {}) do
        if pending ~= ignore and Director.liveVisit(pending) then return pending end
    end
    return nil
end

function Director.sharesResident(house, other)
    if house == other then return true end
    local mine = type(house.residents) == "table" and house.residents or {}
    for key in pairs(type(other.residents) == "table" and other.residents or {}) do
        if mine[key] ~= nil then return true end
    end
    return false
end

function Director.visitHold(house, now, ignore)
    local settings = Director.settings
    local gap = settings.visitGapDays * 24
    for _, other in pairs(Director.store().houses) do
        if type(other) == "table" and Director.sharesResident(house, other) then
            local active = Director.visitActive(other, ignore)
            if active ~= nil then return true, "visit active: " .. tostring(active.event) .. " is still at the house" end
            local ended = tonumber(other.visitEnded)
            if ended ~= nil and now >= ended and now - ended < settings.visitCooldownHours then
                return true, string.format("visit cooldown %.1f h left", settings.visitCooldownHours - (now - ended))
            end
            local started = tonumber(other.visitStarted)
            if started ~= nil and now >= started and now - started < gap then
                return true, string.format("visit gap %.1f h left", gap - (now - started))
            end
        end
    end
    return false, nil
end

function Director.noteVisitStart(house, pending, now)
    if pending.startedHours ~= nil then return end
    pending.startedHours = now
    house.visitStarted = now
    local metrics = Director.metrics
    metrics.visitStarts = metrics.visitStarts + 1
    metrics.rateSince = metrics.rateSince or now
    Director.dirty()
end

function Director.noteVisitEnd(house, pending, now)
    if pending.lane ~= "visit" or pending.uids == nil then return end
    house.visitEnded = now
end

function Director.visitRateLine(now)
    local metrics = Director.metrics
    now = tonumber(now) or Director.hours()
    local days = math.max(1, (now - (tonumber(metrics.rateSince) or now)) / 24)
    return string.format("[ALIFE-QA] VisitRate: started=%d perDay=%.2f queuedMax=%d expired=%d gapRefused=%d",
        metrics.visitStarts, metrics.visitStarts / days, metrics.visitQueuedMax, metrics.visitExpired, metrics.visitGapRefused)
end

function Director.visitStale(house, pending, now)
    if pending.lane ~= "visit" or pending.state ~= "queued" or pending.started == true or pending.homeAtRoll ~= true then
        return false
    end
    local away = Director.nobodyHome(house, now)
    if not away then pending.awaySince = nil; return false end
    pending.awaySince = tonumber(pending.awaySince) or now
    if now - pending.awaySince < Director.settings.visitAwayHours then return false end
    local visit = ProjectALife.SafehouseVisit
    Director.metrics.visitExpired = Director.metrics.visitExpired + 1
    if visit ~= nil and type(visit.settle) == "function" then
        visit.settle(house, pending, "expired", nil, now, "resident_left_before_arrival")
    else
        pending.resolved, pending.state = true, "outcome"
        Director.removePending(house, pending)
        Director.refund(house, pending)
    end
    return true
end

function Director.gate(id, house, now)
    local settings = Director.settings
    if id == "enabled" then
        local ok, why = Director.enabledHere()
        return not ok, why
    end
    if id == "house" then return house == nil, house == nil and "no house (mark one, claim a safehouse, or live somewhere)" or nil end
    if house == nil then return true, "no house" end
    if id == "residents" then
        if #Director.onlineResidents(house) == 0 then return true, "every resident is offline" end
        return false, nil
    end
    if id == "quiet_days" then
        local ends = (tonumber(house.flaggedHours) or now) + settings.quietDays * 24
        if now < ends then return true, string.format("quiet days: %.1f h left", ends - now) end
        return false, nil
    end
    if id == "excluded" then
        local spawn = ProjectALife.SpawnPolicy
        local drop = Director.dropOf(house) or { x = house.cx, y = house.cy }
        local region = spawn ~= nil and type(spawn.excludedRegionAt) == "function"
            and spawn.excludedRegionAt({ x = drop.x, y = drop.y }) or nil
        return region ~= nil, region ~= nil and ("excluded region " .. tostring(region)) or nil
    end
    if id == "zombies_inside" then
        local inside = Director.fresh(house, now) and (tonumber(house.zeds.inside) or 0) or 0
        return inside > 0, inside > 0 and (inside .. " zombie(s) inside the house") or nil
    end
    if id == "density" then
        local band = Director.densityBand(house, now)
        if band == "extreme" then return true, "density extreme (" .. tostring(house.zeds.n) .. " zombies)" end
        return false, "band " .. band
    end
    if id == "in_fight" then return Director.inFight(house, now) end
    if id == "running" then
        local pending = Director.hasPending(house)
        if pending ~= nil then return true, "pending " .. tostring(pending.event) .. " waits (" .. tostring(pending.wait or "queued") .. ")" end
        local raid = ProjectALife.RaidDirector
        if raid ~= nil and raid.state ~= nil then return true, "a raid is running" end
        return false, nil
    end
    if id == "pacing" then
        local gapScale = Director.frequencyScale()
        local gap = math.max(24, settings.gapDays * 24 * gapScale)
        local last = tonumber(type(house.last) == "table" and house.last.any or nil)
        if last ~= nil and now - last < gap then return true, string.format("pacing: %.1f h left", gap - (now - last)) end
        return false, nil
    end
    if id == "door" then
        local door = ProjectALife.SafehouseDoor
        local stale, why = door.stale(house, now)
        if stale then return true, "front door " .. tostring(why) end
        if house.door.mode == "none" then return true, "no reachable square outside the house" end
        return false, nil
    end
    return false, nil
end

function Director.gateState(house, now)
    local result = {}
    for index = 1, #Director.gateOrder do
        local id = Director.gateOrder[index]
        local blocks, why = Director.gate(id, house, now)
        result[#result + 1] = { id = id, blocks = blocks == true, why = why }
    end
    return result
end

function Director.laneFactor(house, lane, now)
    local band = Director.densityBand(house, now)
    if lane == "quiet" then
        if band == "high" then return 0.5 end
        if band == "extreme" then return 0 end
        return 1
    end
    if lane == "visit" then
        if band == "mid" then return 0.3 end
        if band == "high" or band == "extreme" or band == "unknown" then return 0 end
        return 1
    end
    if lane == "lethal" then
        if Director.settings.attacks ~= true then return 0 end
        return 1
    end
    return 0
end

function Director.rowOpen(house, row, now, skipTimers)
    if (tonumber(row.weight) or 0) <= 0 then return false, "weight 0" end
    if row.scripted == true and Director.settings.scriptedEffects ~= true then return false, "scripted effects off" end
    if row.id == "trader" and Director.settings.traderVisits ~= true then return false, "trader visits off" end
    if (row.persons == true or row.lane == "visit") and not Director.personsOn() then return false, "persons off" end
    if type(row.hours) == "table" then
        local time = type(getGameTime) == "function" and getGameTime() or nil
        local hour = tonumber(Director.ask(time, "getTimeOfDay"))
        local first, last = tonumber(row.hours[1]), tonumber(row.hours[2])
        if hour == nil or first == nil or last == nil then return false, "time unavailable" end
        hour = hour % 24
        local open = first == last or (first < last and hour >= first and hour < last)
            or (first > last and (hour >= first or hour < last))
        if not open then return false, "outside visit hours" end
    end
    local day = math.floor(now / 24)
    if not skipTimers then
        if row.minDay ~= nil and day < row.minDay then return false, "before day " .. row.minDay end
        if row.maxDay ~= nil and day > row.maxDay then return false, "after day " .. row.maxDay end
        if row.lane == "lethal" and day < Director.settings.attackMinDay then return false, "attacks before day " .. Director.settings.attackMinDay end
        local laneGap = row.lane == "visit" and Director.settings.visitGapDays
            or (row.lane == "lethal" and Director.settings.attackGapDays or nil)
        local laneLast = tonumber(type(house.last) == "table" and house.last[row.lane] or nil)
        if laneGap ~= nil and laneLast ~= nil and now - laneLast < laneGap * 24 then
            return false, string.format("%s gap %.1f h left", row.lane, laneGap * 24 - (now - laneLast))
        end
        if row.lane == "visit" then
            local held, heldWhy = Director.visitHold(house, now)
            if held then return false, heldWhy end
        end
        local cooled = tonumber(type(house.cooldowns) == "table" and house.cooldowns[row.id] or nil)
        if cooled ~= nil and now - cooled < (tonumber(row.cooldownDays) or 0) * 24 then
            return false, string.format("cooldown %.1f h left", (tonumber(row.cooldownDays) or 0) * 24 - (now - cooled))
        end
    end
    if Director.settings.entry == 2 and ProjectALife.SafehouseEvents.contains(row.needs, "entryAllowed") then
        return false, "entry never"
    end
    return true, nil
end

function Director.pickWeighted(list, weightOf)
    local total = 0
    for index = 1, #list do total = total + math.max(0, weightOf(list[index])) end
    if total <= 0 then return nil end
    local roll = Director.rand(math.floor(total * 100)) / 100
    local acc = 0
    for index = 1, #list do
        acc = acc + math.max(0, weightOf(list[index]))
        if roll < acc then return list[index] end
    end
    return list[#list]
end

function Director.weigh(house, now, opts)
    opts = type(opts) == "table" and opts or {}
    local result = { ok = false, gates = {} }
    for index = 1, #Director.gateOrder do
        local id = Director.gateOrder[index]
        if not (opts.skipTimers and Director.timerGates[id]) then
            local blocks, why = Director.gate(id, house, now)
            if blocks then
                result.reason, result.gate = "gate_" .. id .. ": " .. tostring(why), id
                return result
            end
        end
    end
    if not opts.skipChance and opts.forced ~= true then
        local _, chanceScale = Director.frequencyScale()
        local p = math.min(1, Director.settings.chancePercent / 100 * chanceScale)
        result.chance = p
        if Director.rand(10000) >= math.floor(p * 10000) then
            result.reason = string.format("chance: no event this check (%.0f%%)", p * 100)
            return result
        end
    end
    local tier = Director.houseTier(house)
    local mix = ProjectALife.SafehouseEvents.mix[tier] or ProjectALife.SafehouseEvents.mix.h_unknown
    local lanes = {}
    local closed = {}
    local personsOn, rows = Director.personsOn(), {}
    for _, row in ipairs(ProjectALife.SafehouseEvents.shippable()) do
        if row.persons ~= true or personsOn then rows[#rows + 1] = row end
    end
    for _, row in ipairs(rows) do
        local open, note = Director.rowOpen(house, row, now, opts.skipTimers)
        if open then
            local picks, pickWhy = Director.candidates(house, row, now, false)
            if #picks > 0 then
                lanes[row.lane] = lanes[row.lane] or { lane = row.lane, rows = {} }
                table.insert(lanes[row.lane].rows, { row = row, picks = picks })
            else
                open, note = false, pickWhy
            end
        end
        if not open then
            local key = (string.gsub(tostring(note), "[%d%.]+", "#"))
            closed[key] = (closed[key] or 0) + 1
        end
    end
    local laneList = {}
    for _, lane in ipairs(ProjectALife.SafehouseEvents.lanes) do
        if lanes[lane] ~= nil then
            lanes[lane].weight = (mix[lane] or 0) * Director.laneFactor(house, lane, now)
            if lanes[lane].weight > 0 then laneList[#laneList + 1] = lanes[lane] end
        end
    end
    result.tier = tier
    local lane = Director.pickWeighted(laneList, function(entry) return entry.weight end)
    if lane == nil then
        local parts = ProjectALife.SafehouseDoor.reasonText(closed)
        local openLanes = 0
        for _ in pairs(lanes) do openLanes = openLanes + 1 end
        if openLanes > 0 then
            parts = "zombie density band " .. Director.densityBand(house, now) .. " blocks the open lanes; " .. parts
        end
        result.reason = "nothing eligible (" .. parts .. ")"
        return result
    end
    local events = ProjectALife.SafehouseEvents
    local choice = Director.pickWeighted(lane.rows, function(entry)
        return entry.row.weight * events.tierWeight(entry.row, tier)
    end)
    result.lane, result.row = lane.lane, choice.row
    result.pick = choice.picks[1 + Director.rand(#choice.picks)]
    if result.row.lane == "lethal" then
        local routed = Director.routeRaid(house, result.pick.factionId)
        if routed == nil then result.reason = "lethal lane not built (P2 ladder, P5 variants)"; return result end
    end
    result.ok, result.reason = true, "picked " .. result.row.id
    return result
end

function Director.routeRaid(house, factionId)
    return nil
end

function Director.ladderStep(house, factionId)
    local ladder = type(house.ladder) == "table" and house.ladder[factionId] or nil
    return type(ladder) == "table" and tonumber(ladder.step) or 0
end

function Director.band(tier, pool)
    local wanted = "neutral"
    if tier == "h_hunted" or tier == "h_disliked" then wanted = "bad" end
    if tier == "h_known" or tier == "h_trusted" then wanted = "good" end
    if type(pool[wanted]) == "table" then return wanted end
    for _, band in ipairs({ "neutral", "good", "bad" }) do
        if type(pool[band]) == "table" then return band end
    end
    return nil
end

function Director.fill(template, values)
    return (string.gsub(tostring(template), "{(%w+)}", function(name)
        local value = values[name]
        if value == nil then return "{" .. name .. "}" end
        return tostring(value)
    end))
end

function Director.residentName(house, key)
    local resident = key ~= nil and house.residents[tostring(key)] or nil
    if type(resident) == "table" and resident.name ~= nil then return resident.name end
    for _, other in pairs(house.residents) do
        if type(other) == "table" and other.name ~= nil then return other.name end
    end
    return "friend"
end

function Director.attachPerson(house, pending, cast, now)
    pending.faction = cast.factionId or pending.faction
    pending.factionTier = Director.factionTier(house, pending.faction, now)
    pending.plan = { version = 1, scam = false, searchRefused = false, hiddenWeapon = false, bitten = false,
        counting = false, betray = false, squat = false, fake = false }
    pending.person = { ids = cast.personIds, party = cast.partyId, carriers = cast.carrierProfileIds, via = cast.via,
        returning = cast.returning == true }
    return pending
end

function Director.composePerson(house, row, pick, now)
    local cast, why = Director.castPerson(house, row, pick, now)
    if cast ~= nil then return cast end
    return nil, "visitor_cast_" .. tostring(why or "no_candidates")
end

function Director.compose(house, row, pick, now, debug)
    if row.lane == "visit" then
        local cast, castWhy = Director.composePerson(house, row, pick, now)
        if cast == nil and castWhy ~= nil then return nil, castWhy end
        local store = Director.store()
        local sequence = store.visitIdentitySequence
        if sequence == nil then sequence = 0 end
        if type(sequence) ~= "number" or sequence ~= sequence or sequence < 0
                or sequence >= 9007199254740991 or sequence ~= math.floor(sequence) then
            return nil, "visit_identity_invalid"
        end
        store.visitIdentitySequence = sequence + 1
        house.visitSequence = (tonumber(house.visitSequence) or 0) + 1
        Director.dirty()
        local houseTier = Director.houseTier(house)
        local scam = row.id == "trader" and houseTier == "h_unknown" and Director.settings.betrayal == true and Director.rand(100) < 10
        local counting = row.id == "beggar" and houseTier == "h_unknown" and Director.settings.betrayal == true and Director.rand(100) < 10
        local betray = (row.id == "sleep_one_night" or row.id == "asks_help") and Director.settings.betrayal == true
            and Director.rand(100) < Director.betrayChance(pick, houseTier, house)
        local squat = row.id == "sleep_one_night" and not betray and Director.rand(100) < Director.settings.squatPercent
        local fake = row.id == "wounded" and Director.settings.betrayal == true
            and Director.rand(100) < Director.betrayChance(pick, houseTier, house)
        local bitten = row.id == "wounded" and not fake and Director.rand(100) < Director.settings.bittenPercent
        if row.id == "preacher" then
            counting = houseTier == "h_unknown" and Director.settings.betrayal == true and Director.rand(100) < 10
        end
        local pending = { id = tostring(house.key) .. ":visit2:" .. string.format("%.0f", store.visitIdentitySequence), lane = "visit",
            event = row.id, faction = pick.factionId, target = pick.target, state = "queued",
            createdHours = now, untilHours = now + 6, debug = debug == true,
            houseTier = houseTier, factionTier = pick.tier,
            plan = { version = 1, scam = scam, searchRefused = scam or bitten, hiddenWeapon = betray, bitten = bitten,
                counting = counting, betray = betray, squat = squat, fake = fake },
            hostile = pick.hostile, chasers = Director.span(row.chasers), lureCount = Director.span(row.lure), place = pick.place }
        if cast ~= nil then Director.attachPerson(house, pending, cast, now) end
        local visitModule = ProjectALife.SafehouseVisit
        if visitModule ~= nil and type(visitModule.wantFor) == "function" then pending.want = visitModule.wantFor(row.id, pending.id) end
        return pending
    end
    local events = ProjectALife.SafehouseEvents
    local pool = events.letters[row.letter or row.id] or {}
    local band = Director.band(pick.tier, pool) or "neutral"
    local lines = pool[band] or { "{faction}" }
    local demand = type(row.demand) == "table" and row.demand or nil
    local n = nil
    if demand ~= nil then n = math.min(demand.cap, demand.min + Director.rand(demand.max - demand.min + 1)) end
    local place = pick.place or {}
    local stand = Director.standOf(house)
    local _, town = ProjectALife.SafehouseDoor.regionAt(stand and stand.x or house.cx, stand and stand.y or house.cy)
    local values = {
        faction = Director.factionName(pick.factionId), player = Director.residentName(house, pick.target),
        n = n, days = demand and demand.days or nil, hostile = pick.hostile and Director.factionName(pick.hostile) or "strangers",
        place = place.name, dist = place.dist, dir = place.dir,
        name = events.names[1 + Director.rand(#events.names)], town = town or "town",
    }
    local outcomes = type(row.outcomes) == "table" and row.outcomes or { plain = 1 }
    local outcomeList = {}
    for name, weight in pairs(outcomes) do
        if not (name == "betrayal" and Director.settings.betrayal ~= true) then
            outcomeList[#outcomeList + 1] = { name = name, weight = weight }
        end
    end
    table.sort(outcomeList, function(a, b) return a.name < b.name end)
    local outcome = Director.pickWeighted(outcomeList, function(entry) return entry.weight end)
    local gift = nil
    if outcome ~= nil and outcome.name == "reward" then gift = events.gifts[1 + Director.rand(#events.gifts)] end
    return {
        id = tostring(house.key) .. ":" .. tostring(row.id) .. ":" .. string.format("%.2f", now),
        lane = row.lane, event = row.id, faction = pick.factionId, target = pick.target,
        tier = pick.tier, band = band, outcome = outcome and outcome.name or "plain",
        title = Director.fill(pool.title or "A note", values),
        body = Director.fill(lines[1 + Director.rand(#lines)], values),
        gift = gift, state = "queued", createdHours = now,
        untilHours = now + Director.settings.dropDeadlineDays * 24, debug = debug == true,
    }
end

function Director.enqueue(house, pending, now)
    house.pending = type(house.pending) == "table" and house.pending or {}
    while #house.pending >= Director.settings.pendingCap do
        local drop = nil
        for index = 1, #house.pending do
            if not Director.liveVisit(house.pending[index]) then drop = index; break end
        end
        if drop == nil then break end
        table.remove(house.pending, drop)
    end
    house.pending[#house.pending + 1] = pending
    local queued = 0
    for _, row in ipairs(house.pending) do
        if row.state == "queued" and row.resolved ~= true then queued = queued + 1 end
    end
    Director.metrics.visitQueuedMax = math.max(Director.metrics.visitQueuedMax, queued)
    if pending.debug ~= true then
        house.last = type(house.last) == "table" and house.last or {}
        house.cooldowns = type(house.cooldowns) == "table" and house.cooldowns or {}
        pending.prior = { any = house.last.any, lane = house.last[pending.lane], cooldown = house.cooldowns[pending.event] }
        house.last.any, house.last[pending.lane] = now, now
        house.cooldowns[pending.event] = now
    end
    Director.metrics.picked = Director.metrics.picked + 1
    Director.dirty()
end

function Director.newItem(fullType)
    if type(Director.adapters.newItem) == "function" then return Director.adapters.newItem(fullType) end
    if type(instanceItem) ~= "function" then return nil end
    local ok, item = pcall(instanceItem, fullType)
    if ok then return item end
    return nil
end

function Director.makeItems(pending)
    local events = ProjectALife.SafehouseEvents
    local letter = Director.newItem(events.letterItem)
    if letter == nil then return nil, "letter item unavailable" end
    Director.ask(letter, "setName", pending.title)
    Director.ask(letter, "setCustomName", true)
    if type(letter.addPage) ~= "function" then return nil, "letter item has no pages" end
    letter:addPage(1, pending.body)
    Director.ask(letter, "setLockedBy", events.lockedBy)
    local data = Director.ask(letter, "getModData")
    if type(data) == "table" then data.ALifeLetter = { event = pending.event, faction = pending.faction } end
    local items = { letter }
    if pending.gift ~= nil then
        local gift = Director.newItem(pending.gift)
        if gift ~= nil then items[#items + 1] = gift end
    end
    return items, nil
end

function Director.nobodyHome(house, now)
    local drop = Director.dropOf(house)
    if drop == nil then return false, "no drop point" end
    local settings = Director.settings
    local keepOut = ProjectALife.KeepOut
    for _, player in ipairs(Director.onlineResidents(house)) do
        local px, py, pz = Director.position(player)
        if px ~= nil then
            local d = math.sqrt((px - drop.x) ^ 2 + (py - drop.y) ^ 2)
            local facing = Director.ask(player, "getForwardDirection")
            local fx, fy = tonumber(Director.ask(facing, "getX")) or 0, tonumber(Director.ask(facing, "getY")) or 0
            local seen = keepOut ~= nil and type(keepOut.inCone) == "function"
                and keepOut.inCone(px, py, fx, fy, drop.x, drop.y, settings.coneHalfCos, settings.coneRange) == true
            local away = d >= settings.awayTiles and not seen
            if not away and d >= settings.hiddenTiles and not seen then away = not Director.lineOfSight(px, py, pz, drop) end
            if not away then
                return false, string.format("%s is %d tiles from the drop point", Director.displayName(player), math.floor(d))
            end
        end
    end
    return true, nil
end

function Director.lineOfSight(px, py, pz, drop)
    if LosUtil == nil or type(LosUtil.lineClear) ~= "function" or type(getCell) ~= "function" then return true end
    local ok, ray = pcall(LosUtil.lineClear, getCell(), math.floor(px), math.floor(py), math.floor(pz or 0),
        math.floor(drop.x), math.floor(drop.y), math.floor(drop.z or 0), false)
    return not ok or tostring(ray) ~= "Blocked"
end

function Director.removePending(house, pending)
    for index = #house.pending, 1, -1 do
        if house.pending[index] == pending then table.remove(house.pending, index) end
    end
end

function Director.remember(house, entry)
    house.history = type(house.history) == "table" and house.history or {}
    table.insert(house.history, 1, entry)
    while #house.history > Director.settings.historyCap do table.remove(house.history) end
end

function Director.deliverNow(house, pending, now, force)
    if type(isClient) == "function" and isClient() == true then return false, "client_authority" end
    if pending.lane == "visit" then
        local visit = ProjectALife.SafehouseVisit
        if visit == nil then return false, "visit_unavailable" end
        local direct = force == true or pending.debug == true
        if not direct and pending.state == "queued" and pending.started ~= true then
            local held, heldWhy = Director.visitHold(house, now, pending)
            if held then
                if now >= (tonumber(pending.untilHours) or math.huge) then
                    Director.metrics.visitExpired = Director.metrics.visitExpired + 1
                    visit.settle(house, pending, "expired", nil, now, "visit_hold_expired")
                    return false, "expired"
                end
                if pending.gapCounted ~= true then
                    pending.gapCounted = true
                    Director.metrics.visitGapRefused = Director.metrics.visitGapRefused + 1
                end
                pending.wait = heldWhy
                house.lastVisitWhy = tostring(pending.event) .. ": " .. tostring(heldWhy)
                return false, heldWhy
            end
        end
        local started, why, info = visit.start(house, pending, now, direct)
        if started then
            house.lastVisitWhy = nil
            if not direct then Director.noteVisitStart(house, pending, now) end
        else
            house.lastVisitWhy = tostring(pending.event) .. ": " .. tostring(why)
            if why == "expired" then Director.metrics.visitExpired = Director.metrics.visitExpired + 1 end
        end
        return started, why, info
    end
    if pending.state == "queued" and now > (tonumber(pending.untilHours) or math.huge) and force ~= true then
        pending.state = "expired"
        Director.removePending(house, pending)
        Director.remember(house, { event = pending.event, faction = pending.faction, outcome = "expired", hours = now })
        Director.metrics.expired = Director.metrics.expired + 1
        Director.dirty()
        return false, "expired"
    end
    local signRow = ProjectALife.SafehouseEvents.row(pending.event)
    if signRow ~= nil and pending.state == "queued" and (signRow.raid ~= nil or signRow.sabotage ~= nil) then
        return Director.deliverLethal(house, pending, signRow, now, force)
    end
    if signRow ~= nil and pending.state == "queued" and (signRow.camp ~= nil or signRow.mark ~= nil
            or signRow.opens == true or signRow.home == true or signRow.siphon ~= nil or signRow.garden ~= nil) then
        return Director.deliverSign(house, pending, signRow, now, force)
    end
    if pending.state ~= "queued" then return false, "not queued" end
    local door = ProjectALife.SafehouseDoor
    if door.stale(house, now) then pending.wait = "front door not evaluated"; return false, pending.wait end
    if force ~= true then
        for _, id in ipairs(Director.deliveryGates) do
            local blocked, why = Director.gate(id, house, now)
            if blocked then pending.wait = why; return false, why end
        end
        local away, why = Director.nobodyHome(house, now)
        if not away then pending.wait = why; return false, why end
    end
    local items, itemWhy = Director.makeItems(pending)
    if items == nil then pending.wait = itemWhy; return false, itemWhy end
    local placed, why, partial = door.place(house, items)
    if placed == nil then
        pending.wait = "refused: " .. tostring(why)
        Director.metrics.refused = Director.metrics.refused + 1
        if partial then
            pending.state = "failed_delivery"
            Director.removePending(house, pending)
            Director.remember(house, { event = pending.event, faction = pending.faction,
                outcome = "failed_delivery", hours = now, where = pending.wait })
            Director.dirty()
            print("[ALIFE-SAFEHOUSE] partial delivery stopped to prevent replay: " .. pending.wait)
        end
        return false, pending.wait
    end
    Director.climb(house, pending, now)
    pending.state, pending.placedAt = "delivered", placed
    Director.removePending(house, pending)
    Director.remember(house, { event = pending.event, faction = pending.faction, outcome = pending.outcome,
        by = pending.target, hours = now, where = placed.rank, debug = pending.debug })
    Director.metrics.delivered = Director.metrics.delivered + 1
    Director.dirty()
    print(string.format("[ALIFE-SAFEHOUSE] delivered %s from %s to %s at %d,%d (%s)%s", tostring(pending.event),
        tostring(pending.faction), tostring(house.key), placed.x, placed.y, placed.rank, pending.debug and " debug" or ""))
    return true, placed
end

Director.waitingFor = { "outside visit hours", "before day", "after day", "density", "band ", "quiet days", "pacing",
    "offline", "a zombie is on", "is fighting a resident", "resident_away", "crowded", "approach_sampling", "reach_unknown",
    "conversation_clock", "from the drop point", "gap ", "cooldown", "excluded region", "nobody home", "not evaluated",
    "spawn pending", "visit active", "inside the house", "square_unloaded", "runtime_off", "events_off", "dedicated_server_off", "client_authority", "waits" }

function Director.waiting(why)
    why = tostring(why)
    for index = 1, #Director.waitingFor do
        if string.find(why, Director.waitingFor[index], 1, true) ~= nil then return true end
    end
    return false
end

function Director.refund(house, pending)
    local prior = pending.prior
    if type(prior) ~= "table" or pending.refunded == true then return false end
    pending.refunded = true
    house.last = type(house.last) == "table" and house.last or {}
    house.cooldowns = type(house.cooldowns) == "table" and house.cooldowns or {}
    house.last.any = prior.any
    house.last[pending.lane] = prior.lane
    house.cooldowns[pending.event] = prior.cooldown
    Director.metrics.refunded = (tonumber(Director.metrics.refunded) or 0) + 1
    Director.dirty()
    return true
end

function Director.refused(house, pending, why, now)
    if pending.resolved == true or pending.state == "delivered" or pending.state == "expired"
            or pending.state == "failed_delivery" or pending.state == "outcome" then return false end
    local listed = false
    for _, row in ipairs(type(house.pending) == "table" and house.pending or {}) do
        if row == pending then listed = true end
    end
    if not listed then return false end
    if Director.waiting(why) then pending.refusedSince = nil; return false end
    pending.refusedSince = tonumber(pending.refusedSince) or now
    if now - pending.refusedSince < Director.settings.refusedHours then return false end
    print(string.format("[ALIFE-SAFEHOUSE] %s given up after %.1f h of refusals: %s", tostring(pending.event),
        now - pending.refusedSince, tostring(why)))
    if pending.lane == "visit" then
        local visit = ProjectALife.SafehouseVisit
        if visit ~= nil and type(visit.settle) == "function" then return visit.settle(house, pending, "no_placement", nil, now) end
    end
    pending.state = "failed_delivery"
    Director.removePending(house, pending)
    Director.remember(house, { event = pending.event, faction = pending.faction, outcome = "no_placement", hours = now,
        where = tostring(why) })
    Director.refund(house, pending)
    Director.dirty()
    return true
end

function Director.deliver(house, pending, now, force)
    local ok, why, info = Director.deliverNow(house, pending, now, force)
    if ok ~= true and force ~= true and pending.debug ~= true and type(why) == "string" then
        Director.refused(house, pending, why, now)
    end
    return ok, why, info
end

Director.markTexts = {
    kind = "A chalk symbol by the door. Travellers' code: kind people live here.",
    food = "A chalk symbol by the door. Travellers' code: this house has food.",
    armed = "A chalk symbol by the door. Travellers' code: armed, keep away.",
    paint_x = "Fresh paint by the front door: a big X at eye level. Someone marked this house.",
    tally = "Tally marks scratched by the door. Someone is counting how many live here.",
    flag = "{faction} have tied their colours to your fence. They say this house is under them.",
    blood = "Blood smeared on the wall by the front door. It is fresh.",
}

Director.markPlaced = {
    flag = "{faction} have painted their sign by your door. They say this house is under them.",
}

function Director.markKind(house, row)
    if row.mark ~= "chalk" then return row.mark end
    for _, entry in ipairs(type(house.history) == "table" and house.history or {}) do
        local outcome = tostring(entry.outcome)
        if outcome == "gave_food" or outcome == "let_sleep" or outcome == "fair_trade" or outcome == "treated_wounded" then
            return "kind"
        end
        if outcome == "rude_no" or outcome == "guest_turned" or outcome == "racket_backed_down" then return "armed" end
    end
    return "food"
end

function Director.present(house)
    local stand = Director.standOf(house)
    local result = {}
    if stand == nil then return result end
    for _, player in ipairs(Director.onlineResidents(house)) do
        local x, y = Director.position(player)
        if x ~= nil and (x - stand.x) ^ 2 + (y - stand.y) ^ 2 <= 400 and Director.ask(player, "isAsleep") ~= true then
            result[#result + 1] = player
        end
    end
    return result
end

function Director.tell(player, text, mark)
    if type(text) ~= "string" or text == "" then return false end
    if type(player.setHaloNote) == "function" then pcall(player.setHaloNote, player, text, 230, 220, 160, 600) end
    if type(isServer) == "function" and isServer() == true then
        if type(sendServerCommand) == "function" then
            pcall(sendServerCommand, player, "ProjectALife", "safehouseNotice", { text = text, mark = mark })
        end
    else
        local client = ProjectALife.SafehouseClient
        if client ~= nil and type(client.notice) == "function" then client.notice({ text = text, mark = mark }, player) end
    end
    return true
end

function Director.notice(house, text, now, mark)
    house.notices = type(house.notices) == "table" and house.notices or {}
    table.insert(house.notices, 1, { text = text, atHours = now, seen = {}, mark = mark })
    while #house.notices > 4 do table.remove(house.notices) end
    Director.dirty()
end

function Director.flushNotices(house, now)
    if type(house.notices) ~= "table" or #house.notices == 0 then return 0 end
    local present, sent = Director.present(house), 0
    for index = #house.notices, 1, -1 do
        local notice = house.notices[index]
        if now - (tonumber(notice.atHours) or now) > 72 then
            table.remove(house.notices, index)
        else
            notice.seen = type(notice.seen) == "table" and notice.seen or {}
            for _, player in ipairs(present) do
                local key = Director.playerKey(player)
                if key ~= nil and notice.seen[key] ~= true then
                    notice.seen[key] = true
                    Director.tell(player, notice.text, notice.mark)
                    sent = sent + 1
                end
            end
        end
    end
    if sent > 0 then Director.dirty() end
    return sent
end

function Director.openFrontDoor(house, force, dry)
    local door = house.door
    if type(door) ~= "table" or door.mode ~= "door" then
        return false, "no front door (stand mode " .. tostring(type(door) == "table" and door.mode or "none") .. ")"
    end
    local object = ProjectALife.SafehouseDoor.entryDoor(door)
    if object == nil then return false, "the front door object was not found" end
    if Director.ask(object, "IsOpen") == true then return false, "the front door is already open" end
    local policy = ProjectALife.DoorPolicy
    local cleared = false
    if policy ~= nil and type(policy.lockKind) == "function" then
        local ok, kind = pcall(policy.lockKind, object, nil)
        if ok and kind ~= nil then
            if force ~= true or kind ~= "key" then return false, "the front door is locked (" .. tostring(kind) .. ")" end
            if dry == true then return true, "would be unlocked (debug) and opened" end
            Director.ask(object, "setLockedByKey", false)
            Director.ask(object, "setLocked", false)
            cleared = true
        end
    end
    if type(object.ToggleDoorSilent) ~= "function" then return false, "the front door cannot be toggled" end
    if dry == true then return true, "would be opened" end
    local ok = pcall(object.ToggleDoorSilent, object)
    if ok and Director.ask(object, "IsOpen") == true then
        if cleared then return true, "unlocked (debug) and opened" end
        return true, "opened"
    end
    return false, "the front door did not open"
end

function Director.deliverSign(house, pending, row, now, force)
    if force ~= true then
        for _, id in ipairs(Director.deliveryGates) do
            local blocked, why = Director.gate(id, house, now)
            if blocked then pending.wait = why; return false, why end
        end
    end
    local text, say, at = row.notice, nil, nil
    local rank = "sign"
    if row.home == true then
        rank = "notice"
        local present
        if force == true then present = Director.onlineResidents(house) else present = Director.present(house) end
        if #present == 0 then pending.wait = "nobody home and awake"; return false, pending.wait end
        local told, fxNote = false, nil
        if type(row.fx) == "string" and ProjectALife.SafehouseScript ~= nil then
            told, fxNote = ProjectALife.SafehouseScript.home(house, present, row, text, now, force)
        end
        if not told then
            for _, player in ipairs(present) do Director.tell(player, text) end
        end
        if row.light == true then
            local sent, windows = Director.sendLight(house, present)
            if sent ~= true then
                say = "no light sent (no stand square)"
            elseif (windows or 0) > 0 then
                say = "light sweeps " .. windows .. " window(s)"
            else
                say = "light sweeps the south wall (no window mapped)"
            end
        else
            say = "told " .. #present .. " resident(s)"
            if fxNote ~= nil then say = say .. " - " .. tostring(fxNote) end
        end
    else
        if force ~= true then
            local away, why = Director.nobodyHome(house, now)
            if not away then pending.wait = why; return false, why end
        end
        local mark = nil
        if type(row.camp) == "table" then
            if force ~= true and tonumber(pending.retryAtHours) ~= nil and now < pending.retryAtHours then
                return false, pending.wait
            end
            local result, why = Director.scatterTraces(house, pending, row, now)
            if result == nil then
                pending.wait, pending.retryAtHours = "refused: " .. tostring(why), now + 0.25
                return false, pending.wait
            end
            text, say, at, rank = result.text, result.say, result.at, "yard"
        end
        if row.siphon ~= nil then
            local taken = Director.siphon(house, row.siphon)
            if taken == 0 then pending.wait = "no car in the open within 40 tiles to siphon"; return false, pending.wait end
            say = string.format("%.1f units of fuel taken", taken)
        end
        if row.garden ~= nil then
            local taken = Director.garden(house, row.garden)
            if taken == 0 then pending.wait = "no ripe crops within 40 tiles to take"; return false, pending.wait end
            say = taken .. " ripe plant(s) picked"
        end
        if row.opens == true then
            local opened, why = Director.openFrontDoor(house, force == true)
            if not opened then pending.wait = tostring(why); return false, pending.wait end
            say = "the front door was " .. tostring(why)
        end
        if row.mark ~= nil then
            local kind = Director.markKind(house, row)
            text = Director.fill(Director.markTexts[kind] or "A mark by the door.",
                { faction = Director.factionName(pending.faction) })
            house.marks = type(house.marks) == "table" and house.marks or {}
            house.marks[#house.marks + 1] = { kind = kind, faction = pending.faction, atHours = now, text = text }
            while #house.marks > 4 do table.remove(house.marks, 1) end
            mark = kind
            local marks = ProjectALife.SafehouseMarks
            local entry, why = nil, "marks module missing"
            if marks ~= nil then entry, why = marks.place(house, kind, now, pending) end
            if entry ~= nil then
                if Director.markPlaced[kind] ~= nil then
                    text = Director.fill(Director.markPlaced[kind], { faction = Director.factionName(pending.faction) })
                end
                say = string.format("mark '%s' painted on the %s wall at %d,%d (%s), sprite %s", kind,
                    entry.north and "north" or "west", entry.x, entry.y,
                    entry.visible and "outer face toward the street" or "the face seen from inside", tostring(entry.sprite))
            else
                say = "mark '" .. kind .. "' by the front door (a notice only: " .. tostring(why) .. ")"
            end
        end
        if text ~= nil then Director.notice(house, text, now, mark) end
    end
    Director.climb(house, pending, now)
    pending.state = "delivered"
    Director.removePending(house, pending)
    Director.remember(house, { event = pending.event, faction = pending.faction, outcome = "plain", hours = now,
        debug = pending.debug })
    Director.metrics.delivered = Director.metrics.delivered + 1
    Director.dirty()
    local spot = at or Director.standOf(house) or { x = house.cx or 0, y = house.cy or 0 }
    return true, { rank = rank, x = math.floor(spot.x), y = math.floor(spot.y), say = say }
end

function Director.traceGroup(pending)
    local faction = Director.faction(pending.faction)
    local bloc = nil
    if faction ~= nil then bloc = Director.blocOf(faction) end
    return ProjectALife.SafehouseEvents.traceGroup(bloc)
end

function Director.traceKinds(group, count)
    local events = ProjectALife.SafehouseEvents
    local pool = events.traceKinds[group] or events.traceKinds.civilian
    local taken, result = {}, {}
    for _ = 1, count do
        local open = {}
        for index = 1, #pool do
            if (taken[pool[index][1]] or 0) < pool[index][3] then open[#open + 1] = pool[index] end
        end
        local pick = nil
        if #open > 0 then pick = Director.pickWeighted(open, function(kind) return kind[2] end) end
        if pick == nil then break end
        taken[pick[1]] = (taken[pick[1]] or 0) + 1
        result[#result + 1] = pick[1]
    end
    return result
end

function Director.scatterTraces(house, pending, row, now)
    local events, door = ProjectALife.SafehouseEvents, ProjectALife.SafehouseDoor
    local rule = row.camp
    local stand = Director.standOf(house)
    if stand == nil then return nil, "no_stand_square" end
    if tonumber(pending.nights) == nil then pending.nights = Director.span(rule.nights or { 1, 1 }) end
    local nights = math.max(1, math.floor(tonumber(pending.nights) or 1))
    local total = math.min(tonumber(rule.cap) or 10, (tonumber(rule.base) or 4) + (tonumber(rule.perNight) or 2) * nights)
    local fireCount = 0
    if nights >= (tonumber(rule.fireFrom) or 2) then fireCount = math.min(#events.traceFire, nights + 1) end
    local group = Director.traceGroup(pending)
    local litter, fire = {}, {}
    for _, fullType in ipairs(Director.traceKinds(group, math.max(2, total - fireCount))) do
        local item = Director.newItem(fullType)
        if item ~= nil then litter[#litter + 1] = { item = item, fullType = fullType } end
    end
    for index = 1, fireCount do
        local fullType = events.traceFire[index]
        local item = Director.newItem(fullType)
        if item ~= nil then fire[#fire + 1] = { item = item, fullType = fullType, stone = fullType == "Base.Stone2" } end
    end
    if #litter + #fire == 0 then return nil, "trace items unavailable" end
    local report, why = door.scatter(house, stand, { litter = litter, fire = fire, rand = Director.rand })
    if report == nil then return nil, why end
    house.traces = type(house.traces) == "table" and house.traces or {}
    local far = 0
    for _, spot in ipairs(report.spots) do
        house.traces[#house.traces + 1] = { x = spot.x, y = spot.y, z = spot.z, t = spot.t, id = spot.id, atHours = now }
        far = math.max(far, spot.ring or 0)
    end
    Director.trimTraces(house)
    local text = row.notice
    if nights > 1 then text = string.gsub(text, "a night", nights .. " nights") end
    local ashes = ""
    if report.fire ~= nil then
        text = text .. " Someone kept a small fire going."
        ashes = string.format(", ashes at %d,%d", report.fire.x, report.fire.y)
    end
    local say = string.format("%d items on %d squares within %d tile(s) of %d,%d (%d night(s), %s camp%s)",
        report.placed, report.squares, far, stand.x, stand.y, nights, group, ashes)
    return { text = text, say = say, at = { x = stand.x, y = stand.y }, report = report }
end

function Director.dropTrace(entry)
    local result = ProjectALife.SafehouseDoor.removeTrace(entry)
    if result == nil then
        local store = Director.store()
        store.traceDebt = type(store.traceDebt) == "table" and store.traceDebt or {}
        if #store.traceDebt < 64 then
            store.traceDebt[#store.traceDebt + 1] = { x = entry.x, y = entry.y, z = entry.z, t = entry.t, id = entry.id,
                atHours = entry.atHours }
        end
    end
    Director.dirty()
    return result
end

function Director.trimTraces(house)
    local list = house.traces
    if type(list) ~= "table" then return 0 end
    local trimmed = 0
    while #list > ProjectALife.SafehouseDoor.settings.traceCap do
        Director.dropTrace(table.remove(list, 1))
        trimmed = trimmed + 1
    end
    return trimmed
end

function Director.cleanTraces(house)
    local list = type(house.traces) == "table" and house.traces or {}
    local removed = 0
    for index = #list, 1, -1 do
        if Director.dropTrace(table.remove(list, index)) == true then removed = removed + 1 end
    end
    return removed
end

function Director.traceTick(now)
    if Director.metrics.ticks % 10 ~= 0 then return 0 end
    local worked = 0
    local limit = ProjectALife.SafehouseDoor.settings.traceDays * 24
    for _, key in ipairs(Director.houseList()) do
        local list = Director.store().houses[key].traces
        if type(list) == "table" then
            for index = #list, 1, -1 do
                if now - (tonumber(list[index].atHours) or now) > limit then
                    Director.dropTrace(table.remove(list, index))
                    worked = worked + 1
                end
            end
        end
    end
    local debt = Director.store().traceDebt
    if type(debt) == "table" then
        local tried = 0
        for index = #debt, 1, -1 do
            if tried >= 2 then break end
            tried = tried + 1
            local entry = debt[index]
            local result = ProjectALife.SafehouseDoor.removeTrace(entry)
            if result ~= nil or now - (tonumber(entry.atHours) or now) > limit + 72 then
                table.remove(debt, index)
                worked = worked + 1
            end
        end
    end
    return worked
end

function Director.wash(player)
    if not Director.isPlayer(player) then return false, "no_player" end
    local key, now = Director.playerKey(player), Director.hours()
    local x, y = Director.position(player)
    if key == nil or x == nil then return false, "no_player" end
    for _, house in pairs(Director.store().houses) do
        local stand = Director.standOf(house)
        if type(house) == "table" and type(house.residents) == "table" and house.residents[key] ~= nil and stand ~= nil
                and (x - stand.x) ^ 2 + (y - stand.y) ^ 2 <= 16 and type(house.marks) == "table" and #house.marks > 0 then
            for _, mark in ipairs(house.marks) do
                local ladder = type(house.ladder) == "table" and house.ladder[mark.faction] or nil
                if type(ladder) == "table" then ladder.washedUntil = now + 72 end
            end
            house.marks = {}
            if ProjectALife.SafehouseMarks ~= nil then ProjectALife.SafehouseMarks.clean(house) end
            Director.dirty()
            Director.tell(player, "You scrub the mark off the wall.")
            return true, nil
        end
    end
    return false, "no_mark_here"
end

Director.ladderGapHours = 48

function Director.ladderFits(house, row, factionId, now)
    local ladder = type(house.ladder) == "table" and house.ladder[factionId] or nil
    local step = type(ladder) == "table" and tonumber(ladder.step) or 0
    if step ~= row.ladder - 1 then return false end
    if row.ladder == 1 or type(ladder) ~= "table" then return true end
    if now - (tonumber(ladder.atHours) or now) < Director.settings.ladderGapHours then return false end
    return now >= (tonumber(ladder.washedUntil) or -math.huge)
end

function Director.climb(house, pending, now)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    if row == nil or row.ladder == nil or pending.faction == nil then return false end
    house.ladder = type(house.ladder) == "table" and house.ladder or {}
    local step = row.ladder >= 4 and 1 or row.ladder
    house.ladder[pending.faction] = { step = step, atHours = now, cause = row.id }
    Director.dirty()
    return true
end

function Director.houseSquares(house, visit)
    local seen, budget = 0, 900
    for x = math.floor(house.x1) - 1, math.floor(house.x2) do
        for y = math.floor(house.y1) - 1, math.floor(house.y2) do
            seen = seen + 1
            if seen > budget then return end
            local square = ProjectALife.SafehouseDoor.square(x, y, house.z or 0)
            if square ~= nil and visit(square) == true then return end
        end
    end
end

function Director.barricadeOutside(barricade, fallback)
    local at = Director.ask(barricade, "getSquare") or fallback
    return at ~= nil and ProjectALife.SafehouseDoor.outside(at)
end

function Director.sabotage(house, rule, dry)
    local planks, windows = tonumber(rule.planks) or 3, tonumber(rule.windows) or 1
    local heat = ProjectALife.BaseHeat
    local done = { planks = 0, windows = 0 }
    Director.houseSquares(house, function(square)
        local objects = Director.ask(square, "getSpecialObjects")
        local size = tonumber(objects ~= nil and Director.ask(objects, "size")) or 0
        for index = 0, math.min(size, 16) - 1 do
            local object = objects:get(index)
            if done.planks < planks and type(object.getBarricadeOnSameSquare) == "function" then
                for _, getter in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
                    local barricade = Director.ask(object, getter)
                    local npc = heat ~= nil and type(heat.npcBarricade) == "function" and heat.npcBarricade(barricade)
                    if barricade ~= nil and not npc and Director.barricadeOutside(barricade, square)
                            and (tonumber(Director.ask(barricade, "getNumPlanks")) or 0) > 0
                            and type(barricade.removePlank) == "function" and done.planks < planks then
                        if dry == true or pcall(barricade.removePlank, barricade, nil) then done.planks = done.planks + 1 end
                    end
                end
            end
            if done.windows < windows and type(instanceof) == "function" and instanceof(object, "IsoWindow")
                    and Director.ask(object, "isSmashed") ~= true and Director.ask(object, "isInvincible") ~= true
                    and type(object.smashWindow) == "function" then
                if dry == true or pcall(object.smashWindow, object) then done.windows = done.windows + 1 end
            end
        end
        return done.planks >= planks and done.windows >= windows
    end)
    return done
end

function Director.powerCut(house)
    local cut = 0
    Director.houseSquares(house, function(square)
        local objects = Director.ask(square, "getObjects")
        local size = tonumber(objects ~= nil and Director.ask(objects, "size")) or 0
        for index = 0, math.min(size, 16) - 1 do
            local object = objects:get(index)
            if type(instanceof) == "function" and instanceof(object, "IsoGenerator") and Director.ask(object, "isActivated") == true
                    and Director.ask(square, "isOutside") == true and type(object.setActivated) == "function" then
                if pcall(object.setActivated, object, false) then cut = cut + 1 end
            end
        end
        return false
    end)
    return cut
end

function Director.lureTick(nowMs)
    local lure = Director.lure
    if lure == nil then return 0 end
    if nowMs >= lure.untilMs then Director.lure = nil; return 0 end
    if nowMs < (lure.nextMs or 0) then return 0 end
    lure.nextMs = nowMs + 2000
    if type(addSound) == "function" then pcall(addSound, nil, lure.x, lure.y, lure.z, 60, 100) end
    return 1
end

function Director.deliverLethal(house, pending, row, now, force)
    if force ~= true then
        for _, id in ipairs(Director.deliveryGates) do
            local blocked, why = Director.gate(id, house, now)
            if blocked then pending.wait = why; return false, why end
        end
    end
    local say = nil
    if type(row.sabotage) == "table" then
        if force ~= true then
            local away, why = Director.nobodyHome(house, now)
            if not away then pending.wait = why; return false, why end
        end
        local done = Director.sabotage(house, row.sabotage)
        pending.damage = done
        Director.notice(house, row.notice, now, nil)
        say = string.format("%d plank(s) pried, %d window(s) smashed", done.planks or 0, done.windows or 0)
        if (done.planks or 0) + (done.windows or 0) == 0 then say = say .. " (nothing to break at this house)" end
    else
        local raid = ProjectALife.RaidDirector
        local targets = Director.onlineResidents(house)
        if raid == nil or type(raid.start) ~= "function" then pending.wait = "raid director unavailable"; return false, pending.wait end
        if #targets == 0 then pending.wait = "no resident online"; return false, pending.wait end
        local rule = row.raid
        if rule.powerCut == true then pending.cut = Director.powerCut(house) end
        local ok, why = true, nil
        ok, why = raid.start(targets[1], { factionId = pending.faction, waves = rule.waves,
            waveDelayMinutes = rule.waveDelayMinutes }, true)
        say = "raid started on " .. tostring(Director.displayName(targets[1])) .. ", " .. tostring(rule.waves) .. " wave(s)"
        if not ok then pending.wait = "raid refused: " .. tostring(why); return false, pending.wait end
        if rule.powerCut == true then say = say .. "; " .. tostring(pending.cut or 0) .. " generator(s) cut" end
        if tonumber(rule.lureMinutes) ~= nil then
            local stand = Director.standOf(house) or { x = house.cx, y = house.cy, z = 0 }
            local nowMs = type(getTimestampMs) == "function" and getTimestampMs() or 0
            Director.lure = { x = math.floor(stand.x) + 8, y = math.floor(stand.y) + 8, z = stand.z or 0,
                untilMs = nowMs + rule.lureMinutes * 60000 }
        end
    end
    Director.climb(house, pending, now)
    pending.state = "delivered"
    Director.removePending(house, pending)
    Director.remember(house, { event = pending.event, faction = pending.faction, outcome = "plain", hours = now,
        debug = pending.debug })
    Director.metrics.delivered = Director.metrics.delivered + 1
    Director.dirty()
    local spot = Director.standOf(house) or { x = house.cx or 0, y = house.cy or 0 }
    return true, { rank = "lethal", x = math.floor(spot.x), y = math.floor(spot.y), say = say }
end

function Director.vehicleItems(list)
    local items = {}
    if list == nil then return items end
    local size = tonumber(Director.ask(list, "size")) or 0
    local getter = list.get
    if type(getter) == "function" then
        for index = 0, math.min(size, 200) - 1 do
            local ok, vehicle = pcall(getter, list, index)
            if ok and vehicle ~= nil then items[#items + 1] = vehicle end
        end
        return items
    end
    local array = Director.ask(list, "toArray")
    if type(array) == "table" then
        for _, vehicle in pairs(array) do
            if vehicle ~= nil and #items < 200 then items[#items + 1] = vehicle end
        end
    end
    return items
end

function Director.vehiclesNear(house, radius)
    local result = {}
    local cell = type(getCell) == "function" and getCell() or nil
    local list = nil
    if cell ~= nil and type(cell.getVehicles) == "function" then list = Director.ask(cell, "getVehicles") end
    local cx, cy = (house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2
    for _, vehicle in ipairs(Director.vehicleItems(list)) do
        local x, y = tonumber(Director.ask(vehicle, "getX")), tonumber(Director.ask(vehicle, "getY"))
        if x ~= nil and y ~= nil and (x - cx) ^ 2 + (y - cy) ^ 2 <= radius * radius then result[#result + 1] = vehicle end
    end
    return result
end

function Director.siphon(house, percent, dry)
    for _, vehicle in ipairs(Director.vehiclesNear(house, 40)) do
        local square = Director.ask(vehicle, "getSquare")
        local part = type(vehicle.getPartById) == "function" and vehicle:getPartById("GasTank") or nil
        if part ~= nil and square ~= nil and Director.ask(square, "isOutside") == true
                and Director.ask(square, "getRoom") == nil then
            local amount, capacity = tonumber(Director.ask(part, "getContainerContentAmount")), tonumber(Director.ask(part, "getContainerCapacity"))
            if amount ~= nil and capacity ~= nil and capacity > 0 then
                local take = math.min(capacity * percent / 100, amount - capacity * 0.10)
                if take >= 1 and type(part.setContainerContentAmount) == "function" then
                    if dry == true then return take end
                    part:setContainerContentAmount(amount - take)
                    if type(vehicle.transmitPartModData) == "function" then pcall(vehicle.transmitPartModData, vehicle, part) end
                    return take
                end
            end
        end
    end
    return 0
end

function Director.garden(house, percent, dry)
    local system = SFarmingSystem ~= nil and SFarmingSystem.instance or nil
    if system == nil or type(system.getLuaObjectCount) ~= "function" then return 0 end
    local ripe = {}
    local cx, cy = (house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2
    for index = 1, system:getLuaObjectCount() do
        local plant = system:getLuaObjectByIndex(index)
        if plant ~= nil and type(plant.canHarvest) == "function" and plant:canHarvest()
                and (tonumber(plant.x) or math.huge) - cx < 40 and cx - (tonumber(plant.x) or -math.huge) < 40
                and (tonumber(plant.y) or math.huge) - cy < 40 and cy - (tonumber(plant.y) or -math.huge) < 40 then
            ripe[#ripe + 1] = plant
        end
    end
    local take = math.ceil(#ripe * percent / 100)
    local taken = 0
    if dry == true then return take end
    for index = 1, take do
        local plant = ripe[index]
        if type(plant.harvestThis) == "function" and pcall(plant.harvestThis, plant) then
            if type(plant.saveData) == "function" then pcall(plant.saveData, plant) end
            taken = taken + 1
        end
    end
    return taken
end

function Director.sendLight(house, players, dry)
    local stand = Director.standOf(house)
    if stand == nil then return false end
    local args = { x1 = house.x1, y1 = house.y1, x2 = house.x2, y2 = house.y2, z = math.floor(stand.z or 0) }
    local list = type(house.door) == "table" and house.door.windows or nil
    local windows = {}
    for index = 1, math.min(6, type(list) == "table" and #list or 0) do
        windows[#windows + 1] = { x = list[index].x, y = list[index].y }
    end
    if #windows > 0 then args.windows = windows end
    if dry == true then return true, #windows end
    for _, player in ipairs(players) do
        if type(isServer) == "function" and isServer() == true then
            if type(sendServerCommand) == "function" then pcall(sendServerCommand, player, "ProjectALife", "safehouseLight", args) end
        else
            local client = ProjectALife.SafehouseClient
            if client ~= nil and type(client.light) == "function" then client.light(args) end
        end
    end
    return true, #windows
end

function Director.ambush(house, job, player)
    local service = ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function" or type(service.hostileProfileIds) ~= "function" then return false end
    local profiles = service.hostileProfileIds(3, math.floor(Director.hours() * 1000), job.faction, true)
    if type(profiles) ~= "table" or #profiles == 0 then return false end
    local ok = service.spawnEncounter(player, { requestId = tostring(job.id) .. ":ambush", encounterId = "fullscale_raid",
        mode = "roam", profile = "manhunt", profileIds = profiles, factionId = job.faction, count = #profiles,
        x = math.floor(job.x), y = math.floor(job.y), z = 0, distance = 0, separation = 2, radius = 8, atomicGroup = true,
        supportPolicy = "disabled", hostileOverride = true, playerKeepOut = 0, targetUsername = Director.username(player) })
    return ok == true
end

function Director.jobReward(player)
    local events = ProjectALife.SafehouseEvents
    local square = Director.ask(player, "getSquare")
    if square == nil or type(square.AddWorldInventoryItem) ~= "function" then return 0 end
    local placed = 0
    for _ = 1, 2 + Director.rand(2) do
        local item = Director.newItem(events.gifts[1 + Director.rand(#events.gifts)])
        if item ~= nil and pcall(square.AddWorldInventoryItem, square, item, 0.5, 0.5, 0) then placed = placed + 1 end
    end
    return placed
end

function Director.finishJob(house, job, player, now)
    local key = Director.playerKey(player)
    if job.kind == "deliver" then
        Director.deed("finished_job", key, job.faction, nil, tostring(job.id))
        Director.tell(player, "You delivered the message. They will remember it.")
    else
        Director.jobReward(player)
        Director.deed("answered_call", key, job.faction, nil, tostring(job.id))
        Director.tell(player, "Your help was needed, and it was real. They shared what they had.")
    end
end

function Director.jobTick(house, now)
    local jobs = house.jobs
    if type(jobs) ~= "table" or #jobs == 0 then return 0 end
    local worked = 0
    for index = #jobs, 1, -1 do
        local job = jobs[index]
        if now > (tonumber(job.untilHours) or 0) then
            table.remove(jobs, index)
            Director.notice(house, job.kind == "deliver" and "The days to deliver the note have run out."
                or "Whatever was happening out there is over now.", now)
            worked = 1
        else
            for _, player in ipairs(Director.onlineResidents(house)) do
                local px, py = Director.position(player)
                local d2 = px ~= nil and (px - job.x) ^ 2 + (py - job.y) ^ 2 or math.huge
                if job.ambush == true and d2 <= 2025 then
                    Director.ambush(house, job, player)
                    table.remove(jobs, index)
                    worked = 1
                    break
                elseif job.ambush ~= true and d2 <= (job.kind == "deliver" and 400 or 196) then
                    Director.finishJob(house, job, player, now)
                    table.remove(jobs, index)
                    worked = 1
                    break
                end
            end
        end
    end
    if worked > 0 then Director.dirty() end
    return worked
end

function Director.returnTick(house, now)
    local returns = house.returns
    if type(returns) ~= "table" or #returns == 0 then return 0 end
    local worked = 0
    for index = #returns, 1, -1 do
        local entry = returns[index]
        if now >= (tonumber(entry.atHours) or math.huge) then
            table.remove(returns, index)
            worked = 1
            local item = Director.rand(100) < 85 and Director.newItem(entry.fullType) or nil
            local placed = item ~= nil and ProjectALife.SafehouseDoor.place(house, { item }) or nil
            if placed ~= nil then
                Director.notice(house, "Your " .. tostring(entry.name) .. " is back by the door.", now)
            else
                Director.notice(house, "There is no sign of your " .. tostring(entry.name) .. ". The neighbour never brought it back.", now)
            end
        end
    end
    if worked > 0 then Director.dirty() end
    return worked
end

function Director.zombieList()
    if type(Director.adapters.zombies) == "function" then return Director.adapters.zombies() end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getZombieList) ~= "function" then return nil end
    return cell:getZombieList()
end

function Director.startSample(house, now, approach)
    if Director.sample ~= nil then return false end
    local stand = nil
    if type(approach) == "table" then stand = approach.stand end
    if stand == nil then stand = Director.standOf(house) end
    if stand == nil then stand = { x = house.cx, y = house.cy, z = 0 } end
    if ProjectALife.SafehouseDoor.square(stand.x, stand.y, stand.z) == nil then return false end
    Director.sample = { key = house.key, cursor = 0, n = 0, inside = 0, targeting = 0,
        x = stand.x, y = stand.y, keys = {} }
    if type(approach) == "table" then
        Director.sample.visit = { pendingId = approach.pendingId, point = approach.point, n = 0 }
    end
    for _, key in ipairs(Director.residentKeys(house)) do Director.sample.keys[key] = true end
    return true
end

function Director.sampleStep(now)
    local job = Director.sample
    if job == nil then return 0 end
    local house = Director.store().houses[job.key]
    local list = Director.zombieList()
    if house == nil or list == nil then Director.sample = nil; return 0 end
    local size = tonumber(list:size()) or 0
    local stop = math.min(size, job.cursor + Director.settings.sampleBudget)
    local reach = Director.settings.sampleRadius * Director.settings.sampleRadius
    local threat = Director.settings.zombieThreatTiles * Director.settings.zombieThreatTiles
    local started = type(getTimestampMs) == "function" and getTimestampMs() or nil
    for index = job.cursor, stop - 1 do
        if started ~= nil and index > job.cursor and (index - job.cursor) % 16 == 0
                and getTimestampMs() - started > Director.settings.sampleMs then
            stop = index
            break
        end
        local zombie = list:get(index)
        if zombie ~= nil and Director.ask(zombie, "isDead") ~= true
                and not (Director.ask(zombie, "hasModData") == true and zombie:getModData().ProjectALifeUID ~= nil) then
            local x, y = tonumber(Director.ask(zombie, "getX")), tonumber(Director.ask(zombie, "getY"))
            if x ~= nil and y ~= nil then
                if job.visit ~= nil then
                    local point = job.visit.point
                    local dx, dy = job.x - point.x, job.y - point.y
                    local length = dx * dx + dy * dy
                    local t = length > 0 and math.max(0, math.min(1,
                        ((x - point.x) * dx + (y - point.y) * dy) / length)) or 0
                    if (x - point.x - t * dx)^2 + (y - point.y - t * dy)^2 <= 64 then
                        job.visit.n = job.visit.n + 1
                    end
                end
                if (x - job.x) ^ 2 + (y - job.y) ^ 2 <= reach then job.n = job.n + 1 end
                if ProjectALife.SafehouseDoor.inBox(house, x, y) then job.inside = job.inside + 1 end
                local target = Director.ask(zombie, "getTarget")
                if target ~= nil and Director.isPlayer(target) and job.keys[Director.playerKey(target)] then
                    local tx, ty = Director.position(target)
                    if tx ~= nil and (tx - x) ^ 2 + (ty - y) ^ 2 <= threat then job.targeting = job.targeting + 1 end
                end
            end
        end
    end
    job.cursor = stop
    if stop >= size then
        house.zeds = { n = job.n, inside = job.inside, targeting = job.targeting, atHours = now }
        if job.visit ~= nil then
            house.approach = { pendingId = job.visit.pendingId, point = job.visit.point,
                n = job.visit.n, atHours = now }
        end
        Director.sample = nil
        Director.metrics.samples = Director.metrics.samples + 1
    end
    return stop
end

function Director.notePasses(house)
    local keys = type(house.door) == "table" and house.door.keys or nil
    if type(keys) ~= "table" then return 0 end
    local counted = 0
    for _, player in ipairs(Director.onlineResidents(house)) do
        local x, y = Director.position(player)
        local playerKey = Director.playerKey(player)
        if x ~= nil and playerKey ~= nil then
            local square = math.floor(x) .. "," .. math.floor(y)
            local last = Director.lastSquare[playerKey]
            if square ~= last then
                local edge = keys[square]
                if edge ~= nil and (last == nil or keys[last] ~= edge) then
                    house.passes = type(house.passes) == "table" and house.passes or {}
                    house.passes[edge] = math.min(Director.settings.passesCap, (tonumber(house.passes[edge]) or 0) + 1)
                    counted = counted + 1
                end
                Director.lastSquare[playerKey] = square
            end
        end
    end
    return counted
end

function Director.houseList()
    local keys = {}
    for key, house in pairs(Director.store().houses) do
        if type(house) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

function Director.nextHouse(now)
    local keys = Director.houseList()
    local houses = Director.store().houses
    for _ = 1, #keys do
        Director.cursor = (Director.cursor % #keys) + 1
        local house = houses[keys[Director.cursor]]
        local due = house.checkedHours == nil or now < house.checkedHours
            or now - house.checkedHours >= Director.settings.checkHours
        if due and #Director.onlineResidents(house) > 0 then return house end
    end
    return nil
end

function Director.check(house, now, opts)
    opts = type(opts) == "table" and opts or {}
    house.checkedHours = now
    Director.metrics.checks = Director.metrics.checks + 1
    local door = ProjectALife.SafehouseDoor
    if door.stale(house, now) and door.job(house) == nil then door.evaluate(house, now, door.settings.scanBudget, true) end
    Director.startSample(house, now)
    Director.memo = {}
    local result = Director.weigh(house, now, opts)
    Director.memo = nil
    house.lastOutcome = result.reason
    Director.lastOutcome = result.reason
    if result.ok then
        local pending, why = Director.compose(house, result.row, result.pick, now, false)
        if pending == nil then result.ok, result.reason = false, why; return result end
        if pending.lane == "visit" then pending.homeAtRoll = not Director.nobodyHome(house, now) end
        Director.enqueue(house, pending, now)
        Director.deliver(house, pending, now, false)
    end
    return result
end

function Director.prune(now)
    local houses = Director.store().houses
    local limit = Director.settings.pruneDays * 24
    for key, house in pairs(houses) do
        if type(house) ~= "table" then
            houses[key] = nil
        elseif house.mark == nil then
            local seen = -math.huge
            for _, resident in pairs(type(house.residents) == "table" and house.residents or {}) do
                seen = math.max(seen, tonumber(resident.seenHours) or -math.huge)
            end
            if now - seen > limit then
                Director.cleanTraces(house)
                if ProjectALife.SafehouseMarks ~= nil then ProjectALife.SafehouseMarks.clean(house) end
                houses[key] = nil
            end
        end
    end
end

function Director.tickVisits(house, first, now)
    local visit = ProjectALife.SafehouseVisit
    if visit == nil or type(visit.tick) ~= "function" or type(house.pending) ~= "table" then return 0 end
    local others = {}
    for _, pending in ipairs(house.pending) do
        if pending ~= first and pending.lane == "visit" and pending.state ~= "queued" and pending.resolved ~= true then
            others[#others + 1] = pending
        end
    end
    for _, pending in ipairs(others) do
        if pending.resolved ~= true then visit.tick(house, pending, now) end
    end
    return #others
end

Director.visitorModules = { "VisitorDirector", "VisitorEvents", "VisitorLife" }

function Director.visitorTicks()
    local work = 0
    local nowMs = type(getTimestampMs) == "function" and getTimestampMs() or nil
    for _, name in ipairs(Director.visitorModules) do
        local module = ProjectALife[name]
        if module ~= nil and type(module.tick) == "function" then work = work + (tonumber(module.tick(nowMs)) or 0) end
    end
    return work
end

function Director.stamp()
    return type(getTimestampMs) == "function" and getTimestampMs() or 0
end

function Director.part(name, started)
    local now = Director.stamp()
    local spent = now - started
    local parts = Director.metrics.partMs
    if type(parts) ~= "table" then
        parts = {}
        Director.metrics.partMs = parts
    end
    parts[name] = (parts[name] or 0) + spent
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then runtime.noteDetail("safehouse:" .. name, spent) end
    end
    return now
end

function Director.tick()
    if type(isClient) == "function" and isClient() == true then return 0 end
    local script = ProjectALife.SafehouseScript
    local effects = 0
    local began = Director.stamp()
    if script ~= nil then effects = script.tick(type(getTimestampMs) == "function" and getTimestampMs() or nil) end
    began = Director.part("script", began)
    local enabled = Director.enabledHere()
    if not enabled then
        local visit = ProjectALife.SafehouseVisit
        if visit ~= nil and type(visit.settle) == "function" then
            for _, key in ipairs(Director.houseList()) do
                local house = Director.store().houses[key]
                for _, pending in ipairs(house.pending or {}) do
                    if pending.lane == "visit" and pending.resolved ~= true then
                        visit.settle(house, pending, "disabled", nil, Director.hours())
                        return 1
                    end
                end
            end
        end
        return effects
    end
    local now = Director.hours()
    Director.metrics.ticks = Director.metrics.ticks + 1
    local work = effects
    local players = Director.players()
    if #players > 0 then
        Director.playerCursor = (Director.playerCursor % #players) + 1
        local house = Director.houseFor(players[Director.playerCursor], now)
        if house ~= nil then work = work + Director.notePasses(house) + 1 end
    end
    began = Director.part("pass", began)
    work = work + Director.sampleStep(now)
    began = Director.part("sample", began)
    local door = ProjectALife.SafehouseDoor
    local jobKeys = {}
    for key in pairs(door.jobs) do jobKeys[#jobKeys + 1] = key end
    if #jobKeys > 0 then
        table.sort(jobKeys)
        Director.jobCursor = ((tonumber(Director.jobCursor) or 0) % #jobKeys) + 1
        local key = jobKeys[Director.jobCursor]
        local house = Director.store().houses[key]
        if house == nil then door.jobs[key] = nil else door.evaluate(house, now, door.settings.scanBudget) end
        work = work + 1
    end
    began = Director.part("door", began)
    for _, key in ipairs(Director.houseList()) do
        local house = Director.store().houses[key]
        local pending = Director.hasPending(house)
        if pending ~= nil and Director.visitStale(house, pending, now) then
            work = work + 1
        elseif pending ~= nil then
            if pending.lane == "visit" and pending.state ~= "queued" and ProjectALife.SafehouseVisit ~= nil then
                ProjectALife.SafehouseVisit.tick(house, pending, now)
            else
                Director.deliver(house, pending, now, false)
            end
            work = work + 1 + Director.tickVisits(house, pending, now)
        end
    end
    began = Director.part("pending", began)
    for _, key in ipairs(Director.houseList()) do
        local house = Director.store().houses[key]
        work = work + Director.flushNotices(house, now) + Director.jobTick(house, now) + Director.returnTick(house, now)
    end
    began = Director.part("notices", began)
    work = work + Director.traceTick(now)
    if ProjectALife.SafehouseMarks ~= nil then work = work + ProjectALife.SafehouseMarks.tick(now) end
    began = Director.part("trace", began)
    if Director.lure ~= nil and type(getTimestampMs) == "function" then work = work + Director.lureTick(getTimestampMs()) end
    began = Director.part("lure", began)
    work = work + Director.visitorTicks()
    began = Director.part("visitors", began)
    local house = Director.nextHouse(now)
    if house ~= nil then
        Director.check(house, now, {})
        work = work + 1
    end
    Director.part("check", began)
    if Director.metrics.ticks % 600 == 0 then Director.prune(now) end
    return work
end

function Director.age(now, hours)
    if tonumber(hours) == nil then return "never" end
    return string.format("%.1f h ago", now - tonumber(hours))
end

function Director.stateLines(house, now)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local enabled, why = Director.enabledHere()
    add("world: " .. Director.worldKind() .. ", events " .. tostring(Director.frequencyNames[Director.settings.frequency] or "?")
        .. (enabled and "" or (" (OFF: " .. tostring(why) .. ")")))
    add(string.format("house %s (%s) box %d,%d - %d,%d", tostring(house.key), tostring(house.source),
        house.x1, house.y1, house.x2 - 1, house.y2 - 1))
    local names = {}
    local online = {}
    for _, player in ipairs(Director.onlineResidents(house)) do online[Director.playerKey(player)] = true end
    for _, key in ipairs(Director.residentKeys(house)) do
        names[#names + 1] = tostring(house.residents[key].name or key) .. (online[key] and " (online)" or " (offline)")
    end
    add("residents: " .. table.concat(names, ", "))
    local tier, tierWhy = Director.houseTier(house)
    add("house tier: " .. tier .. " (" .. tostring(tierWhy) .. ")")
    local quietEnd = (tonumber(house.flaggedHours) or now) + Director.settings.quietDays * 24
    add(string.format("flagged day %d; quiet days %d (%s)", math.floor((tonumber(house.flaggedHours) or now) / 24),
        Director.settings.quietDays, now < quietEnd and string.format("%.1f h left", quietEnd - now) or "over"))
    local door = house.door
    local job = ProjectALife.SafehouseDoor.job(house)
    if job ~= nil then
        local words = Director.doorWords[tostring(job.status or job.phase)]
        add("front door: evaluating (" .. tostring(job.status or job.phase) .. ")" .. (words ~= nil and (" -> " .. words) or ""))
    end
    if type(door) == "table" then
        local stale, staleWhy = ProjectALife.SafehouseDoor.stale(house, now)
        add(string.format("front door: mode %s, edge %s, state %s, evaluated %s%s", tostring(door.mode), tostring(door.edgeKey),
            tostring(door.state), Director.age(now, door.atHours), stale and (" STALE: " .. tostring(staleWhy)) or ""))
        if Director.modeWords[tostring(door.mode)] ~= nil then add("  -> " .. Director.modeWords[tostring(door.mode)]) end
        for index, rank in ipairs(door.ranked or {}) do
            add(string.format("  #%d %s score %d (base %d, passes %d, road %d, state %d) reach %s, %s", index,
                tostring(rank.edgeKey), rank.score, rank.base, rank.passes, rank.road, rank.penalty,
                tostring(rank.verdict), tostring(rank.state)))
        end
        local stand, mailbox = door.stand, door.mailbox
        add("stand square: " .. (stand and (stand.x .. "," .. stand.y .. "," .. stand.z) or "none")
            .. "; drop point: " .. (mailbox and ("mailbox " .. mailbox.x .. "," .. mailbox.y) or (stand and "porch" or "none"))
            .. "; region " .. tostring(door.region))
        local windows, parts = type(door.windows) == "table" and door.windows or {}, {}
        for index = 1, math.min(3, #windows) do parts[#parts + 1] = windows[index].x .. "," .. windows[index].y end
        add("windows: " .. #windows .. " usable" .. (#parts > 0 and (" (" .. table.concat(parts, "; ") .. ")") or ""))
        local survey = ProjectALife.SafehouseDoor.survey(house)
        local stood = survey.stand
        if stood ~= nil then
            add(string.format("visitor square: %d,%d,%d (%s) facing %s%s", stood.x, stood.y, stood.z or 0, tostring(stood.kind),
                Director.facingWord(stood.x, stood.y, stood.fx, stood.fy), stood.shifted > 0 and (", shifted " .. stood.shifted .. " tile(s)") or ""))
        else
            add("visitor square: NONE - " .. tostring(survey.standWhy))
        end
        local seen = {}
        for _, window in ipairs(survey.windows) do
            seen[#seen + 1] = window.x .. "," .. window.y .. (window.ok and " ok" or (" refused " .. tostring(window.why)))
        end
        if #seen > 0 then add("window survey: " .. table.concat(seen, "; ", 1, math.min(#seen, 6))) end
    elseif job == nil then
        add("front door: not evaluated")
    end
    local zeds = house.zeds
    if type(zeds) == "table" then
        add(string.format("zombies: %d near, %d inside, %d on a resident (%s), band %s", zeds.n or 0, zeds.inside or 0,
            zeds.targeting or 0, Director.age(now, zeds.atHours), Director.densityBand(house, now)))
    else
        add("zombies: not sampled" .. (Director.sample ~= nil and Director.sample.key == house.key and " (sampling)" or ""))
    end
    local ladder = {}
    for factionId, step in pairs(type(house.ladder) == "table" and house.ladder or {}) do
        ladder[#ladder + 1] = tostring(factionId) .. " step " .. tostring(type(step) == "table" and step.step or step)
    end
    add("ladder: " .. (#ladder > 0 and table.concat(ladder, ", ") or "no steps") .. " (ladder is P2)")
    local last = type(house.last) == "table" and house.last or {}
    add("last event: any " .. Director.age(now, last.any) .. ", quiet " .. Director.age(now, last.quiet)
        .. ", visit " .. Director.age(now, last.visit) .. ", lethal " .. Director.age(now, last.lethal))
    local cooldowns = {}
    for _, row in ipairs(ProjectALife.SafehouseEvents.rows) do
        local open, openWhy = Director.rowOpen(house, row, now, false)
        if not open then cooldowns[#cooldowns + 1] = row.id .. " " .. tostring(openWhy) end
    end
    add("row cooldowns: " .. (#cooldowns > 0 and table.concat(cooldowns, "; ") or "none"))
    for _, pending in ipairs(type(house.pending) == "table" and house.pending or {}) do
        local spot = type(pending.spot) == "table" and (" at the " .. tostring(pending.spot.kind) .. " " .. tostring(pending.spot.x)
            .. "," .. tostring(pending.spot.y)) or ""
        add(string.format("pending %s from %s: %s, deadline %.1f h, %s%s%s", tostring(pending.event), tostring(pending.faction),
            tostring(pending.state), (tonumber(pending.untilHours) or now) - now, tostring(pending.wait or "-"),
            pending.debug and " (debug)" or "", spot))
    end
    add("traces: " .. #(type(house.traces) == "table" and house.traces or {}) .. " items tracked; placed "
        .. tostring(ProjectALife.SafehouseDoor.metrics.tracesPlaced) .. ", removed " .. tostring(ProjectALife.SafehouseDoor.metrics.tracesRemoved))
    local fx, marks = ProjectALife.SafehouseFx, ProjectALife.SafehouseMarks
    if fx ~= nil and marks ~= nil then
        add("wall marks: " .. marks.count(house) .. " painted (cap " .. marks.settings.cap
            .. "); radio " .. tostring(fx.metrics.radioActivated) .. " on, " .. tostring(fx.metrics.radioNoDevice) .. " no device, "
            .. tostring(fx.metrics.radioNoPower) .. " no power; effects " .. tostring(fx.metrics.scriptedEffects)
            .. "; options scripted " .. tostring(Director.settings.scriptedEffects) .. " radio " .. tostring(Director.settings.radioActivate)
            .. " marks " .. tostring(Director.settings.wallMarks))
    end
    for index = 1, math.min(3, #(house.history or {})) do
        local entry = house.history[index]
        add(string.format("history: %s from %s, %s, %s%s", tostring(entry.event), tostring(entry.faction),
            tostring(entry.outcome), Director.age(now, entry.hours), entry.where and (" in the " .. entry.where) or ""))
    end
    add(string.format("visits: %d direct (debug), %d walking in, %d at a window; spawn hint: %s", Director.metrics.visitsDirect,
        Director.metrics.visitsFar, Director.metrics.windowVisits, tostring(house.lastVisitWhy or "-")))
    if house.spawnHint ~= nil then add("walk-in point search failed: " .. tostring(house.spawnHint)) end
    local nextIn = house.checkedHours and (Director.settings.checkHours - (now - house.checkedHours)) or 0
    add(string.format("next check in %.1f h; last outcome: %s", math.max(0, nextIn), tostring(house.lastOutcome or "none")))
    add("GATES:")
    for _, gate in ipairs(Director.gateState(house, now)) do
        local plain = gate.blocks and Director.gateWords[gate.id] or nil
        add("  " .. gate.id .. ": " .. (gate.blocks and "BLOCKS - " or "ok") .. (gate.blocks and tostring(gate.why) or (gate.why and (" (" .. gate.why .. ")") or ""))
            .. (plain ~= nil and (" -> " .. plain) or ""))
    end
    local gapScale, chanceScale = Director.frequencyScale()
    add(string.format("  chance: %.0f%% per check, a check every %d h, events at least %d h apart",
        math.min(1, Director.settings.chancePercent / 100 * chanceScale) * 100, Director.settings.checkHours,
        math.max(24, Director.settings.gapDays * 24 * gapScale)))
    add("VISIT ROWS (natural flow right now):")
    local openRows, visitRows = 0, 0
    Director.memo = {}
    for _, row in ipairs(ProjectALife.SafehouseEvents.rows) do
        if row.lane == "visit" then
            local called, note = pcall(Director.naturalNote, house, row, now)
            if not called then note = "error: " .. tostring(note) end
            visitRows = visitRows + 1
            if string.sub(tostring(note), 1, 4) == "open" then openRows = openRows + 1 end
            add("  " .. row.id .. ": " .. tostring(note))
        end
    end
    Director.memo = nil
    add(string.format("  %d of %d visit rows open; visit lane x%.1f at zombie density band %s", openRows, visitRows,
        Director.laneFactor(house, "visit", now), Director.densityBand(house, now)))
    while #lines > Director.settings.linesCap do table.remove(lines) end
    return lines
end

function Director.trigger(player, eventId, now)
    local events = ProjectALife.SafehouseEvents
    local row = events.row(eventId)
    if row == nil then return false, "unknown event " .. tostring(eventId) end
    local shipped, problems = events.shipCheck({ row })
    if not shipped then return false, "survival rule: " .. tostring(problems[1]) end
    local house, source = Director.houseFor(player, now)
    if house == nil then return false, "no house (" .. tostring(source) .. "): create a test base first" end
    local door = ProjectALife.SafehouseDoor
    if door.stale(house, now) then
        local done, why = door.evaluate(house, now, door.settings.debugBudget, true)
        if not done then return false, "front door not ready: " .. tostring(why) end
    end
    if house.door.mode == "none" then return false, "no reachable square outside the house: nothing is placed" end
    Director.memo = {}
    local picks, why = Director.candidates(house, row, now, false)
    local relaxed = false
    if #picks == 0 then
        if ProjectALife.SafehouseEvents.contains(row.needs, "poiNear") then
            Director.memo = nil
            return false, "no real place within 400 tiles: an honest map needs one"
        end
        picks = Director.candidates(house, row, now, true)
        relaxed = true
    end
    Director.memo = nil
    if #picks == 0 then return false, "no faction can send " .. row.id .. " (" .. tostring(why) .. ")" end
    local first = Director.rand(#picks)
    local attempts = 1
    if row.lane == "visit" then attempts = math.min(#picks, 6) end
    local note = ""
    if relaxed then note = " (nothing fit: " .. tostring(why) .. "; faction filter relaxed)" end
    Director.metrics.debugTriggers = Director.metrics.debugTriggers + 1
    local pending, ok, placed, info
    for attempt = 0, attempts - 1 do
        local pick = picks[1 + (first + attempt) % #picks]
        local whyCompose
        pending, whyCompose = Director.compose(house, row, pick, now, true)
        if pending == nil then return false, whyCompose end
        Director.enqueue(house, pending, now)
        ok, placed, info = Director.deliver(house, pending, now, true)
        if ok or row.lane ~= "visit" then break end
        Director.removePending(house, pending)
        pending.state = "debug_refused"
        if not Director.retryVisit(placed) then break end
    end
    if not ok then
        if row.lane == "visit" then
            print("[ALIFE-SAFEHOUSE] debug visit " .. row.id .. " refused: " .. tostring(placed))
            return false, row.id .. " refused: " .. tostring(placed) .. "; removed from pending" .. note
        end
        return false, row.id .. " refused: " .. tostring(placed) .. "; it waits in pending" .. note
    end
    if pending.lane == "visit" then
        return true, row.id .. " from " .. Director.factionName(pending.faction) .. ": " .. Director.visitText(info) .. note
    end
    local tail = ""
    if placed.say ~= nil then tail = " - " .. placed.say end
    return true, string.format("%s from %s placed in the %s at %d,%d%s%s", row.id, Director.factionName(pending.faction),
        placed.rank, placed.x, placed.y, tail, note)
end

function Director.retryVisit(reason)
    reason = tostring(reason)
    return reason == "profiles_unavailable" or string.sub(reason, 1, 15) == "profile_invalid"
        or reason == "spawn_refused" or string.sub(reason, 1, 14) == "faction_has_no"
end

function Director.visitText(info)
    if type(info) ~= "table" then return "visit requested" end
    local spot = info.spot
    if type(spot) ~= "table" then return "visit requested (" .. tostring(info.how or "pending") .. ")" end
    local text = string.format("visitor requested at the %s %d,%d", tostring(spot.kind), spot.x, spot.y)
    if spot.kind == "window" then
        text = text .. string.format(" facing the room %d,%d (edge %s)", spot.ix or 0, spot.iy or 0, tostring(spot.edge))
    end
    text = text .. " - " .. tostring(info.how or "pending")
    if info.note ~= nil then text = text .. "; " .. tostring(info.note) end
    return text
end

function Director.debugCommand(player, args)
    args = type(args) == "table" and args or {}
    local action = tostring(args.action or "")
    local now = Director.hours()
    local reply = { ok = false, action = action, event = args.event }
    if not Director.isPlayer(player) then reply.reason = "no_player"; return reply end
    if action == "diagnostics" then
        local lines = Director.diagnosticLines(player, args.at)
        local box = ProjectALife.BlackBox
        local saved = box ~= nil and type(box.saveReport) == "function"
            and box.saveReport("safehouse", table.concat(lines, "\n")) == true
        for index = 1, #lines do print("[ALIFE-SAFEHOUSE] " .. lines[index]) end
        reply.ok, reply.console = true, lines
        reply.say = saved and "Safehouse diagnostics saved: Lua/alife_safehouse_latest.txt (server)."
            or "Safehouse diagnostics printed; text export failed or writer unavailable."
        reply.saved = saved
        return reply
    end
    if action == "mark" then
        local ok, why, house = Director.mark(player, now, args.at)
        reply.ok, reply.reason = ok, why
        reply.say = ok and string.format("Test base created (%d,%d - %d,%d). Pick a trigger.", house.x1, house.y1, house.x2 - 1, house.y2 - 1)
            or "No building there: right-click a house, or stand inside one."
        return reply
    end
    if action == "clear" then
        local cleared = Director.clearMark(player)
        reply.ok = cleared > 0
        reply.say = cleared > 0 and "Base mark cleared." or "You have no base mark."
        return reply
    end
    if action == "state" then
        local house, source = Director.houseFor(player, now)
        if house == nil then
            reply.reason = source
            reply.lines = { "No house for you (" .. tostring(source) .. ").",
                "Providers, in order: a debug mark, a vanilla safehouse you own or belong to, the BaseHeat base.",
                "Use Mark this building as my base while standing inside." }
            local enabled, why = Director.enabledHere()
            if not enabled then reply.lines[#reply.lines + 1] = "Events are off here: " .. tostring(why) end
            return reply
        end
        reply.ok, reply.lines = true, Director.stateLines(house, now)
        return reply
    end
    if action == "trigger" then
        local note = ""
        if Director.houseFor(player, now) == nil and args.at ~= nil then
            local made, _, house = Director.mark(player, now, args.at)
            if made then note = string.format("Test base created at %d,%d - %d,%d. ", house.x1, house.y1, house.x2 - 1, house.y2 - 1) end
        end
        local ok, text = Director.trigger(player, args.event, now)
        reply.ok, reply.say = ok, note .. tostring(text)
        return reply
    end
    if action == "tick" then
        local house, source = Director.houseFor(player, now)
        if house == nil and args.at ~= nil and Director.mark(player, now, args.at) then house, source = Director.houseFor(player, now) end
        if house == nil then reply.reason, reply.say = source, "No house: right-click a house and create a test base."; return reply end
        local result = Director.check(house, now, { forced = true, skipTimers = true })
        reply.ok = result.ok == true
        reply.say = "Director check (quiet days, pacing and cooldowns skipped): " .. tostring(result.reason)
        return reply
    end
    if action == "selftest" or action == "spawnpoints" then
        local house, source = Director.houseFor(player, now)
        local note = ""
        if house == nil and args.at ~= nil then
            local made, _, fresh = Director.mark(player, now, args.at)
            if made then house, note = fresh, "Test base created. " end
        end
        if house == nil then reply.reason, reply.say = source, "No house: right-click a house and create a test base."; return reply end
        local door = ProjectALife.SafehouseDoor
        if door.stale(house, now) then
            local done, why = door.evaluate(house, now, door.settings.debugBudget, true)
            if not done then reply.say = "front door not ready: " .. tostring(why); return reply end
        end
        if house.door.mode == "none" then
            reply.say = "no reachable square outside the house: nothing can be placed"
            return reply
        end
        if action == "selftest" then
            local test = Director.selfTest(house, now)
            reply.ok, reply.console = true, test.lines
            reply.say = note .. string.format("self-test: %d ok, %d refused, see console", test.ok, test.refused)
            if type(isServer) == "function" and isServer() == true then
                for index = 1, #test.lines do print("[ALIFE-SAFEHOUSE] " .. test.lines[index]) end
            end
            return reply
        end
        local points = Director.spawnPoints(house, now)
        local good = 0
        for index = 1, #points do if points[index].ok then good = good + 1 end end
        reply.ok, reply.points = true, points
        reply.say = note .. string.format("spawn points: %d valid, %d refused (markers for 30 s)", good, #points - good)
        return reply
    end
    reply.reason = "unknown_action"
    return reply
end

Director.modeWords = {
    gate = "the yard is fenced by the player: visitors wait outside the gate",
    fence = "fenced yard with no gate: visitors call from the first free square past the fence line",
    street = "no door could be reached: visitors stand on the nearest road square",
    none = "nothing reachable outside the house: no event can be placed",
}

Director.doorWords = {
    house_unloaded = "no vanilla building was found inside the base box: the area is not loaded, or the base is not a building",
    entrances_missing = "the entrance mapper is not loaded",
    no_site = "the building has no definition to map",
    mapping = "still mapping the doors and windows",
    reach_unknown = "waiting for the reach budget, retried on the next ticks",
}

Director.gateWords = {
    enabled = "events are off in the sandbox, or this server type does not run them",
    house = "no base: mark a building, claim a safehouse or build a flagged base",
    residents = "nobody who lives here is online",
    quiet_days = "nothing happens in the first quiet days after the base is flagged",
    excluded = "the front door lies in a no-event region",
    zombies_inside = "zombies are inside the house",
    density = "too many zombies around for any event",
    in_fight = "a fight is going on; events wait for it to end",
    running = "an earlier event is still pending; it blocks new ones until it finishes or is given up",
    pacing = "events are spaced at least two days apart",
    door = "the front door square is not evaluated yet or no reachable square exists",
}

function Director.diagnosticValue(value)
    if value == nil then return "-" end
    return string.sub(string.gsub(tostring(value), "[%c]", " "), 1, 120)
end

function Director.diagnosticPoint(point)
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then return "-" end
    return string.format("%.2f,%.2f,%.2f", point.x, point.y, tonumber(point.z) or 0)
end

function Director.diagnosticStore()
    if type(Director.adapters.store) == "function" then return Director.adapters.store() end
    local persistence = ProjectALife.Persistence
    local saved = persistence ~= nil and persistence.storage or nil
    local stores = type(saved) == "table" and saved.stores or nil
    return type(stores) == "table" and stores.baseHeat or Director.fallback
end

function Director.diagnosticHouse(player, at)
    local store = Director.diagnosticStore()
    local houses = type(store) == "table" and store.houses or nil
    if type(houses) ~= "table" then return nil, "store_not_initialized", 0 end
    local key = Director.playerKey(player)
    local x, y = Director.position(player)
    if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then x, y = at.x, at.y end
    local marked, nearby, resident, scanned = nil, nil, nil, 0
    for _, house in pairs(houses) do
        if scanned >= 64 then break end
        scanned = scanned + 1
        if type(house) == "table" then
            if type(house.mark) == "table" and house.mark.by == key then marked = house end
            if type(house.residents) == "table" and key ~= nil and house.residents[key] ~= nil then resident = house end
            if x ~= nil and y ~= nil and tonumber(house.x1) ~= nil and tonumber(house.y1) ~= nil
                    and tonumber(house.x2) ~= nil and tonumber(house.y2) ~= nil
                    and x >= house.x1 and x < house.x2 and y >= house.y1 and y < house.y2 then nearby = house end
        end
    end
    return nearby or marked or resident, scanned >= 64 and "bounded_house_scan" or "existing_store", scanned
end

function Director.diagnosticAdd(lines, text)
    if #lines < 199 then lines[#lines + 1] = text end
end

function Director.diagnosticPending(house, id)
    for index = 1, math.min(#(house.pending or {}), 8) do
        local row = house.pending[index]
        if type(row) == "table" and row.lane == "visit" and row.id == id and row.resolved ~= true then return row end
    end
end

function Director.diagnosticMember(lines, house, uid, pending, expectedGeneration, now, player, reason)
    local value, point = Director.diagnosticValue, Director.diagnosticPoint
    local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
    local actor = registry ~= nil and type(registry.records) == "table" and registry.records[uid] or nil
    local memory = actor ~= nil and type(actor.memory) == "table" and actor.memory or {}
    local stamp = type(memory.visit) == "table" and memory.visit or nil
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    local shell = type(binding) == "table" and binding.shell or nil
    local x, y, z = Director.position(shell)
    local physical = x ~= nil and { x = x, y = y, z = z } or nil
    local identity = nil
    if shell ~= nil and (type(shell.hasModData) ~= "function" or Director.ask(shell, "hasModData") == true) then
        identity = Director.ask(shell, "getModData")
    end
    local identityOk = type(identity) == "table" and actor ~= nil and identity.ProjectALifeUID == uid
        and identity.ProjectALifeGeneration == actor.generation
    local shellDead, shellLoaded = Director.ask(shell, "isDead"), nil
    if shell ~= nil and type(shell.getCurrentSquare) == "function" then shellLoaded = Director.ask(shell, "getCurrentSquare") ~= nil end
    local anchor = type(memory.stanceAnchor) == "table" and memory.stanceAnchor or nil
    local expectedAnchor = pending ~= nil and type(pending.waitingSpots) == "table" and pending.waitingSpots[uid] or nil
    local distance = physical ~= nil and anchor ~= nil and tonumber(anchor.x) ~= nil and tonumber(anchor.y) ~= nil
        and math.sqrt((x - anchor.x)^2 + (y - anchor.y)^2) or nil
    local modules = ProjectALife.ModuleRegistry
    local allowed, policy = nil, "unavailable"
    if actor ~= nil and modules ~= nil and type(modules.allows) == "function" then
        local ok, answer = pcall(modules.allows, actor, "stance")
        if ok then allowed, policy = answer == true, "module_registry" else policy = "policy_read_failed" end
    end
    local valid = actor ~= nil and actor.lifecycle == "active" and pending ~= nil and pending.resolved ~= true and stamp ~= nil
        and stamp.house == house.key and stamp.pendingId == pending.id and stamp.generation == actor.generation
        and type(pending.generations) == "table" and pending.generations[uid] == actor.generation
        and now <= (tonumber(stamp.untilHours) or -math.huge)
        and now <= (tonumber(stamp.renewedHours) or -math.huge) + 3
    local findings = {}
    if reason ~= nil then findings[#findings + 1] = reason end
    if actor == nil then findings[#findings + 1] = "actor_missing"
    elseif actor.lifecycle ~= "active" then findings[#findings + 1] = "actor_" .. value(actor.lifecycle) end
    if shell == nil then findings[#findings + 1] = "physical_shell_missing"
    elseif not identityOk then findings[#findings + 1] = "shell_identity_mismatch" end
    if shellDead == true then findings[#findings + 1] = "shell_dead" end
    if shellLoaded == false then findings[#findings + 1] = "shell_unloaded" end
    if actor ~= nil and binding ~= nil and binding.generation ~= actor.generation then findings[#findings + 1] = "binding_generation_mismatch" end
    if actor ~= nil and expectedGeneration ~= nil and expectedGeneration ~= actor.generation then findings[#findings + 1] = "member_generation_mismatch" end
    if stamp ~= nil and stamp.house == house.key and Director.diagnosticPending(house, stamp.pendingId) == nil then
        findings[#findings + 1] = "orphan_stamp:pending_missing"
    end
    if pending ~= nil and not valid then findings[#findings + 1] = "visit_stamp_or_lease_invalid" end
    if stamp ~= nil and now > (tonumber(stamp.untilHours) or -math.huge) then findings[#findings + 1] = "lease_expired" end
    if stamp ~= nil and now > (tonumber(stamp.renewedHours) or -math.huge) + 3 then findings[#findings + 1] = "lease_not_renewed" end
    local stances = ProjectALife.ModuleStances
    local tolerance = stances ~= nil and stances.settings ~= nil and tonumber(stances.settings.visitTolerance) or 0.9
    local lifeApi = ProjectALife.VisitorLife
    local roaming = actor ~= nil and lifeApi ~= nil and type(lifeApi.owns) == "function" and lifeApi.owns(actor) == true
    if distance ~= nil and not roaming and (distance > tolerance or math.abs(z - (tonumber(anchor.z) or 0)) > 0.5) then
        findings[#findings + 1] = "out_of_anchor"
    end
    if stamp ~= nil and allowed == false then findings[#findings + 1] = "stance_policy_disabled" end
    Director.diagnosticAdd(lines, "member uid=" .. value(uid) .. " generation=" .. value(actor and actor.generation)
        .. " expectedGeneration=" .. value(expectedGeneration) .. " lifecycle=" .. value(actor and actor.lifecycle)
        .. " physical=" .. point(physical) .. " identity=" .. tostring(identityOk) .. " shellUid=" .. value(identity and identity.ProjectALifeUID)
        .. " shellGeneration=" .. value(identity and identity.ProjectALifeGeneration)
        .. " bindingGeneration=" .. value(binding and binding.generation) .. " dead=" .. value(shellDead) .. " loaded=" .. value(shellLoaded))
    Director.diagnosticAdd(lines, "  memoryVisit=" .. value(stamp and stamp.pendingId) .. " house=" .. value(stamp and stamp.house)
        .. " generation=" .. value(stamp and stamp.generation) .. " untilHours=" .. value(stamp and stamp.untilHours)
        .. " renewedHours=" .. value(stamp and stamp.renewedHours) .. " natural=" .. value(memory.natural)
        .. " debugSpawn=" .. value(memory.debugSpawn) .. " holdUntilMs=" .. value(stamp and stamp.holdUntilMs))
    local override = nil
    if type(memory.moduleOverrides) == "table" then override = memory.moduleOverrides.stance end
    Director.diagnosticAdd(lines, "  stance=" .. value(memory.stance) .. " anchor=" .. point(anchor)
        .. " waitingAnchor=" .. point(expectedAnchor) .. " stanceAllowed=" .. value(allowed) .. " policy=" .. policy
        .. " override=" .. value(override)
        .. " profile=" .. value(memory.behaviorProfile) .. " distanceToAnchor=" .. (distance ~= nil and string.format("%.2f", distance) or "-"))
    local decisions = ProjectALife.DecisionLoop
    local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[uid] or nil
    local order = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders[uid] or nil
    local action = type(state) == "table" and state.action or nil
    Director.diagnosticAdd(lines, "  decision=" .. value(state and state.kind) .. " intent=" .. value(state and state.intent)
        .. " activity=" .. value(actor and actor.activity) .. " actorIntent=" .. value(actor and actor.intent)
        .. " order=" .. value(order and order.kind) .. " orderGeneration=" .. value(order and order.generation)
        .. " orderUntilMs=" .. value(order and order.untilMs) .. " orderAnchor=" .. point(order and order.anchor)
        .. " movementGoal=" .. point(type(action) == "table" and action.target or nil))
    local guestLife = ProjectALife.GuestLife
    if guestLife ~= nil and type(guestLife.explain) == "function" and memory.guest ~= nil then
        local read, text = pcall(guestLife.explain, uid)
        Director.diagnosticAdd(lines, "  guestLife=" .. (read and tostring(text) or "explain_failed"))
    end
    local choices, choiceReason = {}, "not_a_valid_dialogue_peer"
    local visit = ProjectALife.SafehouseVisit
    if valid and identityOk and shellDead == false and shellLoaded ~= false and player ~= nil and type(house.residents) == "table"
            and house.residents[Director.playerKey(player)] ~= nil and visit ~= nil and type(visit.choices) == "function" then
        local peerOk, peer = false, nil
        if type(visit.doorPeer) == "function" then peerOk, peer = pcall(visit.doorPeer, player, uid) end
        local read, answer = false, nil
        if peerOk and peer ~= nil then read, answer = pcall(visit.choices, uid, player) end
        if read and type(answer) == "table" then
            local scanned = 0
            for intent, enabled in pairs(answer) do
                scanned = scanned + 1
                if scanned > 48 then break end
                if enabled == true then choices[#choices + 1] = value(intent) end
            end
            table.sort(choices)
            choiceReason = #choices > 0 and "server_choices" or "state_has_no_choices"
        elseif peerOk and peer == nil then choiceReason = "outside_server_dialogue_range"
        else choiceReason = "choices_or_peer_read_failed" end
    end
    Director.diagnosticAdd(lines, "  dialogue=" .. choiceReason .. " choices=" .. table.concat(choices, ",")
        .. " diagnosis=" .. (#findings > 0 and table.concat(findings, ";") or "identity_and_lease_valid"))
    local explanation = "Identity and visit lease are valid."
    if actor == nil then explanation = "The visit references an actor that is absent from the registry."
    elseif shell == nil then explanation = "The actor record exists, but no physical shell is currently bound."
    elseif not identityOk then explanation = "The bound shell has a different UID or generation; it is not this visitor."
    elseif shellDead == true then explanation = "The physical visitor shell is dead; the visit may be waiting to settle."
    elseif shellLoaded == false then explanation = "The visitor shell is bound but its current square is unloaded or missing."
    elseif reason == "settled_generation_reused" then explanation = "This UID now belongs to a newer generation; the old settled visitor is not the current shell."
    elseif reason == "settled_visitor_in_new_visit" then explanation = "The earlier visit settled; this actor now carries a different visit stamp."
    elseif reason == "visitor_exists_visit_removed" then explanation = "The physical visitor still exists, but the recorded visit settled and was removed."
    elseif stamp ~= nil and stamp.house == house.key and Director.diagnosticPending(house, stamp.pendingId) == nil then
        explanation = "The actor carries an orphan visit stamp: no current pending visit matches it."
    elseif pending ~= nil and not valid then explanation = "The actor's visit identity or lease does not match the current pending visit."
    elseif allowed == false then explanation = "The stance module policy disables waiting at the visit anchor."
    elseif roaming then explanation = "The admitted guest is moving around the house under the visitor life director."
    elseif distance ~= nil and distance > tolerance then explanation = "The visitor is away from its waiting anchor; server door dialogue may be unavailable."
    end
    Director.diagnosticAdd(lines, "  explanation=" .. explanation)
end

function Director.diagnosticHouseLines(lines, house, player, now)
    local value, point = Director.diagnosticValue, Director.diagnosticPoint
    local door = type(house.door) == "table" and house.door or {}
    Director.diagnosticAdd(lines, "house=" .. value(house.key) .. " source=" .. value(house.source)
        .. " bounds=" .. value(house.x1) .. "," .. value(house.y1) .. " - " .. value(house.x2) .. "," .. value(house.y2)
        .. " z=" .. value(house.z) .. " pending=" .. #(house.pending or {}) .. " history=" .. #(house.history or {}))
    Director.diagnosticAdd(lines, "door mode=" .. value(door.mode) .. " state=" .. value(door.state)
        .. " outside=" .. point({ x = door.sx, y = door.sy, z = door.z })
        .. " inside=" .. point({ x = door.ix, y = door.iy, z = door.z }) .. " stand=" .. point(door.stand)
        .. " edge=" .. value(door.edgeKey) .. " evaluatedHours=" .. value(door.atHours)
        .. " stale=" .. value(door.stale) .. " reason=" .. value(door.reason))
    local seen, members, visits = {}, 0, 0
    for index = 1, math.min(#(house.pending or {}), 8) do
        local pending = house.pending[index]
        if type(pending) == "table" and pending.lane == "visit" then
            visits = visits + 1
            Director.diagnosticAdd(lines, "pending=" .. value(pending.id) .. " event=" .. value(pending.event)
                .. " state=" .. value(pending.state) .. " resolved=" .. value(pending.resolved)
                .. " untilHours=" .. value(pending.untilHours) .. " remainingHours=" .. value(tonumber(pending.untilHours) and pending.untilHours - now)
                .. " spawn=" .. point(pending.spawn) .. " waitingSpot=" .. point(pending.spot)
                .. " entryKind=" .. value(pending.spot and pending.spot.kind)
                .. " entryInside=" .. point(pending.spot and { x = pending.spot.ix, y = pending.spot.iy, z = pending.spot.z })
                .. " facing=" .. point(pending.spot and { x = pending.spot.fx, y = pending.spot.fy, z = pending.spot.z })
                .. " seenThisSession=" .. value(ProjectALife.SafehouseVisit and ProjectALife.SafehouseVisit.seen and ProjectALife.SafehouseVisit.seen[pending]))
            for position = 1, math.min(#(pending.uids or {}), 8) do
                local uid = pending.uids[position]
                seen[uid], members = true, members + 1
                Director.diagnosticMember(lines, house, uid, pending, pending.generations and pending.generations[uid], now, player)
            end
        end
    end
    for index = 1, math.min(#(house.history or {}), 8) do
        local history = house.history[index]
        if type(history) == "table" then
            Director.diagnosticAdd(lines, "settled pending=" .. value(history.id) .. " event=" .. value(history.event)
                .. " outcome=" .. value(history.outcome) .. " reason=" .. value(history.reason)
                .. " previousState=" .. value(history.previousState) .. " atHours=" .. value(history.hours)
                .. " spawn=" .. point(history.spawn) .. " waitingSpot=" .. point(history.spot))
            for position = 1, math.min(#(history.uids or {}), 8) do
                local uid = history.uids[position]
                if not seen[uid] then
                    seen[uid], members = true, members + 1
                    local watchdog = ProjectALife.Watchdog
                    local binding = watchdog and watchdog.bindings and watchdog.bindings[uid]
                    local actor = ProjectALife.ActorRegistry and ProjectALife.ActorRegistry.records and ProjectALife.ActorRegistry.records[uid]
                    local stamp = actor and actor.memory and actor.memory.visit
                    local reason = "settled_visitor_shell_absent"
                    if actor ~= nil and type(history.generations) == "table" and history.generations[uid] ~= nil
                            and history.generations[uid] ~= actor.generation then
                        reason = "settled_generation_reused"
                    elseif type(stamp) == "table" and stamp.pendingId ~= history.id then
                        reason = "settled_visitor_in_new_visit"
                    elseif binding ~= nil and binding.shell ~= nil then reason = "visitor_exists_visit_removed" end
                    Director.diagnosticMember(lines, house, uid, nil, history.generations and history.generations[uid], now, player, reason)
                end
            end
        end
    end
    local registry = ProjectALife.ActorRegistry
    local order = registry ~= nil and type(registry.order) == "table" and registry.order or {}
    local scanned = math.min(#order, 256)
    for index = 1, scanned do
        local uid = order[index]
        local actor = registry.records and registry.records[uid]
        local stamp = actor and type(actor.memory) == "table" and actor.memory.visit or nil
        if type(stamp) == "table" and stamp.house == house.key and not seen[uid] then
            seen[uid], members = true, members + 1
            Director.diagnosticMember(lines, house, uid, Director.diagnosticPending(house, stamp.pendingId), stamp.generation, now, player)
        end
    end
    Director.diagnosticAdd(lines, "counts visits=" .. visits .. " memberRows=" .. members .. " actorRowsScanned=" .. scanned
        .. " actorScanLimited=" .. tostring(#order > scanned) .. " pendingScanLimited=" .. tostring(#(house.pending or {}) > 8)
        .. " historyScanLimited=" .. tostring(#(house.history or {}) > 8))
end

function Director.diagnosticLines(player, at)
    local catalog = ProjectALife.Catalog
    local lines = { "=== SAFEHOUSE DIAGNOSTICS (read-only, bounded) ===",
        "build=" .. Director.diagnosticValue(catalog and catalog.BUILD_STAMP) .. " worldHours=" .. Director.hours() }
    if type(isClient) == "function" and isClient() == true then
        lines[#lines + 1] = "server_authority_required"
        return lines
    end
    if player ~= nil then
        local house, why, scanned = Director.diagnosticHouse(player, at)
        lines[#lines + 1] = "selection=" .. tostring(why) .. " houseRowsScanned=" .. tostring(scanned)
        if house ~= nil then Director.diagnosticHouseLines(lines, house, player, Director.hours())
        else lines[#lines + 1] = "No existing safehouse selected; no base was created." end
    else
        local store = Director.diagnosticStore()
        local houses = type(store) == "table" and store.houses or {}
        local count = 0
        if type(houses) == "table" then
            for _, house in pairs(houses) do
                if count >= 4 then Director.diagnosticAdd(lines, "houseScanLimited=true limit=4"); break end
                count = count + 1
                if type(house) == "table" then Director.diagnosticHouseLines(lines, house, nil, Director.hours()) end
            end
        end
        if count == 0 then lines[#lines + 1] = "No initialized safehouse store." end
    end
    if #lines >= 199 then lines[#lines + 1] = "reportLimited=true limit=200 lines" end
    return lines
end

function Director.diagnosticText(player, at)
    return table.concat(Director.diagnosticLines(player, at), "\n")
end

function Director.rowKind(row)
    if row.lane == "visit" then
        if row.at == "window" then return "visit_window" end
        return "visit_door"
    end
    if row.letter ~= nil then return "letter" end
    if row.camp ~= nil then return "camp" end
    if row.mark ~= nil then return "mark" end
    if row.opens == true then return "door_open" end
    if row.siphon ~= nil then return "fuel" end
    if row.garden ~= nil then return "garden" end
    if row.home == true then
        if row.light == true then return "light" end
        return "notice"
    end
    if row.sabotage ~= nil then return "sabotage" end
    if type(row.raid) == "table" then
        return "raid"
    end
    return "unknown"
end

function Director.facingWord(x, y, fx, fy)
    if tonumber(fx) == nil or tonumber(fy) == nil then return "-" end
    local dx, dy = fx - (x + 0.5), fy - (y + 0.5)
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return "-" end
    return Director.compass(dx, dy)
end

function Director.naturalNote(house, row, now)
    local open, why = Director.rowOpen(house, row, now, false)
    if not open then return "closed: " .. tostring(why) end
    local picks, pickWhy = Director.candidates(house, row, now, false)
    if #picks == 0 then return "closed: " .. tostring(pickWhy) end
    if row.lane == "visit" and Director.laneFactor(house, "visit", now) <= 0 then
        return "closed: zombie density band " .. Director.densityBand(house, now) .. " (visits need a low zombie count)"
    end
    return "open (" .. #picks .. " faction(s))"
end

function Director.dryVisit(house, kind)
    local door = ProjectALife.SafehouseDoor
    local out = { ok = false, entry = "-", facing = "-", reason = "-" }
    local spot, note = door.visitSpot(house, kind == "visit_window" and "window" or "door", 0, nil, nil, true)
    if spot == nil then out.reason = tostring(note); return out end
    out.entry, out.at = tostring(spot.kind), { x = spot.x, y = spot.y, z = spot.z or 0 }
    out.facing = Director.facingWord(spot.x, spot.y, spot.fx, spot.fy)
    out.ok, out.reason = true, note
    local policy = ProjectALife.SpawnPolicy
    if policy ~= nil and type(policy.probeExact) == "function" then
        local allowed, why = policy.probeExact(spot.x, spot.y, spot.z or 0)
        if allowed ~= true then out.ok, out.reason = false, "spawn policy refuses the square (" .. tostring(why) .. ")" end
    end
    if out.ok then
        local _, zombies = door.occupants(door.square(spot.x, spot.y, spot.z or 0), 3)
        if zombies > 0 then out.reason = (out.reason ~= nil and (out.reason .. "; ") or "") .. zombies .. " zombie(s) within 3 tiles" end
    end
    return out
end

function Director.dryRow(house, row, now)
    local door = ProjectALife.SafehouseDoor
    local kind = Director.rowKind(row)
    local out = { id = row.id, lane = row.lane, kind = kind, ok = false, entry = "-", facing = "-", reason = "-" }
    local stand = Director.standOf(house)
    local shipped, problems = ProjectALife.SafehouseEvents.shipCheck({ row })
    if not shipped then out.reason = "survival rule: " .. tostring(problems[1]); return out end
    if row.persons == true or row.lane == "visit" then
        local ready, why = Director.personsReady(house, row, now)
        if not ready then out.reason = "no person can come (" .. tostring(why) .. ")"; return out end
    end
    if kind == "visit_door" or kind == "visit_window" then
        local plan = Director.dryVisit(house, kind)
        plan.id, plan.lane, plan.kind = row.id, row.lane, kind
        return plan
    end
    if kind == "letter" then
        local placed, why = door.place(house, {}, true)
        if placed == nil then out.reason = tostring(why); return out end
        out.ok, out.entry, out.at = true, tostring(placed.rank), { x = placed.x, y = placed.y, z = placed.z }
        return out
    end
    if kind == "camp" then
        if stand == nil then out.reason = "no_stand_square"; return out end
        local report, why = door.scatter(house, stand, { litter = { {}, {}, {} }, fire = {}, rand = Director.rand }, true)
        if report == nil then out.reason = tostring(why); return out end
        out.entry, out.at = "yard", { x = stand.x, y = stand.y, z = stand.z or 0 }
        out.ok = report.squares >= 3
        out.reason = report.squares .. " free squares within " .. report.far .. " tile(s)"
        if not out.ok then out.reason = "only " .. out.reason end
        return out
    end
    if kind == "mark" then
        if stand == nil then out.reason = "no_stand_square"; return out end
        out.ok, out.entry, out.at = true, "door", { x = stand.x, y = stand.y, z = stand.z or 0 }
        out.reason = "notice only"
        local marks = ProjectALife.SafehouseMarks
        if marks ~= nil and type(marks.dry) == "function" then
            local fits, wall = marks.dry(house)
            out.entry = fits and "wall" or "door"
            if fits then out.at = { x = wall.x, y = wall.y, z = wall.z } end
            out.reason = fits and ("a " .. (wall.north and "north" or "west") .. " wall segment is free") or ("notice only: " .. tostring(wall))
        end
        return out
    end
    if kind == "door_open" then
        local opened, why = Director.openFrontDoor(house, true, true)
        local at = house.door
        out.ok, out.entry, out.reason = opened == true, tostring(type(at) == "table" and at.mode or "-"), tostring(why)
        if type(at) == "table" and at.sx ~= nil then out.at = { x = at.sx, y = at.sy, z = at.z or 0 } end
        return out
    end
    if kind == "fuel" or kind == "garden" then
        local taken
        if kind == "fuel" then taken = Director.siphon(house, row.siphon, true) else taken = Director.garden(house, row.garden, true) end
        out.ok, out.entry = taken > 0, kind == "fuel" and "vehicle" or "crops"
        if kind == "fuel" then
            out.reason = out.ok and string.format("%.1f units available", taken) or "no car in the open within 40 tiles"
        else
            out.reason = out.ok and (taken .. " ripe plant(s)") or "no ripe crops within 40 tiles"
        end
        return out
    end
    if kind == "light" then
        local sent, windows = Director.sendLight(house, {}, true)
        if sent ~= true then out.reason = "no stand square"; return out end
        out.ok, out.entry = true, "windows"
        out.reason = (windows or 0) > 0 and (windows .. " window(s) swept") or "house edge (no window mapped)"
        return out
    end
    if kind == "notice" then
        local online = Director.onlineResidents(house)
        out.ok, out.entry = #online > 0, "resident"
        local script = ProjectALife.SafehouseScript
        if #online > 0 and type(row.fx) == "string" and script ~= nil and type(script.dry) == "function" then
            out.entry, out.reason = row.fx, script.dry(online[1], row)
            local x, y, z = Director.position(online[1])
            if x ~= nil then out.at = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) } end
            return out
        end
        if #online > 0 then
            local x, y, z = Director.position(online[1])
            if x ~= nil then out.at = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) } end
        end
        out.reason = #online > 0 and (#online .. " resident(s) told") or "no resident online"
        return out
    end
    if kind == "sabotage" then
        local done = Director.sabotage(house, row.sabotage, true)
        out.ok, out.entry = true, "house"
        if stand ~= nil then out.at = { x = stand.x, y = stand.y, z = stand.z or 0 } end
        out.reason = done.planks .. " plank(s), " .. done.windows .. " window(s)"
        if done.planks + done.windows == 0 then out.reason = out.reason .. " (nothing to break: notice only)" end
        return out
    end
    if kind == "raid" then
        local raid = ProjectALife.RaidDirector
        local online = Director.onlineResidents(house)
        out.entry = "raid_director"
        if raid == nil or type(raid.start) ~= "function" then out.reason = "raid director unavailable"; return out end
        if #online == 0 then out.reason = "no resident online"; return out end
        local x, y, z = Director.position(online[1])
        if x ~= nil then out.at = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) } end
        out.ok = true
        out.reason = tostring(row.raid.waves or 1) .. " wave(s) round " .. Director.displayName(online[1])
        return out
    end
    out.reason = "unknown row kind"
    return out
end

function Director.arrivalLine(house)
    local door, visit = ProjectALife.SafehouseDoor, ProjectALife.SafehouseVisit
    local spot = door.standSpot(house)
    local head = "selftest arrival ok=%s at=%s entry=walk-in facing=- reason=%s"
    if visit == nil or spot == nil then return string.format(head, "false", "-", "no visitor square") end
    local point, refused = visit.spawnPoint(house, spot)
    if point == nil then
        return string.format(head, "false", "-", "no walk-in point (" .. door.reasonText(refused) .. ")")
    end
    local distance = math.sqrt((point.x - spot.x) ^ 2 + (point.y - spot.y) ^ 2)
    return string.format(head, "true", math.floor(point.x) .. "," .. math.floor(point.y) .. "," .. math.floor(point.z or 0),
        string.format("%.0f tiles from the door", distance))
end

function Director.selfTest(house, now)
    local rows, lines, good = {}, {}, 0
    Director.memo = {}
    for _, row in ipairs(ProjectALife.SafehouseEvents.rows) do
        local called, result = pcall(Director.dryRow, house, row, now)
        if not called then
            result = { id = row.id, lane = row.lane, ok = false, entry = "-", facing = "-", reason = "error: " .. tostring(result) }
        end
        local noted, natural = pcall(Director.naturalNote, house, row, now)
        if not noted then natural = "error: " .. tostring(natural) end
        rows[#rows + 1] = result
        if result.ok then good = good + 1 end
        local at = type(result.at) == "table" and (result.at.x .. "," .. result.at.y .. "," .. result.at.z) or "-"
        lines[#lines + 1] = string.format("selftest %s ok=%s at=%s entry=%s facing=%s reason=%s | natural=%s", tostring(row.id),
            tostring(result.ok == true), at, tostring(result.entry), tostring(result.facing), tostring(result.reason), tostring(natural))
    end
    Director.memo = nil
    local arrived, arrival = pcall(Director.arrivalLine, house)
    lines[#lines + 1] = arrived and arrival or ("selftest arrival ok=false at=- entry=walk-in facing=- reason=error: " .. tostring(arrival))
    return { rows = rows, lines = lines, ok = good, refused = #rows - good }
end

function Director.spawnPoints(house, now)
    local survey = ProjectALife.SafehouseDoor.survey(house)
    local points = {}
    local stood = survey.stand
    if stood ~= nil then
        local label = tostring(stood.kind) .. " " .. Director.facingWord(stood.x, stood.y, stood.fx, stood.fy)
        if stood.shifted > 0 then label = label .. " (shifted " .. stood.shifted .. ")" end
        points[#points + 1] = { x = stood.x, y = stood.y, z = stood.z or 0, kind = stood.kind, ok = true, label = label }
    elseif survey.base ~= nil then
        points[#points + 1] = { x = survey.base.x, y = survey.base.y, z = survey.base.z or 0, kind = "door", ok = false,
            label = "door refused: " .. tostring(survey.standWhy) }
    end
    for _, window in ipairs(survey.windows) do
        if #points < 24 then
            local label = "window " .. Director.facingWord(window.x, window.y, window.fx, window.fy)
            if not window.ok then label = "window refused: " .. tostring(window.why) end
            points[#points + 1] = { x = window.x, y = window.y, z = window.z or 0, kind = "window", ok = window.ok == true, label = label }
        end
    end
    return points
end

do
    local ok, problems = ProjectALife.SafehouseEvents.shipCheck()
    if not ok then
        for index = 1, #problems do print("[ALIFE-SAFEHOUSE] survival rule refused: " .. tostring(problems[index])) end
    end
end

return Director
