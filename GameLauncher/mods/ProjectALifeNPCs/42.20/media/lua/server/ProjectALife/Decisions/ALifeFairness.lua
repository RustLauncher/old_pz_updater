ProjectALife = ProjectALife or {}

local Fair = {
    defaults = {
        tell = true,
        graceMs = 2500,
        warnLeadMs = 1500,
        entryLeadMs = 1500,
        windowOpenMs = 1200,
        fightMemoryHours = 1,
    },
    shoutEarshot = 40,
    hearFloors = 2,
    entryEarshot = 20,
    viewRange = 30,
    nightViewRange = 12,
    viewDegrees = 160,
    tellMemoryMs = 60000,
    lostSightMs = 3000,
    sightEveryMs = 250,
    announceEveryMs = 90000,
    turnedTellMs = 60000,
    cacheMs = 5000,
    limit = 256,
    warnEvent = "WARN_BEFORE_ATTACK",
    announceEvent = "ANNOUNCE_ENTRY",
    tells = {},
    sightings = {},
    announced = {},
    speakers = {},
    sizes = { tells = 0, sightings = 0, announced = 0, speakers = 0 },
    metrics = { held = 0, warned = 0, silent = 0, seen = 0, fought = 0, entries = 0,
        announced = 0, refusedOff = 0, opened = 0, relayed = 0, kos = 0, expired = 0, covered = 0 },
    adapters = {},
}
ProjectALife.Fairness = Fair

function Fair.configure(adapters)
    Fair.adapters = type(adapters) == "table" and adapters or {}
    Fair.cached = nil
end

function Fair.reset()
    Fair.tells, Fair.sightings, Fair.announced, Fair.speakers = {}, {}, {}, {}
    Fair.sizes = { tells = 0, sightings = 0, announced = 0, speakers = 0 }
    Fair.metrics = { held = 0, warned = 0, silent = 0, seen = 0, fought = 0, entries = 0,
        announced = 0, refusedOff = 0, opened = 0, relayed = 0, kos = 0, expired = 0, covered = 0 }
    Fair.cached = nil
end

function Fair.count(name)
    Fair.metrics[name] = (Fair.metrics[name] or 0) + 1
end

function Fair.now()
    if type(Fair.adapters.nowMs) == "function" then return Fair.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Fair.worldHours()
    if type(Fair.adapters.worldHours) == "function" then return tonumber(Fair.adapters.worldHours()) end
    if type(getGameTime) ~= "function" then return nil end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return nil end
    return tonumber(clock:getWorldAgeHours())
end

function Fair.current()
    local settings = ProjectALife.Settings
    if type(settings) ~= "table" or type(settings.read) ~= "function" then return nil end
    local ok, value = pcall(settings.read, nil, true)
    if ok and type(value) == "table" then return value end
    return nil
end

function Fair.millis(seconds, fallback)
    local value = tonumber(seconds)
    if value == nil then return fallback end
    return math.floor(value * 1000 + 0.5)
end

function Fair.settings(now)
    now = now or Fair.now()
    local cached = Fair.cached
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Fair.cacheMs then return cached end
    local d = Fair.defaults
    local value = { atMs = now, tell = d.tell, graceMs = d.graceMs, warnLeadMs = d.warnLeadMs,
        entryLeadMs = d.entryLeadMs, windowOpenMs = d.windowOpenMs,
        fightMemoryHours = d.fightMemoryHours, hostileOff = false }
    local current = Fair.current()
    if type(current) == "table" then
        value.hostileOff = current.hostileEnabled == false
        if type(current.fairTell) == "boolean" then value.tell = current.fairTell end
        value.graceMs = Fair.millis(current.fairGraceSeconds, value.graceMs)
        value.warnLeadMs = Fair.millis(current.fairWarningLeadSeconds, value.warnLeadMs)
        value.entryLeadMs = Fair.millis(current.fairEntryLeadSeconds, value.entryLeadMs)
        value.windowOpenMs = Fair.millis(current.fairWindowOpenSeconds, value.windowOpenMs)
        local minutes = tonumber(current.fairFightMemoryMinutes)
        if minutes ~= nil then value.fightMemoryHours = minutes / 60 end
    end
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.holdMs) == "function" then
        local ceiling = warning.holdMs()
        value.graceMs = math.min(value.graceMs, ceiling)
        value.warnLeadMs = math.min(value.warnLeadMs, ceiling)
        value.entryLeadMs = math.min(value.entryLeadMs, ceiling)
    end
    Fair.cached = value
    return value
end

function Fair.kos(actor, hook, player, now)
    local warning = ProjectALife.ModuleWarning
    return warning ~= nil and type(warning.kos) == "function" and warning.kos(actor, hook, player, now) == true
end

function Fair.given(kind)
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.given) == "function" then warning.given(kind) end
end

function Fair.hostileOff(now)
    return Fair.settings(now).hostileOff == true
end

function Fair.isPlayer(target)
    if target == nil or type(instanceof) ~= "function" then return false end
    local kind = type(target)
    if kind ~= "table" and kind ~= "userdata" then return false end
    return instanceof(target, "IsoPlayer") == true
end

function Fair.keyOf(player)
    if player == nil then return nil end
    if type(player) == "string" then return player end
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.playerKey) == "function" then
        local key = reputation.playerKey(player)
        if key ~= nil then return tostring(key) end
    end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.playerKey) == "function" then return speech.playerKey(player) end
    return nil
end

function Fair.memoryOf(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) == "table" then return memory end
    return nil
end

function Fair.pairId(actor, key)
    return tostring(actor.uid) .. "|" .. tostring(key)
end

function Fair.underAttack(actor, player, now)
    if type(actor) ~= "table" or player == nil then return false end
    local perception = ProjectALife.Perception
    local held = perception ~= nil and type(perception.attackers) == "table" and perception.attackers[actor.uid] or nil
    if type(held) == "table" and held.attacker == player and now < (tonumber(held.untilMs) or -1e12) then
        return true
    end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.isSelfDefence) == "function"
            and relations.isSelfDefence(actor, player, now) == true then
        return true
    end
    local risk = ProjectALife.Risk
    local key = Fair.keyOf(player)
    if risk ~= nil and type(risk.attacked) == "table" and key ~= nil then
        local memory = Fair.memoryOf(actor) or {}
        local group = risk.attacked[tostring(memory.groupId or memory.outpostId or actor.uid)]
        if type(group) == "table" and now < (tonumber(group["player:" .. key]) or 0) then return true end
    end
    return false
end

function Fair.grudge(actor, key)
    local memory = Fair.memoryOf(actor)
    return key ~= nil and memory ~= nil and type(memory.hostileToPlayerKeys) == "table"
        and memory.hostileToPlayerKeys[key] == true
end

function Fair.adminHostile(actor)
    local memory = Fair.memoryOf(actor)
    if memory == nil then return false end
    if memory.spawnStance == "hostile" then return true end
    return memory.debugSpawn == true and memory.hostileOverride == true
end

function Fair.ordered(actor, player)
    local relations = ProjectALife.Relations
    return relations ~= nil and type(relations.orderedHostile) == "function"
        and relations.orderedHostile(actor, player) == true
end

function Fair.mayInitiate(actor, player, now)
    if type(actor) ~= "table" or not Fair.isPlayer(player) then return true end
    now = now or Fair.now()
    if not Fair.hostileOff(now) then return true end
    if Fair.adminHostile(actor) then return true end
    if Fair.ordered(actor, player) and actor.memory.debugSpawn == true then return true end
    if Fair.grudge(actor, Fair.keyOf(player)) then return true end
    return Fair.underAttack(actor, player, now)
end

function Fair.explicitFriend(actor, player)
    local catalog, layers = ProjectALife.Catalog, ProjectALife.RelationLayers
    if type(actor) ~= "table" or catalog == nil or layers == nil or type(catalog.faction) ~= "function"
            or type(layers.towardPlayer) ~= "function" then
        return false
    end
    local faction = catalog.faction(actor.factionId)
    if type(faction) ~= "table" then return false end
    local profession = nil
    if Fair.isPlayer(player) and type(layers.professionOf) == "function" then profession = layers.professionOf(player) end
    local word, layer = layers.towardPlayer(faction, profession)
    return (word == "friendly" or word == "allied") and (layer == "faction" or layer == "profession")
end

function Fair.earnedHostility(actor, player)
    if Fair.adminHostile(actor) or Fair.grudge(actor, Fair.keyOf(player)) then return true end
    if Fair.ordered(actor, player) then return true end
    local reputation = ProjectALife.Reputation
    if player ~= nil and reputation ~= nil and type(reputation.recordedStatus) == "function" then
        local ok, status = pcall(reputation.recordedStatus, player, actor)
        if ok and status == "hostile" then return true end
    end
    return false
end

function Fair.hostilityStands(actor, player, now)
    if not Fair.mayInitiate(actor, player, now) then return false end
    if Fair.explicitFriend(actor, player) and not Fair.earnedHostility(actor, player) then return false end
    return true
end

function Fair.stanceFor(actor, player, stance)
    if stance ~= "hostile" then return stance end
    if not Fair.mayInitiate(actor, player) then return "careful" end
    if Fair.explicitFriend(actor, player) and not Fair.earnedHostility(actor, player) then return "friendly" end
    return stance
end

function Fair.openedBetween(npc, player)
    if not Fair.isPlayer(player) then return false end
    local relations = ProjectALife.Relations
    local record = npc
    if relations ~= nil and type(relations.actorRecord) == "function" then record = relations.actorRecord(npc) end
    if type(record) ~= "table" then return false end
    return Fair.opened(record, Fair.keyOf(player))
end

function Fair.opened(record, key, hours)
    local memory = Fair.memoryOf(record)
    local map = memory ~= nil and memory.fairOpened or nil
    local at = type(map) == "table" and key ~= nil and tonumber(map[key]) or nil
    if at == nil then return false end
    hours = hours or Fair.worldHours()
    if hours == nil then return false end
    return hours >= at and hours - at <= Fair.settings().fightMemoryHours
end

function Fair.startedFight(record, player, now)
    if type(record) ~= "table" or player == nil then return false end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.wasAggressor) == "function"
            and relations.wasAggressor(record, player, now) == true then
        return true
    end
    return Fair.opened(record, Fair.keyOf(player))
end

function Fair.writeMemory(actor, key, value)
    if type(actor.memory) ~= "table" then actor.memory = {} end
    actor.memory[key] = value
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.peek) ~= "function" or type(registry.updateTransient) ~= "function" then
        return false
    end
    local current = registry.peek(actor.uid)
    if current == nil then return false end
    return registry.updateTransient(current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        record.memory[key] = value
    end, true) == true
end

function Fair.noteOpened(actor, player, now)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or not Fair.isPlayer(player) then return false end
    now = now or Fair.now()
    if Fair.underAttack(actor, player, now) then return false end
    local key, hours = Fair.keyOf(player), Fair.worldHours()
    if key == nil or hours == nil then return false end
    local memory = Fair.memoryOf(actor)
    local old = memory ~= nil and memory.fairOpened or nil
    local stamped = type(old) == "table" and tonumber(old[key]) or nil
    if stamped ~= nil and hours >= stamped and hours - stamped < 0.05 then return true end
    local keep = Fair.settings(now).fightMemoryHours
    local map = {}
    if type(old) == "table" then
        for other, at in pairs(old) do
            if tonumber(at) ~= nil and hours - at <= keep then map[other] = at end
        end
    end
    map[key] = hours
    Fair.writeMemory(actor, "fairOpened", map)
    Fair.count("opened")
    return true
end

function Fair.prune(store, sizeKey, now, field)
    if Fair.sizes[sizeKey] < Fair.limit then return end
    local size = 0
    for id, entry in pairs(store) do
        if now >= (tonumber(entry[field]) or 0) then store[id] = nil else size = size + 1 end
    end
    if size >= Fair.limit then
        store = {}
        size = 0
        if sizeKey == "tells" then Fair.tells = store
        elseif sizeKey == "sightings" then Fair.sightings = store
        else Fair.announced = store end
    end
    Fair.sizes[sizeKey] = size
end

function Fair.stamp(id, kind, now, leadMs)
    local entry = Fair.tells[id]
    if entry == nil then
        Fair.prune(Fair.tells, "tells", now, "untilMs")
        entry = {}
        Fair.tells[id] = entry
        Fair.sizes.tells = Fair.sizes.tells + 1
    end
    entry.kind, entry.atMs = kind, now
    entry.readyAtMs = now + math.max(0, tonumber(leadMs) or 0)
    entry.untilMs = entry.readyAtMs + Fair.tellMemoryMs
    return entry
end

function Fair.noteTell(actor, player, kind, now, leadMs)
    if type(actor) ~= "table" or actor.uid == nil then return nil end
    local key = Fair.keyOf(player)
    if key == nil then return nil end
    now = now or Fair.now()
    local id = Fair.pairId(actor, key)
    local live = Fair.tells[id]
    if live ~= nil and now < live.untilMs and live.readyAtMs <= now + (tonumber(leadMs) or 0) then
        live.untilMs = math.max(live.untilMs, now + Fair.tellMemoryMs)
        return live
    end
    return Fair.stamp(id, kind, now, leadMs)
end

function Fair.tellGroup(actor, player, kind, now, leadMs)
    local memory = Fair.memoryOf(actor)
    local groupId = memory ~= nil and memory.groupId or nil
    local outpostId = memory ~= nil and memory.outpostId or nil
    local registry = ProjectALife.ActorRegistry
    if (groupId == nil and outpostId == nil) or registry == nil or type(registry.each) ~= "function" then return 0 end
    local told = 0
    registry.each(function(record)
        local mate = type(record) == "table" and record.memory or nil
        if type(mate) == "table" and record.uid ~= actor.uid and record.lifecycle == "active"
                and ((groupId ~= nil and mate.groupId == groupId) or (outpostId ~= nil and mate.outpostId == outpostId)) then
            Fair.noteTell(record, player, kind, now, leadMs)
            told = told + 1
        end
    end)
    return told
end

function Fair.noteSpotted(actor, player, now)
    if type(actor) ~= "table" or actor.uid == nil or not Fair.isPlayer(player) then return false end
    now = now or Fair.now()
    if Fair.kos(actor, "spot", player, now) then return false end
    local lead = Fair.settings(now).warnLeadMs
    Fair.noteTell(actor, player, "shout", now, lead)
    Fair.tellGroup(actor, player, "shout", now, lead)
    Fair.given("spot")
    return true
end

function Fair.xyz(body)
    if body == nil or type(body.getX) ~= "function" or type(body.getY) ~= "function"
            or type(body.getZ) ~= "function" then return nil end
    return body:getX(), body:getY(), body:getZ()
end

function Fair.distance(a, b)
    local ax, ay, az = Fair.xyz(a)
    local bx, by, bz = Fair.xyz(b)
    if ax == nil or bx == nil then return math.huge end
    if math.floor(az) ~= math.floor(bz) then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Fair.isNight()
    if type(getGameTime) ~= "function" then return false end
    local clock = getGameTime()
    if clock == nil or type(clock.getHour) ~= "function" then return false end
    local hour = clock:getHour()
    return hour ~= nil and (hour >= 22 or hour < 6)
end

function Fair.facing(player, body)
    if type(player.getForwardDirection) ~= "function" then return false end
    local forward = player:getForwardDirection()
    if forward == nil or type(forward.getX) ~= "function" or type(forward.getY) ~= "function" then return false end
    local px, py = player:getX(), player:getY()
    local bx, by = body:getX(), body:getY()
    local fx, fy = forward:getX(), forward:getY()
    local dx, dy = bx - px, by - py
    local f, d = math.sqrt(fx * fx + fy * fy), math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return true end
    if f < 0.001 then return false end
    return (fx * dx + fy * dy) / (f * d) >= math.cos(math.rad(Fair.viewDegrees * 0.5))
end

function Fair.playerSees(player, body)
    if type(Fair.adapters.playerSees) == "function" then return Fair.adapters.playerSees(player, body) == true end
    if player == nil or body == nil then return false end
    if type(player.isDead) == "function" and player:isDead() == true then return false end
    local distance = Fair.distance(player, body)
    local range = Fair.isNight() and Fair.nightViewRange or Fair.viewRange
    if distance > range then return false end
    if not Fair.facing(player, body) then return false end
    local sight = ProjectALife.Sight
    if sight == nil or type(sight.between) ~= "function" then return true end
    local px, py, pz = Fair.xyz(player)
    local bx, by, bz = Fair.xyz(body)
    local answer = sight.between(px, py, pz, bx, by, bz)
    return answer == nil or answer == "clear"
end

function Fair.noteSight(actor, shell, player, now)
    if type(actor) ~= "table" or actor.uid == nil or not Fair.isPlayer(player) then return nil end
    local key = Fair.keyOf(player)
    if key == nil then return nil end
    now = now or Fair.now()
    local id = Fair.pairId(actor, key)
    local entry = Fair.sightings[id]
    if entry ~= nil and now >= entry.checkedAtMs and now - entry.checkedAtMs < Fair.sightEveryMs then return entry end
    local sees = Fair.playerSees(player, shell)
    if entry == nil then
        if not sees then return nil end
        Fair.prune(Fair.sightings, "sightings", now, "untilMs")
        entry = { firstSeenAtMs = now, lastSeenAtMs = now }
        Fair.sightings[id] = entry
        Fair.sizes.sightings = Fair.sizes.sightings + 1
    elseif sees then
        if now - entry.lastSeenAtMs > Fair.lostSightMs then entry.firstSeenAtMs = now end
        entry.lastSeenAtMs = now
    end
    entry.checkedAtMs = now
    entry.untilMs = entry.lastSeenAtMs + Fair.lostSightMs
    return entry
end

function Fair.seenLongEnough(actor, shell, player, now, graceMs)
    local entry = Fair.noteSight(actor, shell, player, now)
    if entry == nil or now - entry.lastSeenAtMs > Fair.lostSightMs then return false end
    return now - entry.firstSeenAtMs >= graceMs
end

function Fair.warnedRecently(actor, key, now)
    if not Fair.grudge(actor, key) then return false end
    local memory = Fair.memoryOf(actor)
    local turned = memory ~= nil and tonumber(memory.carefulTurnedAtMs) or nil
    return turned ~= nil and now >= turned and now - turned <= Fair.turnedTellMs
end

function Fair.shout(actor, shell, player, event)
    if type(Fair.adapters.shout) == "function" then return Fair.adapters.shout(actor, shell, player, event) end
    local executor = ProjectALife.Executor
    if type(isClient) == "function" and isClient() == true and executor ~= nil
            and type(executor.relayTell) == "function" then
        local relayed = executor.relayTell(actor, player, event) == true
        if relayed then Fair.count("relayed") end
        return relayed
    end
    return Fair.bark(actor, shell, player, event) ~= nil
end

function Fair.bark(actor, shell, player, event)
    local talk, speech, data = ProjectALife.Talk, ProjectALife.Speech, ProjectALife.DialogueData
    if talk == nil or speech == nil or type(talk.bark) ~= "function" or type(speech.contextFor) ~= "function" then
        return nil
    end
    if data ~= nil and type(data.load) == "function" then data.load() end
    local context = speech.contextFor(actor, player)
    if event == Fair.warnEvent then context.stance = "hostile" end
    local said = talk.bark(actor, shell, player, event, context)
    return said
end

function Fair.hearing(a, b)
    local ax, ay, az = Fair.xyz(a)
    local bx, by, bz = Fair.xyz(b)
    if ax == nil or bx == nil or math.abs(math.floor(az) - math.floor(bz)) > Fair.hearFloors then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Fair.speakerId(actor, key)
    local memory = Fair.memoryOf(actor) or {}
    return tostring(memory.groupId or memory.outpostId or actor.uid) .. "|" .. tostring(key)
end

function Fair.noteSpeaker(actor, key, now, leadMs)
    local id = Fair.speakerId(actor, key)
    local held = Fair.speakers[id]
    if held == nil then
        if Fair.sizes.speakers >= Fair.limit then
            Fair.speakers = {}
            Fair.sizes.speakers = 0
        end
        Fair.sizes.speakers = Fair.sizes.speakers + 1
    end
    Fair.speakers[id] = { uid = actor.uid, readyAtMs = now + math.max(0, tonumber(leadMs) or 0) }
end

function Fair.covering(actor, player, now)
    if type(actor) ~= "table" or actor.uid == nil or not Fair.isPlayer(player) then return false end
    local key = Fair.keyOf(player)
    local held = key ~= nil and Fair.speakers[Fair.speakerId(actor, key)] or nil
    if held == nil or held.uid == actor.uid then return false end
    now = now or Fair.now()
    if now >= held.readyAtMs then return false end
    Fair.count("covered")
    return true
end

function Fair.warn(actor, shell, player, now, leadMs)
    local id = Fair.pairId(actor, Fair.keyOf(player))
    if Fair.hearing(shell, player) > Fair.shoutEarshot then return false end
    if Fair.shout(actor, shell, player, Fair.warnEvent) then
        Fair.count("warned")
    else
        Fair.count("silent")
    end
    Fair.given("tell")
    Fair.stamp(id, "shout", now, leadMs)
    Fair.noteSpeaker(actor, Fair.keyOf(player), now, leadMs)
    Fair.tellGroup(actor, player, "shout", now, leadMs)
    Fair.noteOpened(actor, player, now)
    return true
end

function Fair.tell(actor, shell, player, now)
    local s = Fair.settings(now)
    if s.tell ~= true then return true end
    local key = Fair.keyOf(player)
    if key == nil then return true end
    if Fair.kos(actor, "tell", player, now) then
        Fair.count("kos")
        return true
    end
    local id = Fair.pairId(actor, key)
    if Fair.underAttack(actor, player, now) or Fair.warnedRecently(actor, key, now) then
        Fair.count("fought")
        Fair.stamp(id, "fight", now, 0)
        return true
    end
    local entry = Fair.tells[id]
    if entry ~= nil and now < entry.untilMs then
        if now < entry.readyAtMs then return false end
        entry.untilMs = math.max(entry.untilMs, now + Fair.tellMemoryMs)
        return true
    end
    if Fair.seenLongEnough(actor, shell, player, now, s.graceMs) then
        Fair.count("seen")
        Fair.stamp(id, "seen", now, 0)
        return true
    end
    if Fair.overdue(id, now) then
        Fair.count("expired")
        Fair.stamp(id, "seen", now, 0)
        return true
    end
    Fair.warn(actor, shell, player, now, s.warnLeadMs)
    return false
end

function Fair.overdue(id, now)
    local warning = ProjectALife.ModuleWarning
    if warning == nil or type(warning.since) ~= "function" or type(warning.expired) ~= "function" then return false end
    if warning.expired(warning.since(id, now), nil, now) ~= true then return false end
    if type(warning.timedOut) == "function" then warning.timedOut("tell") end
    return true
end

function Fair.strikeRefusal(actor, shell, target, now)
    if type(actor) ~= "table" or not Fair.isPlayer(target) then return nil end
    now = now or Fair.now()
    if not Fair.mayInitiate(actor, target, now) then
        Fair.count("refusedOff")
        return "hostile_off"
    end
    if Fair.tell(actor, shell, target, now) then return nil end
    Fair.count("held")
    return "untold"
end

function Fair.offLimits(actor, target, now)
    if type(actor) ~= "table" or not Fair.isPlayer(target) then return false end
    return not Fair.mayInitiate(actor, target, now)
end

function Fair.actorOfShell(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    if type(shell.hasModData) == "function" and shell:hasModData() ~= true then return nil end
    local data = shell:getModData()
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    local registry = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or registry == nil then return nil end
    local look = registry.peek or registry.read
    if type(look) ~= "function" then return nil end
    return look(uid)
end

function Fair.buildingOf(square)
    if square == nil or type(square.getBuilding) ~= "function" then return nil end
    return square:getBuilding()
end

function Fair.entryBuilding(shell, object, toSquare)
    local here = shell ~= nil and type(shell.getCurrentSquare) == "function" and shell:getCurrentSquare() or nil
    local far = toSquare
    if far == nil and object ~= nil and type(object.getSquare) == "function" then
        far = object:getSquare()
        if far == here and type(object.getOppositeSquare) == "function" then far = object:getOppositeSquare() end
    end
    local building = Fair.buildingOf(far)
    if building == nil or building == Fair.buildingOf(here) then return nil end
    return building, far
end

function Fair.playersNear(x, y, z, building)
    local locator = ProjectALife.PlayerLocator
    local list = {}
    if locator == nil or type(locator.list) ~= "function" then return list end
    for _, player in ipairs(locator.list()) do
        local px, py, pz = Fair.xyz(player)
        if px ~= nil and not (type(player.isDead) == "function" and player:isDead() == true) then
            local inside = building ~= nil and Fair.buildingOf(type(player.getCurrentSquare) == "function"
                and player:getCurrentSquare() or nil) == building
            local near = math.abs(math.floor(pz) - math.floor(z)) <= 1
                and (px - x) ^ 2 + (py - y) ^ 2 <= Fair.entryEarshot ^ 2
            if inside or near then list[#list + 1] = { player = player, inside = inside } end
        end
    end
    return list
end

function Fair.onEntry(shell, object, kind, toSquare, now)
    local actor = Fair.actorOfShell(shell)
    if actor == nil then return 0 end
    local building, far = Fair.entryBuilding(shell, object, toSquare)
    if building == nil then return 0 end
    now = now or Fair.now()
    local x, y, z = far:getX(), far:getY(), far:getZ()
    local relations = ProjectALife.Relations
    local s = Fair.settings(now)
    local told = 0
    for _, seen in ipairs(Fair.playersNear(x, y, z, building)) do
        local player = seen.player
        local hostile = relations ~= nil and type(relations.hostileToPlayer) == "function"
            and relations.hostileToPlayer(actor, player) == true
        if hostile then
            if not Fair.kos(actor, "entry", player, now) then
                Fair.noteTell(actor, player, kind, now, s.entryLeadMs)
                told = told + 1
            end
        elseif seen.inside then
            Fair.announce(actor, shell, player, building, now)
        end
    end
    if told > 0 then Fair.count("entries") end
    return told
end

function Fair.announce(actor, shell, player, building, now)
    local memory = Fair.memoryOf(actor) or {}
    local id = tostring(memory.groupId or memory.outpostId or actor.uid) .. "|" .. tostring(building)
    local last = Fair.announced[id]
    if last ~= nil and now < last.untilMs then return false end
    Fair.prune(Fair.announced, "announced", now, "untilMs")
    if last == nil then Fair.sizes.announced = Fair.sizes.announced + 1 end
    Fair.announced[id] = { untilMs = now + Fair.announceEveryMs }
    if not Fair.shout(actor, shell, player, Fair.announceEvent) then return false end
    Fair.count("announced")
    return true
end

function Fair.windowOpenMs(now, shell)
    if shell ~= nil then
        local actor = Fair.actorOfShell(shell)
        if actor ~= nil and Fair.kos(actor, "window", nil, now) then return 0 end
    end
    return Fair.settings(now).windowOpenMs
end

return Fair
