require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/World/ALifeSafehouseDirector"
require "ProjectALife/Talk/ALifeTalkSupplies"
require "ProjectALife/Loot/ALifeScavenging"
require "ProjectALife/Behaviours/ALifeModuleRobbery"
require "ProjectALife/Decisions/ALifeRelations"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Audio/ALifeInteractionCues"
require "ProjectALife/Visitors/ALifeVisitorDirector"
require "ProjectALife/World/ALifeDoorEncounters"

ProjectALife = ProjectALife or {}
local Visit = { seen = {}, quotes = {}, gifts = {}, adapters = {}, backoff = {}, backoffMs = 30000 }
ProjectALife.SafehouseVisit = Visit

Visit.noEncounters = { isThemed = function() return false end, choicesFor = function() return {} end,
    labelsFor = function() return {} end, leaveLine = function() return nil end }

function Visit.door()
    return ProjectALife.DoorEncounters or Visit.noEncounters
end

Visit.refunded = { spawn_refused = true, expired = true, receipt_unavailable = true, approach_unsafe = true,
    density_not_low = true, door_unreachable = true, approach_unwalkable = true, disabled = true, no_placement = true }

function Visit.reset()
    Visit.seen, Visit.quotes, Visit.gifts, Visit.backoff = {}, {}, {}, {}
    Visit.knocks, Visit.cueBusyUntilMs = {}, 0
    Visit.metrics = { knocks = 0, knockFar = 0, knockBusy = 0, knockOff = 0, knockStates = 0,
        adminSpawned = 0, adminAtDoor = 0, adminKnock = 0, adminTalkable = 0, adminLast = "-" }
    Visit.wantStats = { asked = 0, whatAsked = 0, lentExact = 0, lentOther = 0, declined = 0 }
end

function Visit.standFor(house, pending)
    if type(pending) == "table" and type(pending.spot) == "table" then return pending.spot end
    return ProjectALife.SafehouseDirector.standOf(house)
end

function Visit.doorFor(house, pending)
    local spot = nil
    if type(pending) == "table" then spot = pending.spot end
    if type(spot) ~= "table" or spot.kind ~= "window" then return house.door end
    return { mode = "window", sx = spot.x, sy = spot.y, ix = spot.ix, iy = spot.iy, z = spot.z, edgeKey = spot.edge,
        state = spot.state, stand = spot }
end

function Visit.authorized(house)
    if type(isClient) == "function" and isClient() == true then return false, "client_authority" end
    local director = ProjectALife.SafehouseDirector
    local enabled, why = director.enabledHere()
    if not enabled then return false, why end
    if type(house) ~= "table" or director.store().houses[house.key] ~= house then return false, "house_missing" end
    if house.source == "baseheat" and house.round2 ~= true then return false, "base_round2_required" end
    return true
end

function Visit.record(uid)
    return ProjectALife.ActorRegistry.read(uid)
end

function Visit.leadUid(pending)
    local uids = type(pending) == "table" and type(pending.uids) == "table" and pending.uids or {}
    local generations = type(pending.generations) == "table" and pending.generations or nil
    local registry = ProjectALife.ActorRegistry
    local read = type(registry.peek) == "function" and registry.peek or registry.read
    for position = 1, #uids do
        local actor = read(uids[position])
        if actor ~= nil and actor.lifecycle == "active" and (generations == nil or generations[uids[position]] == actor.generation) then
            return uids[position]
        end
    end
    return uids[1]
end

function Visit.liveShell(pending)
    for _, uid in ipairs(type(pending.uids) == "table" and pending.uids or {}) do
        local shell = Visit.shell(uid)
        if shell ~= nil and Visit.position(shell) ~= nil and type(shell.isDead) == "function" and not shell:isDead()
                and type(shell.getSquare) == "function" and shell:getSquare() ~= nil then
            return shell
        end
    end
    return Visit.shell(Visit.leadUid(pending))
end

function Visit.expected(pending)
    local person = type(pending) == "table" and pending.person or nil
    if type(person) == "table" and type(person.carriers) == "table" and #person.carriers >= 1 then
        return math.min(3, #person.carriers)
    end
    return 1
end

function Visit.personArgs(pending)
    local person = type(pending) == "table" and pending.person or nil
    if type(person) ~= "table" or type(person.ids) ~= "table" then return nil end
    local ids = {}
    for position = 1, #person.ids do ids[position] = person.ids[position] end
    return { ids = ids, party = person.party, via = person.via or pending.event }
end

function Visit.scriptReady(pending)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    if type(row) ~= "table" or row.lane ~= "visit" then return false, "visit_script_missing" end
    return true
end

function Visit.eventReady(house, pending, now, direct)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    if row == nil or row.lane ~= "visit" then return false, "visit_script_missing" end
    if direct == true or pending.direct == true then return true end
    local director = ProjectALife.SafehouseDirector
    local open, why = director.rowOpen(house, row, now, true)
    if not open then return false, why end
    local day = math.floor(now / 24)
    if (row.minDay ~= nil and day < row.minDay) or (row.maxDay ~= nil and day > row.maxDay) then
        return false, "outside_visit_days"
    end
    if row.density == "low" and director.densityBand(house, now) ~= "low" then return false, "density_not_low" end
    if type(pending.person) == "table" then return true end
    local picks = director.candidates(house, row, now, false)
    for _, pick in ipairs(picks) do if pick.factionId == pending.faction then return true end end
    return false, "visit_faction_ineligible"
end

function Visit.spawnStamp(houseKey, pendingId)
    local director = ProjectALife.SafehouseDirector
    local house = director.store().houses[houseKey]
    if not Visit.authorized(house) then return nil end
    for _, pending in ipairs(house.pending or {}) do
        if pending.id == pendingId and pending.lane == "visit" and pending.state == "queued"
                and pending.started == true and pending.resolved ~= true
                and director.hours() < (tonumber(pending.untilHours) or 0) then
            return { house = house.key, pendingId = pending.id }
        end
    end
    return nil
end

function Visit.write(uid, mutate)
    local registry = ProjectALife.ActorRegistry
    local actor = registry.read(uid)
    if actor == nil then return false end
    local updated = registry.update(uid, actor.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        mutate(record.memory)
    end)
    return updated ~= nil and updated ~= false
end

function Visit.shell(uid)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.shellFor) == "function" then return talk.shellFor(uid) end
    local watchdog = ProjectALife.Watchdog
    if watchdog ~= nil and type(watchdog.shellFor) == "function" then return watchdog.shellFor(uid) end
    return nil
end

function Visit.position(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function"
            or type(object.getZ) ~= "function" then return nil end
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

function Visit.nearResidents(house, stand)
    local nearby = {}
    if stand == nil then return nearby end
    for _, resident in ipairs(ProjectALife.SafehouseDirector.onlineResidents(house)) do
        local point = Visit.position(resident)
        if point ~= nil and (point.x - stand.x)^2 + (point.y - stand.y)^2 <= 3600 then
            nearby[#nearby + 1] = resident
        end
    end
    return nearby
end

function Visit.hostile(actor, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return nil end
    local ok, stance = pcall(relations.playerStance, actor, player)
    if not ok or (stance ~= "hostile" and stance ~= "careful" and stance ~= "neutral" and stance ~= "friendly") then return nil end
    return stance == "hostile"
end

function Visit.millis()
    local talk = ProjectALife.Talk
    local getter = talk ~= nil and type(talk.adapters) == "table" and talk.adapters.nowMs or getTimestampMs
    if type(getter) ~= "function" then return nil end
    local ok, now = pcall(getter)
    if ok and type(now) == "number" and now == now then return now end
    return nil
end

function Visit.talking(pending)
    local now, talk = Visit.millis(), ProjectALife.Talk
    if now == nil then return false, "conversation_clock_unavailable" end
    pending.state, pending.talkUntilMs = "talking", now + (tonumber(talk.settings.stateMs) or 60000)
    ProjectALife.SafehouseDirector.dirty()
    return true
end

function Visit.atDoor(pending)
    pending.state, pending.question, pending.talkUntilMs = "at_door", nil, nil
    ProjectALife.SafehouseDirector.dirty()
end

function Visit.holdMs()
    local director = ProjectALife.SafehouseDirector
    local seconds = math.floor(tonumber(director.settings.visitorHoldSeconds) or 0)
    if seconds <= 0 then return 0 end
    local low = math.max(1, math.floor(seconds * 2 / 3))
    local high = math.max(low, math.floor(seconds * 4 / 3))
    return (low + director.rand(high - low + 1)) * 1000
end

function Visit.holdWrite(pending, value)
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then memory.visit.holdUntilMs = value end
        end)
    end
end

function Visit.holdStart(house, pending)
    if pending.holdUntilMs ~= nil or pending.holdSpent == true then return false end
    pending.holdSpent = true
    local millis = Visit.millis()
    local span = Visit.holdMs()
    if millis == nil or span <= 0 then return false end
    pending.holdUntilMs = millis + span
    Visit.holdWrite(pending, pending.holdUntilMs)
    ProjectALife.SafehouseDirector.dirty()
    return true
end

function Visit.holdRelease(pending)
    local was = pending.holdUntilMs
    pending.holdUntilMs = nil
    if was ~= nil then Visit.holdWrite(pending, nil) end
    return was ~= nil
end

function Visit.holdTick(house, pending)
    if pending.state ~= "at_door" or Visit.facingOpen(house, pending) then
        if pending.holdUntilMs ~= nil then Visit.holdRelease(pending); ProjectALife.SafehouseDirector.dirty() end
        return false
    end
    if pending.holdUntilMs == nil then
        if pending.holdSpent == true or not Visit.holdStart(house, pending) then return false end
    end
    local millis = Visit.millis()
    if millis == nil or millis >= pending.holdUntilMs then
        Visit.holdRelease(pending)
        ProjectALife.SafehouseDirector.dirty()
        return false
    end
    return true
end

function Visit.clear(uid, pendingId, generation)
    local actor = Visit.record(uid)
    if actor == nil or (generation ~= nil and actor.generation ~= generation) then return false end
    return Visit.write(uid, function(memory)
        if type(memory.visit) == "table" and memory.visit.pendingId == pendingId then
            if memory.visit.stanceForced == true and type(memory.moduleOverrides) == "table"
                    and memory.moduleOverrides.stance == "on" then
                memory.moduleOverrides.stance = memory.visit.stanceOverride
            end
            memory.visit = nil
            if type(memory.guest) == "table" and memory.guest.pendingId == pendingId then memory.guest = nil end
            if memory.stance == "visit" then memory.stance, memory.stanceAnchor, memory.stanceFace = nil, nil, nil end
        end
    end)
end

function Visit.groundNear(x, y, z)
    local door, roads = ProjectALife.SafehouseDoor, ProjectALife.Road
    local first = nil
    for ring = 0, 3 do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local square = door.square(x + dx, y + dy, z)
                    if square ~= nil and door.outside(square) and door.walkable(square) then
                        if roads ~= nil and type(roads.isPavedSurface) == "function" and roads.isPavedSurface(square) == true then
                            return square
                        end
                        if first == nil then first = square end
                    end
                end
            end
        end
    end
    return first
end

Visit.sweeps = { { rings = { 55, 47, 39 }, angles = 8 }, { rings = { 51, 43, 59, 63, 67, 41 }, angles = 16 } }

function Visit.spawnPoint(house, stand)
    local director = ProjectALife.SafehouseDirector
    stand = stand or director.standOf(house)
    local graph, policy = ProjectALife.RoadGraph, ProjectALife.SpawnPolicy
    if stand == nil or policy == nil or type(policy.check) ~= "function" then return nil, { no_spawn_policy = 1 } end
    local z = stand.z or 0
    local options = { playerKeepOut = 40, fairness = false }
    local context = nil
    if type(policy.context) == "function" then context = policy.context(options) end
    local roads = graph ~= nil and type(graph.snapToRoad) == "function"
    local reasons, seen = {}, {}
    local function refuse(why) reasons[why] = (reasons[why] or 0) + 1 end
    for _, sweep in ipairs(Visit.sweeps) do
        for pass = 1, 2 do
            if pass == 2 or roads then
                for ring = 1, #sweep.rings do
                    for index = 0, sweep.angles - 1 do
                        local angle = index * 2 * math.pi / sweep.angles
                        local x, y = stand.x + sweep.rings[ring] * math.cos(angle), stand.y + sweep.rings[ring] * math.sin(angle)
                        local point = nil
                        if pass == 1 then
                            point = graph.snapToRoad(x, y, 12)
                            if type(point) == "table" then point = { x = point.x, y = point.y, z = z } else point = nil end
                        else
                            local square = Visit.groundNear(x, y, z)
                            if square ~= nil then point = { x = square:getX() + 0.5, y = square:getY() + 0.5, z = z, ground = true } end
                        end
                        if point == nil then
                            refuse(pass == 1 and "no_road_near" or "no_open_ground")
                        else
                            local key = pass .. ":" .. math.floor(point.x) .. "," .. math.floor(point.y)
                            local d2 = (point.x - stand.x)^2 + (point.y - stand.y)^2
                            if seen[key] then
                                refuse("duplicate_square")
                            elseif d2 < 1225 or d2 > 4900 then
                                refuse("out_of_range")
                            else
                                seen[key] = true
                                local ok, why = policy.check(point, options, context)
                                if ok == true then return point end
                                refuse(tostring(why))
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, reasons
end

function Visit.approachReady(house, pending, point, now)
    local proof = house.approach
    local stand = Visit.standFor(house, pending)
    if type(proof) == "table" and proof.pendingId == pending.id
            and now >= (tonumber(proof.atHours) or math.huge)
            and now - proof.atHours <= 2 and type(proof.point) == "table"
            and (proof.point.x - point.x)^2 + (proof.point.y - point.y)^2 < 0.25 then
        if (tonumber(proof.n) or math.huge) > 4 then return false, "approach_unsafe" end
        if ProjectALife.SafehouseDirector.densityBand(house, now) ~= "low" then return false, "density_not_low" end
        return true
    end
    local door = ProjectALife.SafehouseDoor
    if stand == nil then return false, "door_unreachable" end
    local verdict = door.reach(stand.x, stand.y, stand.z or 0)
    if verdict == "unknown" then return false, "reach_unknown" end
    if not door.reachable(verdict) then return false, "door_unreachable" end
    local blocked, allowed = 0, 0
    if point.ground == true then allowed = 5 end
    for index = 1, 10 do
        local t = index / 10
        local square = door.square(point.x + (stand.x - point.x) * t,
            point.y + (stand.y - point.y) * t, point.z or 0)
        if not door.outside(square) or not door.walkable(square) then blocked = blocked + 1 end
    end
    if blocked > allowed then return false, "approach_unwalkable" end
    ProjectALife.SafehouseDirector.startSample(house, now, { pendingId = pending.id, point = point, stand = stand })
    return false, "approach_sampling"
end

function Visit.nearestResident(house, stand, limit)
    local player, nearest = nil, limit or math.huge
    if stand == nil then return nil end
    for _, resident in ipairs(ProjectALife.SafehouseDirector.onlineResidents(house)) do
        local point = Visit.position(resident)
        if point ~= nil then
            local d2 = (point.x - stand.x)^2 + (point.y - stand.y)^2
            if d2 <= nearest then player, nearest = resident, d2 end
        end
    end
    return player
end

function Visit.chooseSpot(house, pending, row, reject)
    if type(pending.spot) == "table" and reject == nil then return pending.spot, pending.spotNote end
    local wanted = "door"
    if row ~= nil and row.at == "window" then wanted = "window" end
    local spot, note = ProjectALife.SafehouseDoor.visitSpot(house, wanted, ProjectALife.SafehouseDirector.rand(8), nil, reject)
    if spot == nil then return nil, note end
    pending.spot, pending.spotNote = spot, note
    return spot, note
end

function Visit.probeSpot(house, pending, spot, note, refusals)
    local policy = ProjectALife.SpawnPolicy
    local probe = policy ~= nil and policy.probeExact or nil
    if type(probe) ~= "function" then return spot, note end
    local reject = {}
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    for _ = 1, 4 do
        local ok, reason = probe(spot.x, spot.y, spot.z or 0)
        if ok == true then return spot, note end
        local text = tostring(reason)
        refusals[text] = (refusals[text] or 0) + 1
        reject[spot.x .. "," .. spot.y] = true
        local fresh, freshNote = Visit.chooseSpot(house, pending, row, reject)
        if fresh == nil then return nil, freshNote end
        spot, note = fresh, freshNote
    end
    return nil, "four squares refused"
end

function Visit.walkAway(house, spot)
    local dx, dy = spot.x - (tonumber(house.cx) or spot.x), spot.y - (tonumber(house.cy) or spot.y)
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then dx, dy, length = 1, 0, 1 end
    return { x = math.floor(spot.x + dx / length * 30), y = math.floor(spot.y + dy / length * 30), z = spot.z or 0 }
end

function Visit.spawnProfiles(service, now, faction, pending)
    local person = type(pending) == "table" and pending.person or nil
    if type(person) == "table" then
        if service == nil or type(service.spawnEncounter) ~= "function" or type(service.watchGroup) ~= "function" then
            return nil, "spawn_service_unavailable"
        end
        local carriers = type(person.carriers) == "table" and person.carriers or {}
        if #carriers < 1 or #carriers > 3 then return nil, "profiles_unavailable" end
        local profiles = {}
        for position = 1, #carriers do
            if type(carriers[position]) ~= "string" then return nil, "profiles_unavailable" end
            profiles[position] = carriers[position]
        end
        return profiles
    end
    if service == nil or type(service.spawnEncounter) ~= "function" or type(service.watchGroup) ~= "function"
            or type(service.hostileProfileIds) ~= "function" then return nil, "spawn_service_unavailable" end
    local profiles = service.hostileProfileIds(1, math.floor(now * 1000), faction, true)
    if type(profiles) ~= "table" or #profiles ~= 1 then return nil, "profiles_unavailable" end
    return profiles
end

function Visit.watch(house, pending, service)
    local director = ProjectALife.SafehouseDirector
    return service.watchGroup(pending.id, function(outcome)
        if pending.resolved == true then
            for _, uid in ipairs(type(outcome) == "table" and outcome.actorUids or {}) do Visit.clear(uid, pending.id) end
            return
        end
        local expected = Visit.expected(pending)
        local accepted = type(outcome) == "table" and outcome.ok == true and outcome.active == expected
            and type(outcome.actorUids) == "table" and #outcome.actorUids == expected
        if accepted then accepted = Visit.admit(house, pending, outcome.actorUids, director.hours()) end
        if not accepted then
            local why = type(outcome) == "table" and (outcome.reason or "not_active") or "no_outcome"
            print("[ALIFE-SAFEHOUSE] visit " .. tostring(pending.event) .. " spawn refused: " .. tostring(why))
            for _, uid in ipairs(type(outcome) == "table" and outcome.actorUids or {}) do Visit.clear(uid, pending.id) end
            Visit.settle(house, pending, "spawn_refused", nil, director.hours())
        else
            local spot = pending.spot
            print(string.format("[ALIFE-SAFEHOUSE] visit %s: visitor %s is at the %s %s,%s", tostring(pending.event),
                tostring(Visit.leadUid(pending)), tostring(spot and spot.kind or "door"),
                tostring(spot and spot.x or "?"), tostring(spot and spot.y or "?")))
        end
    end)
end

function Visit.start(house, pending, now, force)
    local allowed, why = Visit.authorized(house)
    if not allowed then return false, why end
    if pending.state ~= "queued" or pending.resolved == true then return false, "not_queued" end
    if now >= (tonumber(pending.untilHours) or now) then Visit.settle(house, pending, "expired", nil, now); return false, "expired" end
    local direct = force == true or pending.direct == true
    local ready, reason = Visit.eventReady(house, pending, now, direct)
    if not ready then return false, reason end
    if pending.started == true then return true, "spawn_pending", { spot = pending.spot, how = "spawn pending" } end
    local director = ProjectALife.SafehouseDirector
    local gates = director.deliveryGates
    if direct then gates = director.directGates end
    for _, id in ipairs(gates) do
        local blocked, reason = director.gate(id, house, now)
        if blocked then return false, reason end
    end
    local pressure = ProjectALife.WorldPressure
    if not direct and pressure ~= nil and type(pressure.crowded) == "function" and pressure.crowded(house.cx, house.cy, now) then
        return false, "crowded"
    end
    local spot, spotNote = Visit.chooseSpot(house, pending, ProjectALife.SafehouseEvents.row(pending.event))
    if spot == nil then return false, tostring(spotNote or "no_stand_square") end
    if direct then return Visit.startDirect(house, pending, now, spot, spotNote) end
    return Visit.startFar(house, pending, now, spot, spotNote)
end

function Visit.startFar(house, pending, now, spot, spotNote)
    local director = ProjectALife.SafehouseDirector
    local player = Visit.nearestResident(house, spot, 3600)
    if player == nil then return false, "resident_away" end
    local millis = Visit.millis()
    local holdUntil = Visit.backoff[pending.id]
    if holdUntil ~= nil and millis ~= nil and millis < holdUntil then return false, "spawn_point_unavailable" end
    local point, refused = pending.planned, nil
    local policy = ProjectALife.SpawnPolicy
    if point ~= nil and not (policy ~= nil and type(policy.check) == "function" and policy.check(point, { playerKeepOut = 40 }) == true) then
        point = nil
    end
    if point == nil then point, refused = Visit.spawnPoint(house, spot) end
    if point == nil then
        if millis ~= nil then Visit.backoff[pending.id] = millis + Visit.backoffMs end
        house.spawnHint = ProjectALife.SafehouseDoor.reasonText(refused)
        return false, "spawn_point_unavailable"
    end
    pending.planned = point
    house.spawnHint = nil
    local safe, unsafe = Visit.approachReady(house, pending, point, now)
    if not safe then
        if unsafe ~= "approach_sampling" and unsafe ~= "reach_unknown" then Visit.settle(house, pending, unsafe, nil, now) end
        return false, unsafe
    end
    local service = ProjectALife.DebugService
    local profiles, profileWhy = Visit.spawnProfiles(service, now, pending.faction, pending)
    if profiles == nil then return false, profileWhy end
    pending.started, pending.spawn = true, point
    director.dirty()
    local ok, reason = service.spawnEncounter(player, { requestId = pending.id, encounterId = "safehouse_visit",
        mode = "roam", profile = "patrol", profileIds = profiles, factionId = pending.faction, count = #profiles,
        origin = "director", stance = "visit", x = point.x, y = point.y, z = point.z or 0,
        distance = 0, radius = 6, separation = 2, atomicGroup = true, person = Visit.personArgs(pending),
        visit = { house = house.key, pendingId = pending.id } })
    if not ok then Visit.settle(house, pending, "spawn_refused", nil, now); return false, reason end
    if Visit.watch(house, pending, service) == false then
        Visit.settle(house, pending, "receipt_unavailable", nil, now)
        return false, "receipt_unavailable"
    end
    director.metrics.visitsFar = director.metrics.visitsFar + 1
    if spot.kind == "window" then director.metrics.windowVisits = director.metrics.windowVisits + 1 end
    return true, "spawn_pending", { spot = spot, how = "walks in from " .. string.format("%.0f,%.0f", point.x, point.y), note = spotNote }
end

function Visit.partySlots(spot, count)
    local doors, policy = ProjectALife.SafehouseDoor, ProjectALife.SpawnPolicy
    local probe = policy ~= nil and policy.probeExact or nil
    local z = spot.z or 0
    local sx, sy = math.floor(spot.x), math.floor(spot.y)
    local slots = { { x = sx + 0.5, y = sy + 0.5, z = z } }
    local taken = { [sx .. "," .. sy] = true }
    for ring = 1, 3 do
        for dx = -ring, ring do
            for dy = -ring, ring do
                local x, y = sx + dx, sy + dy
                if #slots < count and math.max(math.abs(dx), math.abs(dy)) == ring and not taken[x .. "," .. y] then
                    local square = doors.square(x, y, z)
                    if square ~= nil and doors.outside(square) and doors.walkable(square)
                            and (type(probe) ~= "function" or probe(x, y, z) == true) then
                        slots[#slots + 1] = { x = x + 0.5, y = y + 0.5, z = z }
                        taken[x .. "," .. y] = true
                    end
                end
            end
        end
    end
    if #slots < count then return nil end
    return slots
end

function Visit.startDirect(house, pending, now, spot, spotNote)
    local director = ProjectALife.SafehouseDirector
    local player = Visit.nearestResident(house, spot, nil)
    if player == nil then return false, "resident_away" end
    local service = ProjectALife.DebugService
    local profiles, profileWhy = Visit.spawnProfiles(service, now, pending.faction, pending)
    if profiles == nil then return false, profileWhy end
    local refusals = {}
    local chosen, chosenNote = Visit.probeSpot(house, pending, spot, spotNote, refusals)
    if chosen == nil then
        pending.started = nil
        return false, "spawn_square_refused (" .. ProjectALife.SafehouseDoor.reasonText(refusals) .. ")"
    end
    spot, spotNote = chosen, chosenNote
    local slots = nil
    if #profiles > 1 then
        slots = Visit.partySlots(spot, #profiles)
        if slots == nil then
            pending.started = nil
            return false, "spawn_square_refused (party_slots)"
        end
    end
    pending.direct, pending.started, pending.spawn = true, true, Visit.walkAway(house, spot)
    director.dirty()
    local args = { requestId = pending.id, encounterId = "safehouse_visit", mode = "roam", profile = "patrol",
        profileIds = profiles, factionId = pending.faction, count = #profiles, origin = "director", stance = "visit",
        x = spot.x, y = spot.y, z = spot.z or 0, distance = 0, radius = 6, separation = 2, atomicGroup = true,
        adminPick = true, exactSquare = true, playerKeepOut = 0, slots = slots, person = Visit.personArgs(pending),
        visit = { house = house.key, pendingId = pending.id } }
    if spot.fx ~= nil and spot.fy ~= nil then
        args.faces = { { x = spot.fx, y = spot.fy } }
        for position = 2, #profiles do args.faces[position] = { x = spot.fx, y = spot.fy } end
    end
    local ok, reason = service.spawnEncounter(player, args)
    if not ok then
        pending.started = nil
        Visit.settle(house, pending, "spawn_refused", nil, now)
        return false, tostring(reason)
    end
    if Visit.watch(house, pending, service) == false then
        Visit.settle(house, pending, "receipt_unavailable", nil, now)
        return false, "receipt_unavailable"
    end
    director.metrics.visitsDirect = director.metrics.visitsDirect + 1
    if spot.kind == "window" then director.metrics.windowVisits = director.metrics.windowVisits + 1 end
    print(string.format("[ALIFE-SAFEHOUSE] visit %s direct at the %s %d,%d facing %s,%s (debug force)", tostring(pending.event),
        tostring(spot.kind), spot.x, spot.y, tostring(spot.fx), tostring(spot.fy)))
    return true, "spawn_pending", { spot = spot, how = "appears on that square (debug force: hours, faction and density relaxed)",
        note = spotNote }
end

function Visit.waitingSpots(house, pending, uids)
    local doors = ProjectALife.SafehouseDoor
    local first = Visit.standFor(house, pending)
    local door = Visit.doorFor(house, pending)
    if first == nil then return nil end
    if not doors.waitingClear(door, first) then first = doors.standSpot(house) end
    if first == nil then return nil end
    local spots, reject = {}, {}
    for index, uid in ipairs(uids) do
        local spot = first
        if index > 1 then spot = doors.standSearch(house, door, first, reject) end
        if spot == nil then return nil end
        spots[uid] = { x = spot.x + 0.5, y = spot.y + 0.5, z = spot.z or 0 }
        for dx = -1, 1 do
            for dy = -1, 1 do reject[(spot.x + dx) .. "," .. (spot.y + dy)] = true end
        end
    end
    pending.spot, pending.waitingSpots = first, spots
    return spots
end

function Visit.admit(house, pending, uids, now)
    local allowed, why = Visit.authorized(house)
    if not allowed then return false, why end
    if type(pending) ~= "table" or pending.state ~= "queued" or pending.resolved == true
            or type(uids) ~= "table" or #uids < 1 or #uids > 3 then return false, "invalid_receipt" end
    if now >= (tonumber(pending.untilHours) or now) then return false, "receipt_expired" end
    local ready, reason = Visit.eventReady(house, pending, now)
    if not ready then return false, reason end
    local gates = ProjectALife.SafehouseDirector.deliveryGates
    if pending.direct == true then gates = ProjectALife.SafehouseDirector.directGates end
    for _, id in ipairs(gates) do
        local blocked, reason = ProjectALife.SafehouseDirector.gate(id, house, now)
        if blocked then return false, reason end
    end
    local listed = false
    for _, row in ipairs(house.pending or {}) do if row == pending then listed = true end end
    if not listed then return false, "pending_missing" end
    local generations, unique = {}, {}
    for _, uid in ipairs(uids) do
        local actor = Visit.record(uid)
        local memory = actor and actor.memory or {}
        local stamp = memory.visit
        if unique[uid] or actor == nil or actor.lifecycle ~= "active" or memory.natural ~= true
                or actor.factionId ~= pending.faction or memory.debugSpawn == true or type(stamp) ~= "table" or stamp.house ~= house.key
                or stamp.pendingId ~= pending.id then return false, "receipt_identity" end
        unique[uid], generations[uid] = true, actor.generation
    end
    local spots = Visit.waitingSpots(house, pending, uids)
    if spots == nil then return false, "door_missing" end
    for _, uid in ipairs(uids) do
        local ok = Visit.write(uid, function(memory)
            memory.visit = { house = house.key, pendingId = pending.id, generation = generations[uid], untilHours = now + 2, renewedHours = now, event = pending.event }
            memory.visit.stanceForced = true
            if type(memory.moduleOverrides) == "table" then memory.visit.stanceOverride = memory.moduleOverrides.stance end
            memory.moduleOverrides = type(memory.moduleOverrides) == "table" and memory.moduleOverrides or {}
            memory.moduleOverrides.stance = "on"
            memory.stance, memory.stanceAnchor = "visit", spots[uid]
            if type(pending.spot) == "table" and pending.spot.fx ~= nil and pending.spot.fy ~= nil then
                memory.stanceFace = { x = pending.spot.fx, y = pending.spot.fy }
            end
        end)
        if not ok then
            for _, previous in ipairs(uids) do Visit.clear(previous, pending.id) end
            return false, "actor_write_refused"
        end
    end
    pending.uids, pending.generations = uids, generations
    pending.state, pending.untilHours = "approach", now + 2
    local visitors = ProjectALife.VisitorDirector
    if type(pending.person) == "table" and visitors ~= nil and type(visitors.admitted) == "function" then
        visitors.admitted(house, pending, uids, now)
    end
    Visit.seen[pending] = true
    if pending.direct == true or pending.debug == true then Visit.metrics.adminSpawned = Visit.metrics.adminSpawned + 1 end
    if pending.event == "trader" then
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator ~= nil and type(hydrator.ensureTraderStock) == "function" then
            for _, uid in ipairs(uids) do
                local called, ready, reason = pcall(hydrator.ensureTraderStock, Visit.shell(uid), Visit.record(uid))
                if not called or ready ~= true then pending.stockReason = called and reason or "trader_stock_issue_failed" end
            end
        end
    end
    ProjectALife.SafehouseDirector.dirty()
    return true
end

function Visit.live(uid)
    local actor = Visit.record(uid)
    local stamp = actor and type(actor.memory) == "table" and actor.memory.visit or nil
    if type(stamp) ~= "table" then return nil end
    local director = ProjectALife.SafehouseDirector
    local house = director.store().houses[stamp.house]
    local now = director.hours()
    if stamp.generation == actor.generation and house ~= nil and now <= (tonumber(stamp.untilHours) or -math.huge)
            and now <= (tonumber(stamp.renewedHours) or -math.huge) + 3 then
        for _, pending in ipairs(house.pending or {}) do
            if pending.id == stamp.pendingId and pending.resolved ~= true and actor.lifecycle == "active"
                    and type(pending.generations) == "table" and pending.generations[uid] == actor.generation then
                return pending, house, actor
            end
        end
    end
    if not (type(isClient) == "function" and isClient()) then Visit.clear(uid, stamp.pendingId) end
    return nil
end

function Visit.identityShell(uid, actor)
    local shell = Visit.shell(uid)
    if actor == nil or shell == nil or type(shell.getModData) ~= "function"
            or type(shell.isDead) ~= "function" or shell:isDead() then return nil end
    if type(shell.hasModData) == "function" and not shell:hasModData() then return nil end
    local read, data = pcall(shell.getModData, shell)
    if not read or type(data) ~= "table" or data.ProjectALifeUID ~= uid
            or data.ProjectALifeGeneration ~= actor.generation then return nil end
    return shell
end

Visit.peerWhy = {}
Visit.standSq = 9

function Visit.whyNot(uid, why, detail)
    Visit.peerWhy[uid] = detail ~= nil and (why .. " " .. detail) or why
    return nil
end

function Visit.peer(player, uid, observed)
    local pending, house, actor = Visit.live(uid)
    if pending == nil then return Visit.whyNot(uid, "no_visit") end
    local shell = Visit.identityShell(uid, actor)
    if shell == nil then return Visit.whyNot(uid, "no_body") end
    if Visit.guestState(pending) then return Visit.guestPeer(player, uid, pending, house, actor) end
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    if pending.state ~= "at_door" and pending.state ~= "talking"
            and not (observed == true and pending.state == "leaves") then return Visit.whyNot(uid, "state", tostring(pending.state)) end
    if key == nil or house.residents[key] == nil then return Visit.whyNot(uid, "not_resident") end
    local point = Visit.position(player)
    local outside = Visit.position(shell)
    local door = Visit.doorFor(house, pending)
    local stand = actor.memory.stanceAnchor or Visit.standFor(house, pending)
    if observed == true and pending.state == "leaves" then
        stand = type(pending.waitingSpots) == "table" and pending.waitingSpots[uid] or Visit.standFor(house, pending)
    end
    if point == nil or outside == nil or door == nil or stand == nil or tonumber(door.ix) == nil or tonumber(door.iy) == nil
            or math.floor(point.z) ~= math.floor(outside.z) then return Visit.whyNot(uid, "position_missing_or_floor") end
    local drift = (outside.x - stand.x)^2 + (outside.y - stand.y)^2
    if drift > Visit.standSq then return Visit.whyNot(uid, "left_stand", string.format("%.1f", math.sqrt(drift))) end
    local inside = point.x >= house.x1 and point.x < house.x2 and point.y >= house.y1 and point.y < house.y2
    if inside then
        if math.floor(point.z) ~= math.floor(door.z or 0)
                or (point.x - door.ix)^2 + (point.y - door.iy)^2 > 64 then return Visit.whyNot(uid, "player_far_from_door") end
    else
        local talk = ProjectALife.Talk
        if (point.x - outside.x)^2 + (point.y - outside.y)^2 > 36
                or talk == nil or type(talk.lineOfSight) ~= "function" or not talk.lineOfSight(player, shell) then return Visit.whyNot(uid, "outside_far_or_no_sight") end
    end
    Visit.peerWhy[uid] = nil
    return { record = actor, shell = shell }, pending, house
end

function Visit.doorPeer(player, uid)
    return Visit.peer(player, uid, false)
end

function Visit.handles(intent, record)
    if Visit.questionIds[intent] or Visit.door().isThemed(intent) then
        return record ~= nil and Visit.live(record.uid) ~= nil
    end
    if intent ~= "DOOR_WHO" and intent ~= "DOOR_LEAVE" and intent ~= "DOOR_LEAVE_RUDE"
            and intent ~= "DOOR_GIVE" and intent ~= "DOOR_CENSUS_CLEAR" and intent ~= "DOOR_CENSUS_BITTEN"
            and intent ~= "DOOR_WEAPONS_DOWN" and intent ~= "DOOR_TRADE" and intent ~= "DOOR_TRADE_CONFIRM"
            and intent ~= "DOOR_TRADE_CANCEL" and intent ~= "DOOR_SEARCH" and intent ~= "DOOR_INVITE"
            and intent ~= "GUEST_LEAVE" and intent ~= "DOOR_TREAT" and intent ~= "DOOR_PAY" and intent ~= "DOOR_BLUFF"
            and intent ~= "DOOR_CALLSIGN" and intent ~= "DOOR_JOB" and intent ~= "DOOR_LEND" and intent ~= "DOOR_HAND_GUNS"
            and intent ~= "DOOR_TREAT_ME" then
        return false
    end
    return record ~= nil and Visit.live(record.uid) ~= nil
end

function Visit.guestChoices(pending)
    local set = { DOOR_WHO = true, DOOR_HEALTH = true, DOOR_STAY = true, GUEST_LEAVE = true }
    if #(pending.uids or {}) > 1 then set.DOOR_COMPANY = true end
    return set
end

function Visit.choices(uid, player)
    local pending, house = Visit.live(uid)
    if pending ~= nil and Visit.guestState(pending) then return Visit.guestChoices(pending) end
    if pending == nil or (pending.state ~= "at_door" and pending.state ~= "talking") then return {} end
    local choices = { DOOR_WHO = true, DOOR_NEED = true, DOOR_HEALTH = true, DOOR_COMPANY = true,
        DOOR_LEAVE = true, DOOR_LEAVE_RUDE = true, DOOR_WEAPONS_DOWN = true }
    if Visit.entryRow(pending) then choices.DOOR_STAY = true end
    local listener = player ~= nil and Visit.doorPeer(player, uid) or nil
    if listener ~= nil and not Visit.searched(listener.record, player) and Visit.openPeer(player, listener, house) then choices.DOOR_SEARCH = true end
    if pending.event == "beggar" then choices.DOOR_GIVE = true end
    if (pending.event == "wounded" or pending.event == "medical_visit") and pending.treated ~= true then choices.DOOR_TREAT = true end
    if pending.event == "racket" then choices.DOOR_PAY, choices.DOOR_BLUFF = true, true end
    if string.sub(tostring(pending.event), 1, 4) == "law_" then choices.DOOR_CALLSIGN = true end
    if pending.event == "medic_rounds" and pending.treated ~= true then choices.DOOR_TREAT_ME = true end
    if (pending.event == "messenger" or pending.event == "asks_help") and pending.place ~= nil then choices.DOOR_JOB = true end
    if pending.event == "neighbour_borrow" then choices.DOOR_LEND = true end
    if Visit.hasWant(pending) then choices.DOOR_WHAT = true end
    for intent in pairs(Visit.door().choicesFor(pending.event)) do choices[intent] = true end
    if pending.haggled == true or pending.event ~= "racket" then choices.DOOR_HAGGLE = nil end
    if pending.event == "law_guns" then choices.DOOR_HAND_GUNS = true end
    if pending.state == "at_door" and pending.decideUntilMs ~= nil and Visit.entryRow(pending) then choices.DOOR_INVITE = true end
    if pending.event == "trader" and pending.trade == nil then
        choices.DOOR_TRADE = true
        if player ~= nil and Visit.tradeView(player, uid) ~= nil then
            choices.DOOR_TRADE_CONFIRM, choices.DOOR_TRADE_CANCEL = true, true
        end
    end
    if pending.event == "law_census" and pending.question == "census" then
        choices.DOOR_CENSUS_CLEAR, choices.DOOR_CENSUS_BITTEN = true, true
    end
    if pending.state == "talking" and Visit.entryRow(pending) then choices.DOOR_INVITE = true end
    return choices
end

function Visit.doorLabels(uid)
    local pending = Visit.live(uid)
    if pending == nil or Visit.guestState(pending) then return {} end
    return Visit.door().labelsFor(pending.event)
end

function Visit.entryRow(pending)
    local events = ProjectALife.SafehouseEvents
    local row = events.row(pending.event)
    return row ~= nil and (events.contains(row.needs, "entryAllowed") or type(row.guest) == "table")
        and ProjectALife.SafehouseDirector.settings.entry ~= 2
end

function Visit.guestState(pending)
    return pending.state == "invited" or pending.state == "inside"
end

function Visit.guestPeer(player, uid, pending, house, actor)
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    if key == nil or house.residents[key] == nil then return nil end
    local point, shell = Visit.position(player), Visit.shell(uid)
    local guest = Visit.position(shell)
    if point == nil or guest == nil or math.abs(point.z - guest.z) > 1
            or (point.x - guest.x)^2 + (point.y - guest.y)^2 > 36 then return nil end
    return { record = actor, shell = shell }, pending, house
end

function Visit.guestSpot(house)
    local door = house.door
    local z = tonumber(door.z) or 0
    local x = door.ix + (door.ix - (tonumber(door.sx) or door.ix))
    local y = door.iy + (door.iy - (tonumber(door.sy) or door.iy))
    local doors = ProjectALife.SafehouseDoor
    local square = doors.square(x, y, z)
    if square == nil or doors.outside(square) or not doors.walkable(square) then x, y = door.ix, door.iy end
    return { x = x + 0.5, y = y + 0.5, z = z }
end

function Visit.guestUntil(pending, now)
    local base = Visit.guestBase(pending, now)
    local visitors = ProjectALife.VisitorDirector
    if type(pending.person) == "table" and visitors ~= nil and type(visitors.stayUntil) == "function" then
        return visitors.stayUntil(pending, base, now)
    end
    return base
end

function Visit.guestBase(pending, now)
    local director = ProjectALife.SafehouseDirector
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    local rule = row ~= nil and type(row.guest) == "table" and row.guest or {}
    local hour = tonumber(rule.untilHour)
    if hour == nil then return now + (tonumber(rule.hours) or director.settings.guestHours) end
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local today = tonumber(director.ask(time, "getTimeOfDay"))
    if today == nil then return now + director.settings.guestHours end
    local wait = (hour - today) % 24
    if wait < 0 then wait = wait + 24 end
    if wait < 1 then wait = wait + 24 end
    return now + wait
end

function Visit.dropGuest(uid, pending)
    return Visit.write(uid, function(memory)
        if type(memory.guest) == "table" and memory.guest.pendingId == pending.id then memory.guest = nil end
    end)
end

function Visit.unlockEntry(house)
    local doors, policy = ProjectALife.SafehouseDoor, ProjectALife.DoorPolicy
    local door = type(house) == "table" and house.door or nil
    if doors == nil or policy == nil or type(door) ~= "table" or door.mode ~= "door" then return false end
    local object = doors.entryDoor(door)
    if object == nil or type(policy.leaves) ~= "function" or type(policy.unlock) ~= "function" then return false end
    local leaves = policy.leaves(object)
    for _, leaf in ipairs(leaves) do
        if policy.playerLocked(leaf) then return false end
    end
    local freed = policy.unlock(object)
    for _, leaf in ipairs(leaves) do
        if policy.ask(leaf, "isLocked") == true and type(leaf.setLocked) == "function"
                and pcall(leaf.setLocked, leaf, false) then
            if type(leaf.syncIsoObject) == "function" then pcall(leaf.syncIsoObject, leaf, false, 0, nil, nil) end
            freed = true
        end
    end
    return freed
end

function Visit.invite(player, pending, house)
    local director = ProjectALife.SafehouseDirector
    local urgent = pending.state == "at_door" and pending.decideUntilMs ~= nil
    if (pending.state ~= "talking" and not urgent) or not Visit.entryRow(pending) then return false, "invite_unavailable" end
    local planned = Visit.plan(pending)
    if planned ~= nil and planned.fake then
        Visit.turn(house, pending, ProjectALife.SafehouseDirector.hours())
        return true, "Thanks for opening up, wasn't sure you would"
    end
    local door = house.door
    if type(door) ~= "table" or door.mode ~= "door" or tonumber(door.ix) == nil or tonumber(door.iy) == nil then
        return false, "door_not_adjacent"
    end
    local now, by = director.hours(), director.playerKey(player)
    local spot, untilHours = Visit.guestSpot(house), Visit.guestUntil(pending, now)
    local deadline = now + director.settings.inviteMinutes / 60
    local written = {}
    for _, uid in ipairs(pending.uids or {}) do
        local ok = Visit.write(uid, function(memory)
            if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                memory.guest = { house = house.key, pendingId = pending.id, by = by, untilHours = untilHours,
                    renewedHours = now, x1 = house.x1, y1 = house.y1, x2 = house.x2, y2 = house.y2, z = tonumber(door.z) or 0 }
                memory.visit.untilHours, memory.visit.renewedHours = deadline, now
                memory.stanceAnchor = spot
            end
        end)
        if not ok then
            for _, done in ipairs(written) do Visit.dropGuest(done, pending) end
            return false, "actor_write_refused"
        end
        written[#written + 1] = uid
        local traversal = ProjectALife.ObstacleTraversal
        if traversal ~= nil and type(traversal.forgiveCourtesy) == "function" then traversal.forgiveCourtesy(Visit.shell(uid)) end
    end
    Visit.unlockEntry(house)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    local reward = row ~= nil and type(row.outcomes) == "table" and tonumber(row.outcomes.reward) or 0
    pending.state, pending.untilHours, pending.invitedBy, pending.guestUntil = "invited", deadline, by, untilHours
    pending.question, pending.talkUntilMs = nil, nil
    pending.reward = director.rand(100) < reward
    director.dirty()
    director.deed("let_in", by, pending.faction, Visit.leadUid(pending), tostring(pending.id) .. "#in")
    return true, "Thanks, I'll come in and stay out from underfoot"
end

function Visit.guestEnd(pending, outcome, by, now)
    for _, uid in ipairs(pending.uids or {}) do Visit.dropGuest(uid, pending) end
    Visit.leave(pending, outcome, by, now)
end

function Visit.personOf(record)
    local memory = type(record) == "table" and record.memory or nil
    local person = type(memory) == "table" and memory.person or nil
    if type(person) ~= "table" or type(person.id) ~= "string" then return nil end
    return person
end

function Visit.personChoice(player, pending, listener, intent)
    local talk = ProjectALife.VisitorTalk
    if talk == nil or type(talk.choose) ~= "function" or intent == "GUEST_LEAVE" then return nil end
    if listener == nil or Visit.personOf(listener.record) == nil then return nil end
    local ok, words, result = talk.choose(player, listener.record.uid, intent, { door = true, pendingId = pending.id })
    if ok == nil or (type(result) == "table" and result.fallback == true) then return nil end
    return ok, words
end

Visit.guestHello = { "Bless you, I'll keep to myself, gone by morning", "Thanks again for the roof, I'll stay out of your way",
    "Quiet place you've got here, I appreciate it", "Don't mind me, I'll stay out from underfoot" }

function Visit.guestChoice(player, pending, house, intent, listener)
    local director = ProjectALife.SafehouseDirector
    local handled, spoken = Visit.personChoice(player, pending, listener, intent)
    if handled ~= nil then return handled, spoken end
    if intent == "DOOR_WHO" then
        if pending.squatting == true then return true, "One more day, that's all - I'll stay outta your hair" end
        local lines = Visit.guestHello
        pending.guestAsked = (tonumber(pending.guestAsked) or 0) + 1
        return true, lines[(pending.guestAsked - 1) % #lines + 1]
    end
    if intent ~= "GUEST_LEAVE" then return false, "invalid_choice" end
    Visit.guestEnd(pending, pending.squatting == true and "squatter_left" or "asked_to_leave", director.playerKey(player), director.hours())
    return true, "Fine, fine, I'm going - thanks for the roof though"
end

function Visit.thankYou(house, pending)
    local director, events = ProjectALife.SafehouseDirector, ProjectALife.SafehouseEvents
    local item = director.newItem(events.gifts[1 + director.rand(#events.gifts)])
    if item == nil then return false end
    local placed = ProjectALife.SafehouseDoor.place(house, { item })
    pending.rewardPlaced = placed ~= nil
    return placed ~= nil
end

function Visit.guestRule(pending)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    return row ~= nil and type(row.guest) == "table" and row.guest or {}
end

function Visit.betrayNow(house, pending, now)
    local plan = Visit.plan(pending)
    local window = Visit.guestRule(pending).turnHours
    if plan == nil or not plan.betray or pending.state ~= "inside" or type(window) ~= "table" then return false end
    local director = ProjectALife.SafehouseDirector
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local hour = tonumber(director.ask(time, "getTimeOfDay"))
    if hour == nil or hour < window[1] or hour >= window[2] then return false end
    local victims = {}
    for key in pairs(house.residents or {}) do victims[key] = true end
    if pending.invitedBy ~= nil then victims[pending.invitedBy] = true end
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            memory.hostileToPlayerKeys = type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys or {}
            for key in pairs(victims) do memory.hostileToPlayerKeys[key] = true end
        end)
    end
    pending.turned = true
    Visit.settle(house, pending, "guest_turned", nil, now)
    return true
end

function Visit.bittenTurns(house, pending, shell, now)
    local plan = Visit.plan(pending)
    if plan == nil or not plan.bitten then return false end
    local point = Visit.position(shell)
    local service = ProjectALife.SpawnService
    for _, uid in ipairs(pending.uids or {}) do
        if service ~= nil and type(service.retire) == "function" then pcall(service.retire, uid, "turned") end
    end
    if point ~= nil then Visit.spawnZombies(point.x, point.y, point.z, 1, true) end
    Visit.settle(house, pending, "turned_inside", pending.invitedBy, now)
    return true
end

function Visit.squat(pending, now)
    local plan = Visit.plan(pending)
    if plan == nil or not plan.squat or pending.squatting == true then return false end
    pending.squatting = true
    pending.untilHours = now + (tonumber(Visit.guestRule(pending).squatHours) or 48)
    ProjectALife.SafehouseDirector.dirty()
    return true
end

function Visit.hostDown(pending)
    local director = ProjectALife.SafehouseDirector
    for _, player in ipairs(director.players()) do
        if director.playerKey(player) == pending.invitedBy then return director.ask(player, "isDead") == true end
    end
    return false
end

Visit.arcOutcomes = { stay_cap = "left", trust_low = "left", no_visit = "left" }

function Visit.sessionOpen(pending)
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.sessionOpenFor) ~= "function" then return false end
    for _, uid in ipairs(pending.uids or {}) do
        if talk.sessionOpenFor(uid) then return true end
    end
    return false
end

function Visit.arcEnd(house, pending, now)
    local visitors = ProjectALife.VisitorDirector
    if type(pending.person) ~= "table" or visitors == nil or type(visitors.arc) ~= "function" then return false end
    if now >= (tonumber(pending.untilHours) or -math.huge) then return false end
    local soon = false
    for _, uid in ipairs(pending.uids or {}) do
        local action, why = visitors.arc(uid, now)
        if action == "leave_now" then
            Visit.guestEnd(pending, Visit.arcOutcomes[why] or "left", pending.invitedBy, now)
            return true
        elseif action == "leave_soon" then
            soon = why
        end
    end
    if soon and pending.arcSoon ~= true then
        pending.arcSoon = true
        pending.untilHours = math.min(tonumber(pending.untilHours) or math.huge, now + 1 / 3)
        ProjectALife.SafehouseDirector.dirty()
    end
    return false
end

function Visit.guestTick(house, pending, point, now)
    local director = ProjectALife.SafehouseDirector
    for _, resident in ipairs(director.onlineResidents(house)) do
        for _, uid in ipairs(pending.uids or {}) do
            if Visit.hostile(Visit.record(uid), resident) ~= false then
                Visit.settle(house, pending, "guest_turned", nil, now)
                return 1
            end
        end
    end
    if Visit.hostDown(pending) then
        Visit.guestEnd(pending, "host_gone", pending.invitedBy, now)
        return 1
    end
    if pending.state == "invited" then
        if point.x >= house.x1 and point.x < house.x2 and point.y >= house.y1 and point.y < house.y2 then
            pending.state, pending.untilHours, pending.insideAt = "inside", pending.guestUntil, now
            director.dirty()
        elseif now >= pending.untilHours then
            Visit.guestEnd(pending, "refused", pending.invitedBy, now)
            return 1
        end
    elseif Visit.betrayNow(house, pending, now) then
        return 1
    elseif Visit.sessionOpen(pending) then
        if now >= pending.untilHours - 1 / 12 then
            pending.untilHours = now + 1 / 6
            director.dirty()
        end
    elseif Visit.arcEnd(house, pending, now) then
        return 1
    elseif now >= pending.untilHours and Visit.squat(pending, now) then
        return 1
    elseif now >= pending.untilHours then
        if Visit.bittenTurns(house, pending, Visit.shell(Visit.leadUid(pending)), now) then return 1 end
        Visit.guestEnd(pending, pending.squatting == true and "squatter_left"
            or (pending.treated == true and "treated_wounded") or Visit.guestRule(pending).outcome or "let_sleep", pending.invitedBy, now)
        if pending.reward == true then Visit.thankYou(house, pending) end
        return 1
    end
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                memory.visit.untilHours, memory.visit.renewedHours = pending.untilHours, now
                if type(memory.guest) == "table" and memory.guest.pendingId == pending.id then
                    memory.guest.renewedHours = now
                end
            end
        end)
    end
    return 1
end

function Visit.census(player, pending, house, reportedBite)
    if pending.event ~= "law_census" or pending.question ~= "census" then return false, "census_question_required" end
    local count = 0
    for _, resident in ipairs(ProjectALife.SafehouseDirector.onlineResidents(house)) do
        local point = Visit.position(resident)
        if point ~= nil and point.x >= house.x1 and point.x < house.x2 and point.y >= house.y1 and point.y < house.y2
                and math.abs(point.z - (house.z or 0)) <= 1 then count = count + 1 end
    end
    pending.census = { home = count, reportedBite = reportedBite == true }
    Visit.leave(pending, "census_answer", ProjectALife.SafehouseDirector.playerKey(player), ProjectALife.SafehouseDirector.hours())
    return true, "Noted. " .. tostring(count) .. " residents home, and your report about bites. Stay inside. We're moving on."
end

Visit.reachSq = 12.25

function Visit.openPeer(player, listener, house)
    local inside, outside = Visit.position(player), Visit.position(listener.shell)
    if inside == nil or outside == nil or math.floor(inside.z) ~= math.floor(outside.z)
            or (inside.x - outside.x)^2 + (inside.y - outside.y)^2 > Visit.reachSq then return false, "not_adjacent" end
    if inside.x < house.x1 or inside.x >= house.x2 or inside.y < house.y1 or inside.y >= house.y2 then
        local talk = ProjectALife.Talk
        if talk == nil or type(talk.lineOfSight) ~= "function" or not talk.lineOfSight(player, listener.shell) then
            return false, "not_adjacent"
        end
        return true
    end
    local door = house.door
    if type(door) ~= "table" or door.mode ~= "door" then return false, "door_not_adjacent" end
    local object = ProjectALife.SafehouseDoor.entryDoor(door)
    if object == nil or type(object.IsOpen) ~= "function" then return false, "door_state_unavailable" end
    local ok, open = pcall(object.IsOpen, object)
    if not ok or open ~= true then return false, "door_closed" end
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.lineOfSight) ~= "function" or not talk.lineOfSight(player, listener.shell) then
        return false, "not_adjacent"
    end
    return true
end

function Visit.plan(pending)
    local saved = pending.plan or { version = 1 }
    if type(saved) ~= "table" or saved.version ~= 1 then return nil end
    for _, key in ipairs({ "hiddenWeapon", "bitten", "counting", "scam", "searchRefused", "betray", "squat", "fake" }) do
        if saved[key] ~= nil and type(saved[key]) ~= "boolean" then return nil end
    end
    local scam = pending.event == "trader" and saved.scam == true and ProjectALife.SafehouseDirector.settings.betrayal == true
    local betray = saved.betray == true and ProjectALife.SafehouseDirector.settings.betrayal == true
    return { scam = scam, searchRefused = saved.searchRefused == true and (saved.scam ~= true or scam),
        betray = betray, squat = saved.squat == true,
        fake = saved.fake == true and ProjectALife.SafehouseDirector.settings.betrayal == true,
        hiddenWeapon = saved.hiddenWeapon == true, bitten = saved.bitten == true,
        counting = saved.counting == true and (pending.event ~= "beggar" or ProjectALife.SafehouseDirector.settings.betrayal == true) }
end

function Visit.weaponRead(object, method)
    if object == nil or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object)
    if ok then return value end
    return nil
end

function Visit.weaponState(shell)
    local item = Visit.weaponRead(shell, "getPrimaryHandItem")
    local weapons = ProjectALife.Weapons
    if Visit.weaponRead(item, "IsWeapon") ~= true then
        item = weapons ~= nil and type(weapons.current) == "function" and weapons.current(shell) or nil
    end
    if item == nil or Visit.weaponRead(item, "getFullType") == "Base.BareHands" then return "EMPTY", nil end
    local name = Visit.weaponRead(item, "getDisplayName") or Visit.weaponRead(item, "getFullType") or "weapon"
    name = string.sub((tostring(name):gsub("[\r\n]", " ")), 1, 70)
    if Visit.weaponRead(item, "isAimedFirearm") == true or Visit.weaponRead(item, "isRanged") == true
            or (tonumber(Visit.weaponRead(item, "getMaxAmmo")) or 0) > 0 then return "FIREARM", name end
    return "MELEE", name
end

function Visit.weaponsReply(record)
    local current = record and Visit.record(record.uid)
    if current == nil or current.generation ~= record.generation then return nil end
    record = current
    local visit = record and type(record.memory) == "table" and record.memory.visit
    if type(visit) ~= "table" or visit.weaponsDown ~= true then return nil end
    local kind = visit.weaponKind
    if kind ~= "FIREARM" and kind ~= "MELEE" and kind ~= "EMPTY" then
        kind = Visit.weaponState(Visit.shell(record.uid))
    end
    local words = kind == "FIREARM" and "Alright, putting it away" or kind == "MELEE"
        and "Just this " .. tostring(visit.weaponName or "weapon") .. ", I'll lower it" or "Nothing in my hands, look"
    return "DOOR_WEAPONS_" .. kind, { weapon = visit.weaponName }, words
end

function Visit.replyPool(record, player, intent)
    if type(record) ~= "table" or not ProjectALife.SafehouseDirector.isPlayer(player) then return nil end
    local pending, house, current = Visit.live(record.uid)
    if pending == nil or current.generation ~= record.generation then return nil end
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    if house.residents[key] == nil then return nil end
    if Visit.doorPeer(player, record.uid) == nil
            and not (pending.state == "leaves" and pending.by == key) then return nil end
    local facts = {}
    if pending.event == "beggar" or pending.event == "trader" or pending.event == "law_census" or pending.event == "law_stay_inside" then
        facts[pending.event] = true
    end
    if intent == "DOOR_WHO" or Visit.questionIds[intent] then return nil end
    if intent == "DOOR_TRADE" then
        local plan = Visit.plan(pending)
        if plan ~= nil and plan.scam then
            facts.visit_pay_first = true
            return "VISIT_TELL_PAY_FIRST", facts
        end
    end
    if intent == "DOOR_WEAPONS_DOWN" and current.memory.visit.weaponsDown == true then
        facts.visit_weapons_down = true
        return Visit.weaponsReply(current), facts
    end
    if pending.by ~= key then return nil end
    if (intent == "DOOR_GIVE" and pending.outcome == "gave_food")
            or (intent == "DOOR_TRADE_CONFIRM" and pending.outcome == "fair_trade") then
        facts[pending.outcome] = true
        return "DOOR_THANKS", facts
    end
    if intent == "DOOR_LEAVE" and pending.outcome == "refused" then
        facts.refused = true
        return "DOOR_LEAVE_REPLY", facts
    end
    if intent == "DOOR_LEAVE_RUDE" and pending.outcome == "rude_no" then
        facts.rude = true
        return "DOOR_LEAVE_REPLY", facts
    end
    return nil
end

function Visit.headcountTell(player, listener, pending)
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    local tells = type(pending.tells) == "table" and pending.tells or {}
    local count = 0
    for _ in pairs(tells) do count = count + 1 end
    if tells[key] == nil and count >= 32 then return false, "visit_tell_busy" end
    local talking, reason = Visit.talking(pending)
    if not talking then return false, reason end
    tells[key] = { uid = listener.record.uid, generation = listener.record.generation, pendingId = pending.id,
        facts = { visit_asks_headcount = true, visit_looks_past_you = true } }
    pending.tells = tells
    ProjectALife.SafehouseDirector.dirty()
    return true, "[Looks past you] How many people live here?"
end

function Visit.observations(record, player)
    local facts = {}
    if type(record) ~= "table" or not ProjectALife.SafehouseDirector.isPlayer(player) then return facts end
    local pending, house, current = Visit.live(record.uid)
    if pending == nil or current.generation ~= record.generation then return facts end
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    if house.residents[key] == nil or Visit.peer(player, record.uid, true) == nil then return facts end
    local tell = type(pending.tells) == "table" and pending.tells[key] or nil
    if type(tell) == "table" and tell.uid == record.uid and tell.generation == record.generation
            and tell.pendingId == pending.id and type(tell.facts) == "table"
            and ProjectALife.SafehouseDirector.settings.betrayal == true then
        for _, fact in ipairs({ "visit_asks_headcount", "visit_looks_past_you" }) do
            if tell.facts[fact] == true then facts[fact] = true end
        end
    end
    local search = Visit.searchRow(pending, key, record.uid)
    if type(search) ~= "table" or search.uid ~= record.uid or search.generation ~= record.generation
            or search.pendingId ~= pending.id or type(search.facts) ~= "table" then return facts end
    for _, fact in ipairs({ "visit_searched", "visit_search_refused", "visit_hidden_weapon", "visit_bitten", "visit_counting", "visit_scam" }) do
        if search.facts[fact] == true then facts[fact] = true end
    end
    if ProjectALife.SafehouseDirector.settings.betrayal ~= true then facts.visit_scam = nil end
    if pending.event == "beggar" and ProjectALife.SafehouseDirector.settings.betrayal ~= true then facts.visit_counting = nil end
    return facts
end

function Visit.searchRow(pending, key, uid)
    local row = type(pending.searches) == "table" and pending.searches[key] or nil
    if type(row) ~= "table" then return nil end
    if row.uid == uid then return row end
    return type(row.peers) == "table" and row.peers[uid] or nil
end

function Visit.searched(record, player)
    local facts = Visit.observations(record, player)
    return facts.visit_searched == true or facts.visit_search_refused == true
end

function Visit.carried(shell)
    if shell == nil or type(shell.getInventory) ~= "function" then return nil end
    local ok, inventory = pcall(shell.getInventory, shell)
    if not ok or inventory == nil or type(inventory.getItems) ~= "function" then return nil end
    local items, named, containers, visited, seen = {}, {}, { inventory }, {}, {}
    local cursor, scanned = 1, 0
    while cursor <= #containers do
        local container = containers[cursor]
        cursor = cursor + 1
        if not visited[container] then
            visited[container] = true
            if type(container.getItems) ~= "function" then return nil end
            local read, list = pcall(container.getItems, container)
            if not read or list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return nil end
            local sized, size = pcall(list.size, list)
            if not sized or type(size) ~= "number" or size ~= size or size < 0 or size % 1 ~= 0 or scanned + size > 256 then return nil end
            scanned = scanned + size
            for index = 0, size - 1 do
                local found, item = pcall(list.get, list, index)
                if not found or item == nil or type(item.getDisplayName) ~= "function" then return nil end
                if not seen[item] then
                    seen[item] = true
                    local shown, name = pcall(item.getDisplayName, item)
                    if not shown or type(name) ~= "string" then return nil end
                    name = string.sub(string.gsub(name, "[<>\r\n]", ""), 1, 120)
                    if name == "" then return nil end
                    if named[name] == nil then
                        if #items >= 32 then return nil end
                        named[name] = { name = name, count = 0 }
                        items[#items + 1] = named[name]
                    end
                    named[name].count = named[name].count + 1
                    if type(instanceof) == "function" and instanceof(item, "InventoryContainer") then
                        if type(item.getInventory) ~= "function" or #containers >= 16 then return nil end
                        local opened, inner = pcall(item.getInventory, item)
                        if not opened or inner == nil then return nil end
                        containers[#containers + 1] = inner
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

function Visit.searchItems(record, player)
    if not Visit.observations(record, player).visit_searched then return nil end
    local pending = Visit.live(record.uid)
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    local row = pending and Visit.searchRow(pending, key, record.uid)
    if row == nil or type(row.items) ~= "table" then return nil end
    local items = {}
    for _, item in ipairs(row.items) do items[#items + 1] = { name = item.name, count = item.count } end
    return items
end

function Visit.search(player, listener, pending, house)
    local open, why = Visit.openPeer(player, listener, house)
    if not open then return false, why end
    if Visit.searched(listener.record, player) then return false, "visit_search_done" end
    local plan = Visit.plan(pending)
    if plan == nil then return false, "visit_plan_unsupported" end
    local facts, items = {}, nil
    if plan.searchRefused then facts.visit_search_refused = true
    else
        items = Visit.carried(listener.shell)
        if items == nil then return false, "inventory_api_unavailable" end
        local talking, reason = Visit.talking(pending)
        if not talking then return false, reason end
        facts.visit_searched = true
        if plan.hiddenWeapon then facts.visit_hidden_weapon = true end
        if plan.bitten then facts.visit_bitten = true end
        if plan.counting then facts.visit_counting = true end
    end
    if plan.scam then facts.visit_scam = true end
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    pending.searches = type(pending.searches) == "table" and pending.searches or {}
    local count = 0
    for _, saved in pairs(pending.searches) do
        count = count + 1
        if type(saved) == "table" and type(saved.peers) == "table" then
            for _ in pairs(saved.peers) do count = count + 1 end
        end
    end
    if Visit.searchRow(pending, key, listener.record.uid) == nil and count >= 32 then return false, "visit_search_busy" end
    local saved = { uid = listener.record.uid, generation = listener.record.generation, pendingId = pending.id, facts = facts, items = items }
    local previous = pending.searches[key]
    if type(previous) ~= "table" then pending.searches[key] = saved
    elseif previous.uid == listener.record.uid then
        saved.peers = previous.peers
        pending.searches[key] = saved
    else
        previous.peers = type(previous.peers) == "table" and previous.peers or {}
        previous.peers[listener.record.uid] = saved
    end
    ProjectALife.SafehouseDirector.dirty()
    local opinion = ProjectALife.NpcOpinion
    if facts.visit_searched and not plan.hiddenWeapon and not plan.bitten and not plan.counting and not plan.scam
            and opinion ~= nil and type(opinion.note) == "function" then opinion.note("rude", listener.record, player) end
    if plan.scam then
        Visit.leave(pending, "scam_cancelled", nil, ProjectALife.SafehouseDirector.hours())
        return true, "Nobody pats me down, forget the trade, I'm gone"
    end
    if plan.searchRefused then return true, "Nope, nobody's going through my pockets" end
    if opinion ~= nil and type(opinion.greetTone) == "function" and opinion.greetTone(listener.record, player) == "cold" then
        return true, "Fine, check and let me get out of here"
    end
    return true, "Go on then, look, I got nothing to hide"
end

function Visit.giftKind(pending)
    if type(pending) ~= "table" then return nil end
    if pending.event == "neighbour_borrow" then return "LEND_TOOL" end
    local asked = ProjectALife.SafehouseEvents.row(pending.event)
    return pending.event == "beggar" and "ASK_FOOD" or (asked ~= nil and asked.asks) or nil
end

function Visit.giftEntries(player, kind)
    local robbery, entries = ProjectALife.ModuleRobbery, {}
    if player == nil or type(player.getInventory) ~= "function" or robbery == nil
            or type(robbery.gatherItems) ~= "function" then return entries end
    local gathered, listed = pcall(robbery.gatherItems, player, { playerOnly = true, limit = 256 })
    if not gathered or type(listed) ~= "table" then return entries end
    for _, entry in ipairs(listed) do
        local item = entry.source == "player" and entry.item or nil
        if item ~= nil and type(item.isEquipped) == "function" and type(item.getDisplayCategory) == "function"
                and type(item.getFullType) == "function" and type(item.getCategory) == "function"
                and type(item.getID) == "function" and type(item.getDisplayName) == "function" then
            local categorized, category = pcall(item.getCategory, item)
            local matched, safe = true, true
            if kind ~= "LEND_TOOL" then matched, safe = pcall(ProjectALife.TalkSupplies.matches, item, kind) end
            local named, name = pcall(item.getDisplayName, item)
            local typed, full = pcall(item.getFullType, item)
            local identified, id = pcall(item.getID, item)
            if categorized and (kind ~= "ASK_FOOD" or category == "Food") and matched and safe == true
                    and (kind ~= "LEND_TOOL" or Visit.lendable(item, typed and full or nil))
                    and named and type(name) == "string" and #name > 0 and typed and type(full) == "string"
                    and identified and type(id) == "number" and id == id and id % 1 == 0 then
                entry.id, entry.name, entry.fullType = id, string.sub(name, 1, 160), full
                entries[#entries + 1] = entry
            end
        end
    end
    return entries
end

function Visit.giftPicker(player, listener, pending, house, kind)
    local now, count = Visit.millis(), 0
    if now == nil then return false, "trade_clock_unavailable" end
    for key, saved in pairs(Visit.gifts) do
        if now >= saved.untilMs or Visit.live(saved.uid) == nil then Visit.gifts[key] = nil else count = count + 1 end
    end
    local key = pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))
    if count >= 128 and Visit.gifts[key] == nil then return false, "trade_quotes_busy" end
    local entries = Visit.giftEntries(player, kind)
    if #entries == 0 then
        Visit.gifts[key] = nil
        return false, kind == "LEND_TOOL" and "no_tool_to_lend" or (kind == "ASK_MEDS" and "no_safe_meds" or "no_safe_food")
    end
    local sequence = pending.giftSequence == nil and 0 or pending.giftSequence
    if type(sequence) ~= "number" or sequence ~= sequence or sequence < 0 or sequence % 1 ~= 0
            or sequence + 1 >= 9007199254740992 then return false, "gift_identity_unavailable" end
    pending.giftSequence = sequence + 1
    local token = pending.id .. ":gift:" .. string.format("%.0f", pending.giftSequence)
    local rows, grouped = {}, {}
    for _, entry in ipairs(entries) do
        local group = entry.fullType .. ":" .. entry.name
        local row = grouped[group]
        if row == nil then
            row = { name = entry.name, itemId = entry.id, count = 0, fullType = entry.fullType }
            grouped[group], rows[#rows + 1] = row, row
        end
        row.count = row.count + 1
    end
    if kind == "LEND_TOOL" then Visit.rankTools(pending, rows) end
    Visit.gifts[key] = { token = token, uid = listener.record.uid, generation = listener.record.generation,
        untilMs = now + 60000, kind = kind, entries = entries, rows = rows }
    ProjectALife.SafehouseDirector.dirty()
    if kind == "LEND_TOOL" then return true, "Choose which tool to lend" end
    return true, kind == "ASK_MEDS" and "Choose one medical supply to give" or "Choose one food item to give"
end

function Visit.giftView(player, uid)
    local listener, pending = Visit.doorPeer(player, uid)
    if listener == nil then return nil end
    local key = pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))
    local saved, now = Visit.gifts[key], Visit.millis()
    if saved == nil or now == nil or now >= saved.untilMs or saved.uid ~= uid
            or saved.generation ~= listener.record.generation then return nil end
    local rows = {}
    for _, row in ipairs(saved.rows) do
        rows[#rows + 1] = { name = row.name, count = row.count, itemId = row.itemId, wanted = row.wanted == true or nil }
    end
    local shown = saved.kind == "LEND_TOOL" and "DOOR_LEND" or (saved.kind == "ASK_MEDS" and "DOOR_TREAT" or "DOOR_GIVE")
    return { token = saved.token, rows = rows, intent = shown }
end

function Visit.give(player, listener, pending, house, gift)
    local kind = Visit.giftKind(pending)
    if kind == nil or kind == "LEND_TOOL" then return false, "food_not_requested" end
    if kind == "ASK_MEDS" and pending.treated == true then return false, "already_treated" end
    local open, why = Visit.openPeer(player, listener, house)
    if not open then return false, why end
    if type(player.getInventory) ~= "function" or type(listener.shell.getInventory) ~= "function" then
        return false, "inventory_api_unavailable"
    end
    local got, source = pcall(player.getInventory, player)
    local read, destination = pcall(listener.shell.getInventory, listener.shell)
    if not got or not read or source == nil or destination == nil or type(source.getItems) ~= "function" then
        return false, "inventory_unavailable"
    end
    local listed, items = pcall(source.getItems, source)
    if not listed or items == nil or type(items.size) ~= "function" or type(items.get) ~= "function" then
        return false, "inventory_unavailable"
    end
    if gift == nil then return Visit.giftPicker(player, listener, pending, house, kind) end
    local key = pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))
    local saved, now = Visit.gifts[key], Visit.millis()
    if type(gift) ~= "table" or type(gift.token) ~= "string" or #gift.token > 256
            or type(gift.itemId) ~= "number" or gift.itemId ~= gift.itemId or gift.itemId % 1 ~= 0
            or saved == nil or saved.token ~= gift.token or now == nil or now >= saved.untilMs
            or saved.uid ~= listener.record.uid or saved.generation ~= listener.record.generation or saved.kind ~= kind then
        return false, "gift_selection_required"
    end
    local original
    for _, entry in ipairs(saved.entries) do if entry.id == gift.itemId then original = entry; break end end
    if original == nil then return false, "gift_item_changed" end
    local selected
    for _, entry in ipairs(Visit.giftEntries(player, kind)) do
        if entry.item == original.item and entry.container == original.container and entry.id == gift.itemId then
            selected, source = entry.item, entry.container; break
        end
    end
    if selected == nil then return false, "gift_item_changed" end
    local robbery = ProjectALife.ModuleRobbery
    if robbery == nil or type(robbery.removeItem) ~= "function" then return false, "inventory_api_unavailable" end
    local shellState = ProjectALife.ShellState
    if shellState == nil or type(shellState.markScavenged) ~= "function" or type(selected.getModData) ~= "function" then
        return false, "item_persistence_unavailable"
    end
    local dataOk, data = pcall(selected.getModData, selected)
    if not dataOk or type(data) ~= "table" then return false, "item_persistence_unavailable" end
    local previous = data.ProjectALifeScavenged
    local markedOk, marked = pcall(shellState.markScavenged, selected)
    if not markedOk or marked ~= true then return false, "item_persistence_unavailable" end
    local moved, reason = robbery.removeItem({ item = selected, container = source, source = "player" },
        destination, listener.shell)
    if not moved then
        data.ProjectALifeScavenged = previous
        if reason == "rollback_failed" then Visit.leave(pending, "give_transfer_uncertain", nil, ProjectALife.SafehouseDirector.hours()) end
        return false, reason
    end
    Visit.gifts[key] = nil
    if kind == "ASK_MEDS" then return Visit.treated(player, pending, house) end
    Visit.leave(pending, "gave_food", ProjectALife.SafehouseDirector.playerKey(player), ProjectALife.SafehouseDirector.hours())
    return true, "Thanks, I'll take this and go"
end

function Visit.treated(player, pending, house)
    local director = ProjectALife.SafehouseDirector
    local plan = Visit.plan(pending)
    local now = director.hours()
    if plan ~= nil and plan.fake then
        Visit.turn(house, pending, now)
        return true, "Hey, thanks... didn't think anybody'd open"
    end
    pending.treated, pending.treatedBy = true, director.playerKey(player)
    pending.untilHours = now + (tonumber(Visit.guestRule(pending).hours) or 1)
    director.dirty()
    return true, "Oh, that's better... let me sit a minute, then I'll go"
end

function Visit.turn(house, pending, now)
    local victims = {}
    for key in pairs(house.residents or {}) do victims[key] = true end
    if pending.invitedBy ~= nil then victims[pending.invitedBy] = true end
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            memory.hostileToPlayerKeys = type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys or {}
            for key in pairs(victims) do memory.hostileToPlayerKeys[key] = true end
        end)
    end
    pending.turned = true
    return Visit.settle(house, pending, "guest_turned", nil, now)
end

Visit.questionIds = { DOOR_NEED = true, DOOR_HEALTH = true, DOOR_COMPANY = true, DOOR_STAY = true, DOOR_WHAT = true }

Visit.needLines = {
    beggar = "Food, please... anything you can spare",
    trader = "A fair swap, let me show you what I'm carrying first",
    law_census = "How many people live here, and has anybody been bitten?",
    law_stay_inside = "Stay inside and keep the door shut, that's all we're asking",
    sleep_one_night = "Somewhere to sleep tonight... I'll stay where you tell me",
    chased = "Somewhere to hide! I can't stay out here!",
    wounded = "A bandage or something to clean this with... it hurts like hell",
    racket = "Three supplies, then we leave your place alone for the week",
    neighbour = "Nothing from you, I came to warn you about people around here",
    returning_things = "Nothing, I just came to bring this back",
    radio_rumour = "Nothing, I only wanted to tell you what I heard",
    drunk = "Company! C'mon, don't leave me talking to a door!",
    preacher = "A minute of your time... you don't have to let me in",
    medic_rounds = "Two supplies if you want treatment, but I can have a look first",
    messenger = "Someone to carry a message, ask me where before you agree",
    neighbour_borrow = "A tool I can borrow for a day or two, if you've got one spare",
    law_guns = "The weapons you're holding, we're collecting them",
    asks_help = "Help getting my friend out... ask me where, I'll explain",
    law_fake = "Just open up so we can check inside, alright?",
    family_in_need = "A roof for a little while, and something to eat if you can spare it",
    returning_guest = "Nothing much, I was passing and wanted to say hello",
    lodger_request = "A place to stay a few nights, I'll earn my keep",
    panic_knock = "Open the door, quick, they're right behind me!",
    weather_shelter = "Somewhere dry until this blows over",
    medical_visit = "A look at this wound, and a bandage if you have one",
}

function Visit.questionLine(pending, intent, facts)
    if intent == "DOOR_WHAT" then return Visit.wantAnswer(pending) end
    if intent == "DOOR_NEED" then
        local want = pending.event == "neighbour_borrow" and Visit.wantOf(pending) or nil
        if want ~= nil and want.fullType ~= nil then return "Just " .. want.noun .. " for a day or two, if you've got one spare" end
        return Visit.needLines[pending.event] or "A minute to explain why I came"
    end
    if intent == "DOOR_COMPANY" then
        local count = #(pending.uids or {})
        if count <= 1 then return "Just me" end
        return "There's " .. tostring(count) .. " of us here, we're together"
    end
    if intent == "DOOR_HEALTH" then
        if type(facts) == "table" and facts.visit_bitten == true then return "Yeah... I was bitten, I should've told you before" end
        if pending.event == "wounded" then
            if pending.treated == true then return "Still hurts, but that helped... thank you" end
            return "I'm hurt, yeah... will you take a look before you decide?"
        end
        if pending.event == "chased" then return "I don't think they got me... just let me catch my breath!" end
        if pending.event == "drunk" then return "Bitten? Nooo, just... don't ask me to walk a straight line" end
        if pending.event == "beggar" then return "Weak from not eating, mostly... you can look before you come near" end
        return "I don't know of any bites, but I get why you're asking"
    end
    if pending.squatting == true then return "I need another day... I haven't got anywhere else" end
    if pending.event == "sleep_one_night" then return "Just tonight, I'll be gone by seven in the morning" end
    if pending.event == "chased" then return "Until it's safe to leave... I don't know how long that'll take" end
    if pending.event == "wounded" then return "Until I can get moving again, I won't ask you to keep me forever" end
    return "Only as long as you'll allow, this is your home"
end

Visit.themedStats = { asked = 0, thanked = 0, deedGiven = 0, deedHeld = 0, idAsked = 0, exposed = 0, hagglesWon = 0,
    hagglesLost = 0, patience = 0, radioNews = 0, radioHeard = 0, radioSkipped = 0 }

function Visit.themedQaLine()
    local s = Visit.themedStats
    local outfits = ProjectALife.VisitOutfits
    return "[ALIFE-QA] DoorThemed: asked=" .. tostring(s.asked) .. " thanked=" .. tostring(s.thanked)
        .. " deedGiven=" .. tostring(s.deedGiven) .. " deedHeld=" .. tostring(s.deedHeld) .. " idAsked=" .. tostring(s.idAsked)
        .. " exposed=" .. tostring(s.exposed) .. " haggleWon=" .. tostring(s.hagglesWon) .. " haggleLost=" .. tostring(s.hagglesLost)
        .. " patience=" .. tostring(s.patience) .. " radioNews=" .. tostring(s.radioNews) .. " radioHeard=" .. tostring(s.radioHeard)
        .. " radioSkipped=" .. tostring(s.radioSkipped) .. (outfits ~= nil and (" | " .. outfits.qaLine()) or "")
end

Visit.radioTopics = {
    gave_food = { news = "..people say someone out there feeds strangers at the door, a decent house, they say",
        recap = "That a house out here feeds strangers at the door, and they said it's a decent one" },
    let_sleep = { news = "..word is a house nearby puts travellers up for the night, no questions asked",
        recap = "That a house near here lets travellers sleep under its roof" },
    treated_wounded = { news = "..they say somebody out there patches up the wounded at the window",
        recap = "That somebody here patches up the wounded" },
    sheltered_chased = { news = "..a house nearby opened its door to someone running, folks are talking about it",
        recap = "That someone here opened the door to a runner" },
    fair_trade = { news = "..traders say there is a house out here that deals fair at the door",
        recap = "That you deal fair at the door, traders like that" },
    neighbour_watch = { news = "..the neighbours say somebody out there watches the road for everyone",
        recap = "That somebody here watches the road for the neighbours" },
    rude_no = { news = "..careful on the east road, a house out there turns people away at the door",
        recap = "That a house out here doesn't open for anyone, and not nicely" },
    generic = { news = "..somebody is holding a house out there, quiet and careful, keeps to themselves",
        recap = "That someone holds a house out here and keeps the door shut" },
}

function Visit.radioTopic(house)
    for _, deed in ipairs(type(house.deeds) == "table" and house.deeds or {}) do
        if Visit.radioTopics[deed.kind] ~= nil then return deed.kind end
    end
    return "generic"
end

function Visit.radioNews(house, pending)
    pending.radioDone = true
    local topic = Visit.radioTopic(house)
    pending.radioTopic = topic
    local script = ProjectALife.SafehouseScript
    local stand = Visit.standFor(house, pending)
    local sent = 0
    if script ~= nil and type(script.radioNews) == "function" then
        local ok, count = pcall(script.radioNews, house, Visit.nearResidents(house, stand), "Radio: " .. Visit.radioTopics[topic].news)
        sent = ok and tonumber(count) or 0
    end
    pending.radioHeard = sent > 0
    local stats = Visit.themedStats
    if pending.radioHeard then stats.radioNews, stats.radioHeard = stats.radioNews + 1, stats.radioHeard + 1
    else stats.radioSkipped = stats.radioSkipped + 1 end
    ProjectALife.SafehouseDirector.dirty()
    return pending.radioHeard
end

function Visit.kindWord(player, pending, tag)
    local director = ProjectALife.SafehouseDirector
    local stats = Visit.themedStats
    local door = Visit.door()
    if pending[tag] == true then return false end
    pending[tag] = true
    local accepted, why = director.deed(door.thankDeed, director.playerKey(player), pending.faction, Visit.leadUid(pending),
        tostring(pending.id) .. ":" .. tag)
    if accepted == true then stats.deedGiven = stats.deedGiven + 1 else stats.deedHeld = stats.deedHeld + 1 end
    return accepted == true, why
end

function Visit.themed(player, uid, pending, house, intent)
    local door, stats, director = Visit.door(), Visit.themedStats, ProjectALife.SafehouseDirector
    if not Visit.choices(uid, player)[intent] then return false, "invalid_choice" end
    local ready, reason = Visit.scriptReady(pending)
    if not ready then return false, reason end
    local talking, whyTalk = Visit.talking(pending)
    if not talking then return false, whyTalk end
    local event = pending.event
    local entry = door.entry(event, intent)
    if entry == nil then return false, "invalid_choice" end
    pending.themed = type(pending.themed) == "table" and pending.themed or { total = 0 }
    local seen = tonumber(pending.themed[intent]) or 0
    local now, by = director.hours(), director.playerKey(player)
    local line = nil
    if intent == "DOOR_HAGGLE" then
        pending.haggled = true
        if director.rand(100) < door.haggleChance then
            pending.haggleWon = true
            stats.hagglesWon = stats.hagglesWon + 1
            line = entry[1]
        else
            stats.hagglesLost = stats.hagglesLost + 1
            line = entry.denied or entry[2]
        end
    else
        local fake = event == "law_fake"
        line = door.line(event, intent, seen, fake)
        if intent == "DOOR_ASK_ID" then
            stats.idAsked = stats.idAsked + 1
            if fake then
                if pending.exposed ~= true then stats.exposed = stats.exposed + 1 end
                pending.exposed = true
                pending.exposedAtHours = pending.exposedAtHours or now
            else
                pending.idShown = true
            end
        elseif intent == "DOOR_ASK_A" and event == "radio_rumour" and seen == 0 and pending.radioHeard == true then
            line = Visit.radioTopics[pending.radioTopic or "generic"].recap
        elseif intent == "DOOR_ASK_A" and event == "radio_rumour" and seen == 0 then
            line = "Only what people say on the road, nothing I can pin down"
        elseif (intent == "DOOR_THANK" or intent == "DOOR_KEEP") and entry.deed == true then
            stats.thanked = stats.thanked + 1
            Visit.kindWord(player, pending, intent == "DOOR_THANK" and "thanked" or "kept")
        elseif intent == "DOOR_THANK" then
            stats.thanked = stats.thanked + 1
        end
    end
    pending.themed[intent] = seen + 1
    if intent ~= "DOOR_THANK" and intent ~= "DOOR_HAGGLE" then
        stats.asked = stats.asked + 1
        pending.themed.total = (tonumber(pending.themed.total) or 0) + 1
        if pending.themed.total >= door.patience then
            stats.patience = stats.patience + 1
            if event == "racket" then Visit.ladderUp(house, pending, "racket_refused") end
            Visit.leave(pending, "refused", by, now)
            return true, door.leaveLine(event, true) or "That's enough questions, I'm going"
        end
    end
    director.dirty()
    return true, line
end

Visit.whoLines = {
    beggar = { "Sorry to bother you... I'm looking for food, can you spare anything?" },
    trader = { "I've got things to trade, want to see what we could swap?" },
    medic_rounds = { "Medic, making rounds - I'll check you over for two supplies, looking's free" },
    messenger = { "Got a note for the folks at the {name}, {dist} tiles {dir} - can you run it over in a day or two?" },
    neighbour_borrow = { "Sorry to bug you, could I borrow a tool a day or two? Bring it right back" },
    law_guns = { "Sheriff's office, we're collecting guns around here - hand over what you're holding" },
    asks_help = { "Please - my friend's stuck at the {name}, {dist} tiles {dir}, come with me?",
        "My friend's hurt at the {name}, {dist} tiles {dir} - come alone, leave the gun, you'll spook them" },
    chased = { "Please! They're right behind me! Let me in!" },
    wounded = { "I'm hurt, you got a bandage? I'll stay out here", "I'm hurt, let me in- quick, please!" },
    racket = { "Nice house. You want us leaving you alone? Then let's talk about what you can spare" },
    neighbour = { "Live just down the road - {hostile} people were seen around here, I'd lock that door" },
    returning_things = { "Found this outside, think it's yours? Leaving it by the door" },
    radio_rumour = { "I heard about you on the radio just now, they were talking about this house",
        "Word gets around about houses out here, so I wanted to see yours for myself" },
    drunk = { "Heyyy! Open up, friend! I've got a song for you!" },
    law_fake = { "Sheriff's department, open up, we're checking houses" },
    preacher = { "We got a little service Sundays, you'd be welcome - come on out" },
    family_in_need = { "Please, we've nowhere to go - could we come in out of the road for a while?" },
    returning_guest = { "It's me again, I hoped you'd still be here" },
    lodger_request = { "I'm after somewhere to stay for a few nights, I can pull my weight" },
    panic_knock = { "Open up, please! They're right behind me!" },
    weather_shelter = { "Terrible out here - could I wait inside until it passes?" },
    medical_visit = { "I'm hurt, I've been walking all day - do you have anything for it?" },
}

function Visit.whoLine(pending)
    local lines = Visit.whoLines[pending.event]
    if lines == nil then return nil end
    local plan = Visit.plan(pending)
    local text = Visit.wantRequest(pending) or lines[1]
    if pending.event == "radio_rumour" and pending.radioHeard ~= true then text = lines[2] end
    if plan ~= nil and plan.fake and lines[2] ~= nil then text = lines[2] end
    if pending.event == "asks_help" and plan ~= nil and plan.betray and (tonumber(pending.asked) or 0) >= 1 then text = lines[2] end
    local director = ProjectALife.SafehouseDirector
    local hostile = pending.hostile ~= nil and director.factionName(pending.hostile) or "armed"
    local place = type(pending.place) == "table" and pending.place or {}
    text = string.gsub(text, "{hostile}", function() return hostile end)
    text = string.gsub(text, "{name}", function() return tostring(place.name or "place") end)
    text = string.gsub(text, "{dist}", function() return tostring(place.dist or "?") end)
    text = string.gsub(text, "{dir}", function() return tostring(place.dir or "north") end)
    return text
end

function Visit.whoDone(player, pending, house)
    local director = ProjectALife.SafehouseDirector
    local now, by = director.hours(), director.playerKey(player)
    local text = Visit.whoLine(pending)
    if pending.event == "neighbour" then
        local talking, reason = Visit.talking(pending)
        if not talking then return false, reason end
        pending.completedOutcome, pending.completedBy = "neighbour_watch", by
        director.dirty()
        return true, text
    end
    if pending.event == "returning_things" then
        local talking, reason = Visit.talking(pending)
        if not talking then return false, reason end
        if pending.returnAttempted ~= true then
            pending.returnAttempted = true
            Visit.thankYou(house, pending)
        end
        pending.completedOutcome, pending.completedBy = "returned_things", by
        director.dirty()
        return true, text
    end
    return nil
end

function Visit.ladderUp(house, pending, cause)
    local director = ProjectALife.SafehouseDirector
    house.ladder = type(house.ladder) == "table" and house.ladder or {}
    local row = type(house.ladder[pending.faction]) == "table" and house.ladder[pending.faction] or { step = 0 }
    row.step, row.atHours, row.cause = math.max(tonumber(row.step) or 0, 2), director.hours(), cause
    house.ladder[pending.faction] = row
    director.dirty()
end

function Visit.inventoryOf(listener)
    if listener.shell ~= nil and type(listener.shell.getInventory) == "function" then
        local ok, value = pcall(listener.shell.getInventory, listener.shell)
        if ok then return value end
    end
    return nil
end

function Visit.takeItems(player, listener, count)
    local entries = Visit.tradeEntries(player)
    table.sort(entries, function(a, b) return a.value < b.value end)
    if #entries < count then return nil, "not_enough_items" end
    local destination = Visit.inventoryOf(listener)
    if destination == nil then return nil, "inventory_unavailable" end
    local robbery, paid = ProjectALife.ModuleRobbery, 0
    for index = 1, count do
        local entry = entries[index]
        if robbery.removeItem({ item = entry.item, container = entry.container, source = "player" }, destination, listener.shell) then
            paid = paid + 1
        end
    end
    return paid
end

function Visit.mend(player)
    local body = ProjectALife.SafehouseDirector.ask(player, "getBodyDamage")
    local parts = body ~= nil and ProjectALife.SafehouseDirector.ask(body, "getBodyParts") or nil
    local size = parts ~= nil and tonumber(ProjectALife.SafehouseDirector.ask(parts, "size")) or 0
    for index = 0, size - 1 do
        local part = parts:get(index)
        if part ~= nil then
            if type(part.setBleeding) == "function" then pcall(part.setBleeding, part, false) end
            if type(part.setBleedingTime) == "function" then pcall(part.setBleedingTime, part, 0) end
            if type(part.AddHealth) == "function" then pcall(part.AddHealth, part, 20) end
        end
    end
end

function Visit.treatMe(player, listener, pending)
    if pending.event ~= "medic_rounds" or pending.treated == true then return false, "treatment_unavailable" end
    local director = ProjectALife.SafehouseDirector
    local paid, why = Visit.takeItems(player, listener, 2)
    if paid == nil then return false, why end
    local now, by = director.hours(), director.playerKey(player)
    pending.treated = true
    if paid < 2 then
        Visit.leave(pending, "medic_short", by, now)
        return true, "That ain't enough to check you right, next time maybe"
    end
    Visit.mend(player)
    Visit.leave(pending, "medic_treated", by, now)
    return true, "Keep checking how you feel. If it gets worse, don't ignore it"
end

function Visit.takeJob(player, pending, house)
    local director = ProjectALife.SafehouseDirector
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    local place = pending.place
    if row == nil or type(row.job) ~= "table" or type(place) ~= "table" or tonumber(place.x) == nil then return false, "job_unavailable" end
    local plan = Visit.plan(pending) or {}
    local now = director.hours()
    house.jobs = type(house.jobs) == "table" and house.jobs or {}
    while #house.jobs >= 4 do table.remove(house.jobs, 1) end
    house.jobs[#house.jobs + 1] = { id = pending.id, kind = row.job.kind, faction = pending.faction, by = director.playerKey(player),
        x = place.x, y = place.y, name = place.name, ambush = plan.betray == true and row.job.kind == "help",
        untilHours = now + (tonumber(row.job.days) or 3) * 24 + (tonumber(place.dist) or 0) / 10 }
    Visit.leave(pending, "job_taken", director.playerKey(player), now)
    if row.job.kind == "deliver" then return true, "Thanks - just get it there, they'll know what it means" end
    return true, "Thank you... hurry, please, HURRY!"
end

Visit.toolClasses = {
    hammer = { "Base.Hammer", "Base.HammerForged", "Base.ClubHammer", "Base.ClubHammerForged", "Base.BallPeenHammer",
        "Base.BallPeenHammerForged", "Base.SmithingHammer", "Base.HammerStone", "Base.WoodenMallet", "Base.Sledgehammer",
        "Base.Sledgehammer2", "Base.SledgehammerForged" },
    driver = { "Base.Screwdriver", "Base.Screwdriver_Old", "Base.Screwdriver_Improvised", "Base.Multitool" },
    wrench = { "Base.Wrench", "Base.PipeWrench", "Base.Ratchet" },
    pliers = { "Base.Pliers", "Base.MetalworkingPliers", "Base.ViseGrips", "Base.BoltCutters", "Base.SheetMetalSnips" },
    saw = { "Base.Saw", "Base.GardenSaw", "Base.SmallSaw", "Base.CrudeSaw", "Base.Saw_Flint" },
    pry = { "Base.Crowbar", "Base.CrowbarForged", "Base.TireIron" },
    dig = { "Base.Shovel", "Base.Shovel2", "Base.SpadeForged", "Base.SpadeWood", "Base.HandShovel", "Base.SnowShovel",
        "Base.GardenHoe", "Base.GardenHoeForged", "Base.HandFork" },
    rake = { "Base.Rake", "Base.LeafRake" },
}
Visit.toolWorks = { hammer = { pry = true, wrench = true }, driver = { pry = true }, wrench = { pliers = true },
    pliers = { wrench = true }, saw = {}, pry = { hammer = true }, dig = { rake = true }, rake = { dig = true } }
Visit.toolClassOf = {}

function Visit.indexTools()
    Visit.toolClassOf = {}
    for class, list in pairs(Visit.toolClasses) do
        for _, full in ipairs(list) do Visit.toolClassOf[full] = class end
    end
end
Visit.indexTools()

Visit.wantTools = {
    { full = "Base.Hammer", name = "hammer", noun = "a hammer", class = "hammer", reasons = {
        { "Fence came down last night", "Something big took the back fence down in the night, I have to nail it up before it comes back",
            "The fence, like I said.. the back one's down and I've got nothing to nail it with" },
        { "Got a window to board up", "The kitchen window's been broken since the weekend and it's getting cold, I need to board it",
            "Boards for the window, I've got the planks just no hammer" } } },
    { full = "Base.Saw", name = "saw", noun = "a saw", class = "saw", reasons = {
        { "Tree came down on my shed", "A tree came down across the shed roof and I can't get the door open, I have to cut my way in",
            "The tree, on the shed.. I just need to cut it up" },
        { "Need to cut some kindling", "Out of firewood, got a pile of old pallets and nothing to cut them with",
            "Pallets for the stove, I told you, I just need a saw" } } },
    { full = "Base.Screwdriver", name = "screwdriver", noun = "a screwdriver", class = "driver", reasons = {
        { "Back door latch fell off", "The latch on my back door worked itself loose and I can't lock up at night",
            "The latch.. the back door, I've got the screws just nothing to turn them" },
        { "Radio's got a loose panel", "My radio's rattling and I think a wire came off inside, I want to open it up",
            "The radio, it's dead and I want to look inside" } } },
    { full = "Base.Wrench", name = "wrench", noun = "a wrench", class = "wrench", reasons = {
        { "Rain barrel tap seized up", "The tap on my rain barrel seized and I can't get any water out of it",
            "The tap on the barrel, it won't turn without something to grip it" },
        { "Bike wheel's loose", "My bike's all I've got for getting around and the wheel nut is working loose",
            "The bike wheel, I just need to tighten one nut" } } },
    { full = "Base.Pliers", name = "pliers", noun = "a pair of pliers", class = "pliers", reasons = {
        { "Wire snapped on the chicken run", "The wire on my chicken run snapped and the birds keep getting out",
            "The chickens.. the wire's snapped, I just need to twist it back" },
        { "Got a bent nail stuck", "There's a bent nail in my door frame and my fingers can't pull it out",
            "A nail, it's bent in the frame.. I just need something to grip it" } } },
    { full = "Base.Crowbar", name = "crowbar", noun = "a crowbar", class = "pry", reasons = {
        { "Shed door is nailed shut", "I nailed my shed shut the first week and now I need what's inside it",
            "The shed, I need it open" },
        { "Floorboard's stuck", "There's a loose floorboard I want to lift, I think something's under it",
            "The floorboard, I told you, I just need to lift it" } } },
    { full = "Base.Shovel", name = "shovel", noun = "a shovel", class = "dig", reasons = {
        { "Need to dig a grave", "My neighbour passed in the night and I won't leave them lying out there",
            "The grave, I just need to dig it.. please" },
        { "Drain's blocked", "The ditch by my gate is clogged and the yard floods every time it rains",
            "The ditch, I only need to dig it out" } } },
    { full = "Base.Rake", name = "rake", noun = "a rake", class = "rake", reasons = {
        { "Gutter's full of leaves", "The gutter's packed with leaves and the porch roof is flooding",
            "The gutter, it's all leaves.. I need something with a reach" },
        { "Clearing the yard", "I'm trying to clear the yard so I can see anything coming",
            "The yard, I want a clear line of sight" } } },
}

Visit.wantAsks = {
    "Sorry to bug you.. could I borrow {noun} a day or two? {reason}",
    "Hate to ask but have you got {noun} you can spare? {reason}, I'll bring it right back",
    "Hey.. I'm short {noun}, any chance I could borrow yours? {reason}",
    "Don't suppose you've got {noun} lying around?! {reason}.. two days tops",
}

Visit.wantNeeds = {
    beggar = {
        { "food", "something to eat", "Haven't eaten since Tuesday", "Anything that keeps.. a can, a bit of bread, I'm not picky",
            "Food.. anything, I told you" },
        { "food", "a bite to eat", "Walked all day on nothing", "I came out of the city on foot, a can of anything and I'm gone",
            "Just something to eat, please" } },
    wounded = {
        { "bandage", "a bandage", "It won't stop bleeding", "Cut it on a fence and it won't close, a bandage or a clean rag would do",
            "A bandage.. anything to wrap it" },
        { "disinfectant", "something to clean this with", "Got it dirty", "It's gone red around the edges, I need to clean it before it gets worse",
            "To clean it.. it's going red, I told you" } },
    medical_visit = {
        { "bandage", "a bandage", "Hurt my leg on the road", "Came down hard on it two days ago and it's swelling, a bandage would help",
            "A bandage for the leg, that's all" },
        { "painkillers", "something for the pain", "The pain's wearing me down", "Been walking on it all week and I can't sleep, anything for the pain",
            "For the pain.. anything you can spare" } },
    family_in_need = {
        { "shelter", "a roof for a while", "Two kids and nowhere to go", "We lost our place last week and the kids haven't slept properly since",
            "A roof, just for a while.. the kids are tired" },
        { "shelter", "somewhere warm", "We lost our house", "The road's no place for the little ones, anywhere warm will do",
            "Somewhere warm, that's all we're asking" } },
    lodger_request = {
        { "bed", "a bed for a few nights", "Between places", "I was staying with a cousin and that fell through, I can work for my bed",
            "A bed, a few nights.. I'll earn it" },
        { "bed", "somewhere to sleep", "Can't keep sleeping rough", "I've been sleeping in cars for a week and I'm falling apart",
            "Somewhere to sleep, a few nights" } },
    weather_shelter = {
        { "shelter", "somewhere dry", "Caught out in it", "Left the camp this morning before it turned and it hasn't let up since",
            "Somewhere dry until it passes" },
        { "shelter", "a porch or a corner", "Soaked through", "I'm not asking for a bed, just a corner out of the wind",
            "A corner out of the wind, that's all" } },
    asks_help = {
        { "hands", "a pair of hands", "My friend can't be moved alone", "He's too heavy for me to lift on my own and I can't leave him there",
            "Just a pair of hands.. he's heavy" },
        { "hands", "someone to come with me", "Can't do it by myself", "There's a door jammed and my friend's behind it, it takes two",
            "Someone to come with me, it takes two" } },
    messenger = {
        { "courier", "someone to carry a note", "Somebody has to get this across", "I can't make the trip myself and it won't keep",
            "Someone to carry it, that's all" },
        { "courier", "a runner for a note", "It can't wait", "They're waiting on word from here and I've got a bad leg",
            "Just a runner.. it can't wait" } },
}

Visit.wantReplies = {
    exact = { "That's the one!.. thank you, two days at most, honest to God",
        "Perfect, that's exactly what I needed.. you'll have it back before you know it",
        "Oh bless you.. {noun}, just what I was after, two days" },
    other = { "Not what I had in mind but it'll do.. thanks, two days at most",
        "That's not {noun}.. but I can make it work, I'll bring it back",
        "Huh.. close enough, I'll manage with this, thank you" },
    wrong = { "That's no use to me.. I need {noun}, not that",
        "What am I supposed to do with that?! I asked for {noun}",
        "Nah.. can't do a thing with that, have you got {noun}?" },
    settled = { "Fine.. fine, I'll take it, better than going home with nothing",
        "Ugh, alright.. it'll have to do" },
    annoyed = { "Why do you keep asking?! It's just {noun}.. have you got it or not",
        "I told you twice already.. {noun}, can you spare it or can't you?",
        "Look I already said.. {noun}, that's all it is" },
}

Visit.wantStats = { asked = 0, whatAsked = 0, lentExact = 0, lentOther = 0, declined = 0 }

function Visit.wantQaLine()
    local stats = Visit.wantStats
    return "[ALIFE-QA] DoorWant: asked=" .. tostring(stats.asked) .. " whatAsked=" .. tostring(stats.whatAsked)
        .. " lentExact=" .. tostring(stats.lentExact) .. " lentOther=" .. tostring(stats.lentOther)
        .. " declined=" .. tostring(stats.declined)
end

function Visit.seedOf(text)
    local seed = 7
    for index = 1, #text do seed = (seed * 31 + string.byte(text, index)) % 2147483629 end
    return seed
end

function Visit.wantFor(event, id)
    if event ~= "neighbour_borrow" and Visit.wantNeeds[event] == nil then return nil end
    local seed = Visit.seedOf(tostring(id))
    if event == "neighbour_borrow" then
        local tool = Visit.wantTools[1 + seed % #Visit.wantTools]
        local reason = tool.reasons[1 + math.floor(seed / #Visit.wantTools) % #tool.reasons]
        return { fullType = tool.full, name = tool.name, noun = tool.noun, class = tool.class, reason = reason[1],
            why = reason[2], again = reason[3], ask = 1 + math.floor(seed / 97) % #Visit.wantAsks, seed = seed, whatAsked = 0 }
    end
    local list = Visit.wantNeeds[event]
    if list == nil then return nil end
    local need = list[1 + seed % #list]
    return { name = need[1], noun = need[2], reason = need[3], why = need[4], again = need[5], seed = seed, whatAsked = 0 }
end

function Visit.hasWant(pending)
    if type(pending) ~= "table" then return false end
    return type(pending.want) == "table" or pending.event == "neighbour_borrow" or Visit.wantNeeds[pending.event] ~= nil
end

function Visit.wantOf(pending)
    if type(pending) ~= "table" then return nil end
    if type(pending.want) == "table" then return pending.want end
    local made = Visit.wantFor(pending.event, pending.id)
    if made == nil then return nil end
    pending.want = made
    ProjectALife.SafehouseDirector.dirty()
    return made
end

function Visit.wantFill(want, text)
    return (string.gsub(text, "{noun}", function() return tostring(want.noun) end))
end

function Visit.wantRequest(pending)
    local want = pending.event == "neighbour_borrow" and Visit.wantOf(pending) or nil
    if want == nil or want.fullType == nil then return nil end
    if want.spoken ~= true then
        want.spoken = true
        Visit.wantStats.asked = Visit.wantStats.asked + 1
    end
    local text = Visit.wantAsks[want.ask] or Visit.wantAsks[1]
    text = string.gsub(text, "{reason}", function() return tostring(want.reason) end)
    return Visit.wantFill(want, text)
end

function Visit.wantAnswer(pending)
    local want = Visit.wantOf(pending)
    if want == nil then return "I just need a hand, that's all" end
    want.whatAsked = (tonumber(want.whatAsked) or 0) + 1
    Visit.wantStats.whatAsked = Visit.wantStats.whatAsked + 1
    ProjectALife.SafehouseDirector.dirty()
    local asked = want.whatAsked
    if asked == 1 then return Visit.wantFill(want, "I need {noun}.. " .. tostring(want.why)) end
    if asked == 2 then return Visit.wantFill(want, tostring(want.again)) end
    local pool = Visit.wantReplies.annoyed
    return Visit.wantFill(want, pool[1 + ((tonumber(want.seed) or 0) + asked) % #pool])
end

function Visit.wantLine(kind, want)
    local pool = Visit.wantReplies[kind]
    local step = (tonumber(want.seed) or 0) + (tonumber(want.whatAsked) or 0) + (tonumber(want.wrong) or 0)
    return Visit.wantFill(want, pool[1 + step % #pool])
end

function Visit.wantTier(want, full)
    if type(want) ~= "table" or want.class == nil then return "exact" end
    local class = Visit.toolClassOf[full]
    if full == want.fullType or (class ~= nil and class == want.class) then return "exact" end
    local works = Visit.toolWorks[want.class]
    if class ~= nil and type(works) == "table" and works[class] == true then return "other" end
    return "wrong"
end

function Visit.lendable(item, full)
    local director = ProjectALife.SafehouseDirector
    if director.ask(item, "isEquipped") == true then return false end
    return director.ask(item, "getDisplayCategory") == "Tool" or (full ~= nil and Visit.toolClassOf[full] ~= nil)
end

function Visit.rankTools(pending, rows)
    local want = Visit.wantOf(pending)
    for _, row in ipairs(rows) do
        row.wanted = want ~= nil and want.class ~= nil and Visit.wantTier(want, row.fullType) == "exact"
    end
    table.sort(rows, function(a, b)
        if a.wanted ~= b.wanted then return a.wanted == true end
        if a.name ~= b.name then return a.name < b.name end
        return a.itemId < b.itemId
    end)
end

function Visit.pickedTool(player, listener, pending, gift)
    local key = pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))
    local saved, now = Visit.gifts[key], Visit.millis()
    if type(gift) ~= "table" or type(gift.token) ~= "string" or #gift.token > 256 or type(gift.itemId) ~= "number"
            or gift.itemId ~= gift.itemId or gift.itemId % 1 ~= 0 or saved == nil or saved.kind ~= "LEND_TOOL"
            or gift.token ~= saved.token or now == nil or saved.untilMs <= now or saved.uid ~= listener.record.uid
            or saved.generation ~= listener.record.generation then return nil, "gift_selection_required" end
    local listed
    for _, row in ipairs(saved.entries) do if row.id == gift.itemId then listed = row; break end end
    if listed == nil then return nil, "gift_item_changed" end
    for _, fresh in ipairs(Visit.giftEntries(player, "LEND_TOOL")) do
        if fresh.id == gift.itemId then
            if fresh.item ~= listed.item or fresh.container ~= listed.container then return nil, "gift_item_changed" end
            return fresh, key
        end
    end
    return nil, "gift_item_changed"
end

function Visit.lend(player, listener, pending, house, gift)
    if pending.event ~= "neighbour_borrow" then return false, "lend_unavailable" end
    local director = ProjectALife.SafehouseDirector
    local destination = Visit.inventoryOf(listener)
    if destination == nil then return false, "inventory_unavailable" end
    local robbery = ProjectALife.ModuleRobbery
    if robbery == nil or type(robbery.removeItem) ~= "function" then return false, "inventory_api_unavailable" end
    if gift == nil then
        local shown, prompt = Visit.giftPicker(player, listener, pending, house, "LEND_TOOL")
        if not shown then return false, prompt end
        local reachable, closedWhy = Visit.openPeer(player, listener, house)
        if not reachable then
            Visit.gifts[pending.id .. ":" .. tostring(director.playerKey(player))] = nil
            return false, closedWhy
        end
        return true, prompt
    end
    local reachable, closedWhy = Visit.openPeer(player, listener, house)
    if not reachable then return false, closedWhy end
    local entry, key = Visit.pickedTool(player, listener, pending, gift)
    if entry == nil then return false, key end
    local want = Visit.wantOf(pending)
    local tier = Visit.wantTier(want, entry.fullType)
    if tier == "wrong" then
        want.wrong = (tonumber(want.wrong) or 0) + 1
        Visit.gifts[key] = nil
        if want.wrong < 3 then
            want.last = "declined"
            Visit.wantStats.declined = Visit.wantStats.declined + 1
            director.dirty()
            return true, Visit.wantLine("wrong", want)
        end
        tier = "settled"
    end
    local moved, movedWhy = robbery.removeItem({ item = entry.item, container = entry.container, source = "player" },
        destination, listener.shell)
    if not moved then
        if movedWhy == "rollback_failed" then Visit.leave(pending, "give_transfer_uncertain", nil, director.hours()) end
        return false, movedWhy == "rollback_failed" and movedWhy or "transfer_refused"
    end
    Visit.gifts[key] = nil
    local now = director.hours()
    house.returns = type(house.returns) == "table" and house.returns or {}
    while #house.returns >= 4 do table.remove(house.returns, 1) end
    house.returns[#house.returns + 1] = { fullType = entry.fullType, name = entry.name, faction = pending.faction,
        by = director.playerKey(player), atHours = now + 48 }
    Visit.leave(pending, "tool_lent", director.playerKey(player), now)
    if want == nil then return true, "Thanks, two days at most, honest to God" end
    want.last = tier
    if tier == "exact" then Visit.wantStats.lentExact = Visit.wantStats.lentExact + 1
    else Visit.wantStats.lentOther = Visit.wantStats.lentOther + 1 end
    return true, Visit.wantLine(tier, want)
end

function Visit.doorNote(uid, intent)
    if intent ~= "DOOR_LEND" then return false end
    local pending = Visit.live(uid)
    local want = pending ~= nil and type(pending.want) == "table" and pending.want or nil
    if want == nil or want.last == nil then return false end
    if want.last == "other" then return true, "trade", false end
    if want.last == "exact" then return true, "door_kind", false end
    return true, nil, want.last == "declined"
end

function Visit.handGuns(player, listener, pending)
    if pending.event ~= "law_guns" then return false, "guns_unavailable" end
    local director = ProjectALife.SafehouseDirector
    local destination = Visit.inventoryOf(listener)
    if destination == nil then return false, "inventory_unavailable" end
    local taken = 0
    for _, getter in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local item = director.ask(player, getter)
        if item ~= nil and type(instanceof) == "function" and instanceof(item, "HandWeapon")
                and director.ask(item, "isRanged") == true then
            local container = director.ask(item, "getContainer") or director.ask(player, "getInventory")
            if type(player.removeFromHands) == "function" then pcall(player.removeFromHands, player, item) end
            if ProjectALife.ModuleRobbery.removeItem({ item = item, container = container, source = "player" }, destination, listener.shell) then
                taken = taken + 1
            end
        end
    end
    Visit.leave(pending, taken > 0 and "guns_handed" or "no_guns_in_sight", director.playerKey(player), director.hours())
    if taken > 0 then return true, "Thanks, these go back to the station" end
    return true, "Nothing in your hands - good, that's all we wanted"
end

function Visit.pay(player, listener, pending, house)
    local director = ProjectALife.SafehouseDirector
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    local rule = row ~= nil and type(row.racket) == "table" and row.racket or nil
    if rule == nil then return false, "payment_not_requested" end
    local destination = nil
    if listener.shell ~= nil and type(listener.shell.getInventory) == "function" then
        local ok, value = pcall(listener.shell.getInventory, listener.shell)
        if ok then destination = value end
    end
    local entries = Visit.tradeEntries(player)
    table.sort(entries, function(a, b) return a.value < b.value end)
    local need = math.floor(tonumber(rule.items) or 3)
    if pending.haggleWon == true then need = math.max(1, need - 1) end
    if #entries < need then return false, "racket_not_enough" end
    if destination == nil then return false, "inventory_unavailable" end
    local robbery, paid = ProjectALife.ModuleRobbery, 0
    for index = 1, need do
        local entry = entries[index]
        local moved = robbery.removeItem({ item = entry.item, container = entry.container, source = "player" }, destination, listener.shell)
        if moved then paid = paid + 1 end
    end
    local now, by = director.hours(), director.playerKey(player)
    if paid < need then
        Visit.leave(pending, "racket_partial", by, now)
        return true, "That ain't what we agreed on - we'll be back"
    end
    house.paid = type(house.paid) == "table" and house.paid or {}
    house.paid[pending.faction] = now + (tonumber(rule.paidDays) or 7) * 24
    Visit.leave(pending, "racket_paid", by, now)
    return true, "That settles what you owe us for now"
end

function Visit.bluff(player, pending, house)
    local director = ProjectALife.SafehouseDirector
    if pending.event ~= "racket" then return false, "bluff_unavailable" end
    local stand = Visit.standFor(house, pending)
    local near = 0
    for _, resident in ipairs(Visit.nearResidents(house, stand)) do
        local point = Visit.position(resident)
        if point ~= nil and stand ~= nil and (point.x - stand.x)^2 + (point.y - stand.y)^2 <= 100 then near = near + 1 end
    end
    local armed = false
    local item = director.ask(player, "getPrimaryHandItem")
    if item ~= nil and type(instanceof) == "function" and instanceof(item, "HandWeapon")
            and director.ask(item, "isRanged") == true then armed = true end
    local now, by = director.hours(), director.playerKey(player)
    if near >= 2 or armed then
        Visit.leave(pending, "racket_backed_down", by, now)
        return true, "Easy, easy - no need for that, we're going"
    end
    Visit.ladderUp(house, pending, "racket_refused")
    Visit.leave(pending, "racket_refused", by, now)
    return true, "Nope, wrong answer, see ya"
end

function Visit.arrived(house, pending, point, now)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    if row == nil then return end
    if tonumber(row.decideSeconds) ~= nil then
        local millis = Visit.millis()
        pending.decideUntilMs = millis ~= nil and millis + row.decideSeconds * 1000 or nil
        local count = tonumber(pending.chasers) or 0
        local spawn = pending.spawn or point
        local dx, dy = spawn.x - point.x, spawn.y - point.y
        local length = math.sqrt(dx * dx + dy * dy)
        if count > 0 and length > 0 then
            Visit.spawnZombies(point.x + dx / length * 14, point.y + dy / length * 14, point.z or 0, count)
        end
    end
    if tonumber(row.lureMinutes) ~= nil then pending.lureAtHours = now + row.lureMinutes / 60 end
end

function Visit.zombieSquare(x, y, z, radius)
    local door = ProjectALife.SafehouseDoor
    for ring = 0, radius do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local square = door.square(x + dx, y + dy, z)
                    if square ~= nil and door.verdict(square, { x = x + dx, y = y + dy }) then return x + dx, y + dy end
                end
            end
        end
    end
    return nil
end

function Visit.spawnZombies(x, y, z, count, exact)
    if type(isClient) == "function" and isClient() == true then return 0 end
    if exact ~= true then
        local px, py = Visit.zombieSquare(math.floor(x), math.floor(y), math.floor(z or 0), 3)
        if px == nil then return 0 end
        x, y = px, py
    end
    if type(Visit.adapters) == "table" and type(Visit.adapters.spawnZombies) == "function" then
        return Visit.adapters.spawnZombies(x, y, z, count)
    end
    if type(addZombiesInOutfit) ~= "function" or count < 1 then return 0 end
    local ok, list = pcall(addZombiesInOutfit, math.floor(x), math.floor(y), math.floor(z or 0), count, nil, 50)
    if not ok then return 0 end
    if type(list) == "userdata" or type(list) == "table" then
        local size = type(list.size) == "function" and tonumber(list:size()) or nil
        if size ~= nil then return size end
    end
    return count
end

function Visit.eventTick(house, pending, shell, point, now)
    local row = ProjectALife.SafehouseEvents.row(pending.event)
    if row == nil or (pending.state ~= "at_door" and pending.state ~= "talking") then return false end
    if pending.decideUntilMs ~= nil then
        local millis = Visit.millis()
        if millis ~= nil and millis >= pending.decideUntilMs then
            pending.decideUntilMs = nil
            Visit.leave(pending, "refused_chased", nil, now)
            return true
        end
    end
    if pending.event == "law_fake" and pending.exposedAtHours ~= nil and now >= pending.exposedAtHours + 0.05 then
        Visit.turn(house, pending, now)
        return true
    end
    if pending.event == "law_fake" and Visit.facingOpen(house, pending) then
        Visit.turn(house, pending, now)
        return true
    end
    if pending.lureAtHours ~= nil and now >= pending.lureAtHours and pending.lured ~= true then
        pending.lured = true
        local stand = Visit.standFor(house, pending) or point
        Visit.spawnZombies(stand.x + 6, stand.y + 6, stand.z or 0, tonumber(pending.lureCount) or 1)
        if type(addSound) == "function" then pcall(addSound, nil, math.floor(stand.x), math.floor(stand.y), math.floor(stand.z or 0), 30, 40) end
        ProjectALife.SafehouseDirector.dirty()
    end
    return false
end

function Visit.doorOpen(house)
    local door = house.door
    if type(door) ~= "table" or door.mode ~= "door" then return false end
    local object = ProjectALife.SafehouseDoor.entryDoor(door)
    if object == nil or type(object.IsOpen) ~= "function" then return false end
    local ok, open = pcall(object.IsOpen, object)
    return ok and open == true
end

function Visit.facingOpen(house, pending)
    local door = Visit.doorFor(house, pending)
    if type(door) == "table" and door.mode == "window" then return false end
    return Visit.doorOpen(house)
end

function Visit.lateOutcome(pending)
    if pending.completedOutcome ~= nil then return pending.completedOutcome, pending.completedBy end
    if pending.treated == true then return "treated_wounded", pending.treatedBy end
    return "ignored", nil
end

function Visit.leave(pending, outcome, by, now)
    if pending.completedOutcome ~= nil and (outcome == "refused" or outcome == "rude_no" or outcome == "ignored") then
        outcome, by = pending.completedOutcome, pending.completedBy
    end
    Visit.holdRelease(pending)
    for key, quote in pairs(Visit.quotes) do if quote.pendingId == pending.id then Visit.quotes[key] = nil end end
    pending.by, pending.outcome = by, outcome
    pending.state, pending.untilHours = "leaves", now + 2
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                memory.visit.untilHours, memory.visit.renewedHours = pending.untilHours, now
                memory.visit.leaving = true
                if pending.spawn ~= nil then memory.stanceAnchor = pending.spawn end
            end
        end)
    end
    ProjectALife.SafehouseDirector.dirty()
end

function Visit.priceBounds(player, record)
    local personal = ProjectALife.PersonalRep
    local factor = personal ~= nil and type(personal.priceFactor) == "function" and personal.priceFactor(player) or 1
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and record ~= nil and type(opinion.priceFactor) == "function" then
        factor = factor * opinion.priceFactor(record, player)
    end
    return 0.8 * factor, 1.2 * factor
end

function Visit.tradeEntries(character)
    local robbery, entries = ProjectALife.ModuleRobbery, {}
    if character == nil or type(character.getInventory) ~= "function" or robbery == nil
            or type(robbery.gatherItems) ~= "function" then return entries end
    for _, entry in ipairs(robbery.gatherItems(character, { playerOnly = true, limit = 256 })) do
        local item = entry.item
        if entry.source == "player" and type(entry.value) == "number" and entry.value > 0
                and item ~= nil and type(item.getID) == "function" and type(item.getFullType) == "function"
                and type(item.getDisplayName) == "function" and type(item.getCategory) == "function" then
            local ok, category = pcall(item.getCategory, item)
            local safe = ok and category ~= "Container"
            if safe and category == "Food" then
                local matched, food = pcall(ProjectALife.TalkSupplies.matches, item, "ASK_FOOD")
                safe = matched and food == true
            end
            local named, name = pcall(item.getDisplayName, item)
            local typed, full = pcall(item.getFullType, item)
            local identified, id = pcall(item.getID, item)
            if safe and named and type(name) == "string" and #name > 0 and typed and type(full) == "string"
                    and #full > 0 and identified and type(id) == "number" then
                entry.name, entry.fullType, entry.id = string.sub(name, 1, 160), full, id
                entries[#entries + 1] = entry
            end
        end
    end
    return entries
end

function Visit.tradeView(player, uid)
    local listener, pending = Visit.doorPeer(player, uid)
    if listener == nil or pending.event ~= "trader" or pending.trade ~= nil then return nil end
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    local quote = Visit.quotes[pending.id .. ":" .. tostring(key)]
    local now = Visit.millis()
    if quote == nil or now == nil or now >= quote.untilMs or quote.generation ~= listener.record.generation then return nil end
    return { token = quote.token, give = quote.cost.name, receive = quote.offer.name, stock = quote.stock, untilMs = quote.untilMs }
end

function Visit.stockEntries(listener)
    local entries = Visit.tradeEntries(listener.shell)
    local saved = listener.record.memory and listener.record.memory.traderStock
    if saved == nil then return entries end
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator == nil or type(hydrator.traderSnapshot) ~= "function" then return nil, "trader_stock_unavailable" end
    local stock = hydrator.traderSnapshot(listener.record)
    if stock == nil then return nil, "trader_stock_unavailable" end
    for _, slot in ipairs(stock.slots) do
        if slot.state == "reserved" or slot.state == "uncertain" then return nil, "trader_stock_pending" end
    end
    local offers = {}
    for _, entry in ipairs(entries) do
        local read, data = false, nil
        if type(entry.item.getModData) == "function" then read, data = pcall(entry.item.getModData, entry.item) end
        local slot = read and type(data) == "table" and stock.slots[data.ProjectALifeTraderSlot] or nil
        if slot ~= nil and data.ProjectALifeTraderUID == listener.record.uid and slot.state == "available"
                and entry.fullType == slot.type then
            entry.stockSlot = slot.id
            offers[#offers + 1] = entry
        end
    end
    return offers, stock.revision
end

function Visit.tradeQuote(player, listener, pending, house)
    if pending.event ~= "trader" or pending.trade ~= nil then return false, "trade_unavailable" end
    local plan = Visit.plan(pending)
    if plan == nil then return false, "visit_plan_unsupported" end
    if plan.scam then return true, "You pay first, and nobody's searching me" end
    if pending.stockReason ~= nil then return false, "trader_stock_unavailable" end
    local open, why = Visit.openPeer(player, listener, house)
    if not open then return false, why end
    local now, count = Visit.millis(), 0
    if now == nil then return false, "trade_clock_unavailable" end
    for key, quote in pairs(Visit.quotes) do
        if now >= quote.untilMs or Visit.live(quote.uid) == nil then Visit.quotes[key] = nil else count = count + 1 end
    end
    if count >= 128 then return false, "trade_quotes_busy" end
    local stock, stockRevision = Visit.stockEntries(listener)
    if stock == nil then return false, stockRevision end
    local costs = Visit.tradeEntries(player)
    if #stock < 3 then return false, "trade_stock_insufficient" end
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.dealRefusal) == "function" and opinion.dealRefusal(listener.record, player) then
        return false, "trade_refused_opinion"
    end
    local names, offer, cost = {}, nil, nil
    local low, high = Visit.priceBounds(player, listener.record)
    for i = 1, math.min(6, #stock) do
        local entry = stock[i]
        names[#names + 1] = entry.name
        if offer == nil then
            for _, payment in ipairs(costs) do
                if payment.value >= entry.value * low and payment.value <= entry.value * high then
                    offer, cost = entry, payment; break
                end
            end
        end
    end
    if offer == nil then return false, "no_fair_trade_cost" end
    local sequence = pending.tradeQuoteSequence == nil and 0 or pending.tradeQuoteSequence
    if type(sequence) ~= "number" or sequence ~= sequence or sequence < 0 or sequence % 1 ~= 0 then return false, "trade_quote_identity_unavailable" end
    local nextId = sequence + 1
    if nextId ~= nextId or nextId < 1 or nextId >= 9007199254740992 then return false, "trade_quote_identity_unavailable" end
    pending.tradeQuoteSequence = nextId
    local key = ProjectALife.SafehouseDirector.playerKey(player)
    local token = pending.id .. ":quote:" .. string.format("%.0f", nextId)
    Visit.quotes[pending.id .. ":" .. tostring(key)] = { token = token, pendingId = pending.id, uid = listener.record.uid,
        generation = listener.record.generation, untilMs = now + 60000, stock = names, cost = cost, offer = offer, stockRevision = stockRevision }
    ProjectALife.SafehouseDirector.dirty()
    return true, "On offer: " .. table.concat(names, ", ") .. ". Give one " .. cost.name .. " for one " .. offer.name .. ". Confirm this exact trade to swap."
end

function Visit.tradeConfirm(player, listener, pending, house, token)
    if pending.event ~= "trader" or pending.trade ~= nil then return false, "trade_unavailable" end
    local plan = Visit.plan(pending)
    if plan == nil then return false, "visit_plan_unsupported" end
    if plan.scam then return false, "trade_scam_unavailable" end
    local open, why = Visit.openPeer(player, listener, house)
    if not open then return false, why end
    local key = pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))
    local quote, now = Visit.quotes[key], Visit.millis()
    if type(token) ~= "string" or #token > 256 or quote == nil or quote.token ~= token or now == nil
            or now >= quote.untilMs or quote.generation ~= listener.record.generation then return false, "trade_quote_required" end
    local cost, offer
    for _, entry in ipairs(Visit.tradeEntries(player)) do
        if entry.item == quote.cost.item and entry.container == quote.cost.container then cost = entry; break end
    end
    local stock, stockRevision = Visit.stockEntries(listener)
    if stock == nil then return false, stockRevision end
    for _, entry in ipairs(stock) do
        if entry.item == quote.offer.item and entry.container == quote.offer.container then offer = entry; break end
    end
    Visit.quotes[key] = nil
    if stockRevision ~= quote.stockRevision or cost == nil or offer == nil or cost.fullType ~= quote.cost.fullType or offer.fullType ~= quote.offer.fullType
            or cost.id ~= quote.cost.id or offer.id ~= quote.offer.id or cost.name ~= quote.cost.name or offer.name ~= quote.offer.name
            or cost.value ~= quote.cost.value or offer.value ~= quote.offer.value
            or cost.value < offer.value * select(1, Visit.priceBounds(player, listener.record))
            or cost.value > offer.value * select(2, Visit.priceBounds(player, listener.record)) then return false, "trade_inventory_changed" end
    if type(player.getInventory) ~= "function" or type(listener.shell.getInventory) ~= "function" then return false, "inventory_api_unavailable" end
    local got, playerInventory = pcall(player.getInventory, player)
    local read, npcInventory = pcall(listener.shell.getInventory, listener.shell)
    if not got or not read or playerInventory == nil or npcInventory == nil then return false, "inventory_unavailable" end
    local robbery = ProjectALife.ModuleRobbery
    if robbery == nil or type(robbery.exchangeItems) ~= "function" then return false, "trade_service_unavailable" end
    local hydrator = ProjectALife.ProfileHydrator
    if stockRevision ~= nil and (hydrator == nil or type(hydrator.reserveTraderStock) ~= "function"
            or type(hydrator.completeTraderStock) ~= "function") then return false, "trader_stock_unavailable" end
    cost.destination, cost.owner = npcInventory, listener.shell
    offer.destination, offer.owner = playerInventory, player
    pending.trade = { state = "preparing", token = token, by = ProjectALife.SafehouseDirector.playerKey(player),
        uid = listener.record.uid, generation = listener.record.generation, costId = cost.id, offerId = offer.id,
        costType = cost.fullType, offerType = offer.fullType }
    ProjectALife.SafehouseDirector.dirty()
    if stockRevision ~= nil then
        local called, reserved, slot = pcall(hydrator.reserveTraderStock, listener.shell, listener.record, offer.item, token)
        if not called or reserved ~= true then
            pending.trade = nil
            ProjectALife.SafehouseDirector.dirty()
            return false, called and slot or "trader_stock_write_failed"
        end
        pending.trade.stockSlot = slot
        ProjectALife.SafehouseDirector.dirty()
    end
    local called, exchanged, reason = pcall(robbery.exchangeItems, cost, offer)
    if not called or reason == "rollback_failed" then
        pending.trade.state, pending.trade.reason = "uncertain", called and reason or "exchange_error"
        Visit.leave(pending, "trade_transfer_uncertain", nil, ProjectALife.SafehouseDirector.hours())
        return false, "trade_transfer_uncertain"
    end
    if stockRevision ~= nil then
        local calledStock, completed = pcall(hydrator.completeTraderStock, listener.record.uid, listener.record.generation, token, exchanged == true)
        if not calledStock or completed ~= true then
            pending.trade.state, pending.trade.reason = "uncertain", "trader_stock_write_failed"
            Visit.leave(pending, "trade_transfer_uncertain", nil, ProjectALife.SafehouseDirector.hours())
            return false, "trade_transfer_uncertain"
        end
    end
    if exchanged ~= true then pending.trade = nil; ProjectALife.SafehouseDirector.dirty(); return false, reason or "transfer_refused" end
    pending.trade.state, pending.trade.atHours = "committed", ProjectALife.SafehouseDirector.hours()
    Visit.leave(pending, "fair_trade", pending.trade.by, pending.trade.atHours)
    return true, "Done. You gave one " .. cost.name .. " and received one " .. offer.name .. "."
end

function Visit.choose(player, uid, intent, quoteToken, gift)
    local listener, pending, house = Visit.doorPeer(player, uid)
    if listener == nil then return false, "not_door_peer" end
    local allowed, why = Visit.authorized(house)
    if not allowed then return false, why end
    if type(pending.trade) == "table" and pending.trade.state == "preparing" then return false, "trade_pending" end
    if not ProjectALife.SafehouseDirector.isPlayer(player) or type(player.isDead) ~= "function" or player:isDead() then
        return false, "player_unavailable"
    end
    local hostile = Visit.hostile(listener.record, player)
    if hostile ~= false then
        Visit.settle(house, pending, Visit.guestState(pending) and "guest_turned" or "cancelled", nil,
            ProjectALife.SafehouseDirector.hours())
        return false, hostile == true and "visitor_hostile" or "visit_relation_unavailable"
    end
    if Visit.questionIds[intent] then
        if not Visit.choices(uid, player)[intent] then return false, "invalid_choice" end
        if not Visit.guestState(pending) then
            local ready, reason = Visit.scriptReady(pending)
            if not ready then return false, reason end
            local talking, whyTalk = Visit.talking(pending)
            if not talking then return false, whyTalk end
        end
        return true, Visit.questionLine(pending, intent, Visit.observations(listener.record, player))
    end
    if Visit.guestState(pending) then return Visit.guestChoice(player, pending, house, intent, listener) end
    if Visit.door().isThemed(intent) then return Visit.themed(player, uid, pending, house, intent) end
    if intent ~= "DOOR_LEAVE" and intent ~= "DOOR_LEAVE_RUDE" then
        local ready, reason = Visit.scriptReady(pending)
        if not ready then return false, reason end
    end
    if intent == "DOOR_WEAPONS_DOWN" then
        local plan = Visit.plan(pending)
        if plan ~= nil and plan.betray then return true, "Nah, I keep it on me, old habit" end
        local before, changed = {}, {}
        for _, actorUid in ipairs(pending.uids or {}) do
            local actor = Visit.record(actorUid)
            local saved = actor and actor.memory and actor.memory.visit
            before[actorUid] = type(saved) == "table" and {
                weaponsDown = saved.weaponsDown, weaponKind = saved.weaponKind, weaponName = saved.weaponName } or {}
            local kind, name = Visit.weaponState(Visit.shell(actorUid))
            local wrote = Visit.write(actorUid, function(memory)
                if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                    memory.visit.weaponsDown, memory.visit.weaponKind, memory.visit.weaponName = true, kind, name
                end
            end)
            if not wrote then
                for _, changedUid in ipairs(changed) do
                    Visit.write(changedUid, function(memory)
                        if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                            local savedBefore = before[changedUid]
                            memory.visit.weaponsDown, memory.visit.weaponKind, memory.visit.weaponName =
                                savedBefore.weaponsDown, savedBefore.weaponKind, savedBefore.weaponName
                        end
                    end)
                end
                return false, "actor_write_refused"
            end
            changed[#changed + 1] = actorUid
        end
        for _, actorUid in ipairs(changed) do
            local shell, fence, animations = Visit.shell(actorUid), ProjectALife.AIFence, ProjectALife.Animations
            if shell ~= nil and fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(shell)
                    and animations ~= nil and type(animations.refreshWeapon) == "function" then
                animations.refreshWeapon(shell, false)
            end
        end
        local _, _, words = Visit.weaponsReply(Visit.record(uid))
        return true, words
    end
    if intent == "DOOR_WHO" then
        if pending.event == "law_stay_inside" then
            local talking, reason = Visit.talking(pending)
            if not talking then return false, reason end
            pending.completedOutcome, pending.completedBy = "law_notice", ProjectALife.SafehouseDirector.playerKey(player)
            ProjectALife.SafehouseDirector.dirty()
            return true, "Not safe out here, keep that door shut... anything you need to ask before we go?"
        end
        if pending.event == "law_census" then
            local talking, reason = Visit.talking(pending)
            if not talking then return false, reason end
            pending.question = "census"
            return true, "Checking the houses - how many of you home? Anybody bit?"
        end
        if pending.event == "beggar" or pending.event == "preacher" then
            local plan = Visit.plan(pending)
            if plan == nil then return false, "visit_plan_unsupported" end
            if plan.counting then return Visit.headcountTell(player, listener, pending) end
        end
        local done, doneText = Visit.whoDone(player, pending, house)
        if done ~= nil then return done, doneText end
        local talking, reason = Visit.talking(pending)
        if not talking then return false, reason end
        local line = Visit.whoLine(pending)
        if line ~= nil then
            pending.asked = (tonumber(pending.asked) or 0) + 1
            return true, line
        end
        if pending.event == "sleep_one_night" then
            local plan = Visit.plan(pending)
            if plan ~= nil and plan.betray then return true, "Need a roof for the night, which room's yours so I stay out of it?" end
            return true, "Just need a roof tonight, I'll be gone by seven"
        end
        return true, pending.event == "trader" and "Got stuff to swap, we can do it right here at the door"
            or "Just after some food, I can wait out here"
    end
    if intent == "DOOR_INVITE" then return Visit.invite(player, pending, house) end
    if intent == "DOOR_TREAT" then return Visit.give(player, listener, pending, house, gift) end
    if intent == "DOOR_PAY" then return Visit.pay(player, listener, pending, house) end
    if intent == "DOOR_BLUFF" then return Visit.bluff(player, pending, house) end
    if intent == "DOOR_JOB" then return Visit.takeJob(player, pending, house) end
    if intent == "DOOR_LEND" then return Visit.lend(player, listener, pending, house, gift) end
    if intent == "DOOR_HAND_GUNS" then return Visit.handGuns(player, listener, pending) end
    if intent == "DOOR_TREAT_ME" then return Visit.treatMe(player, listener, pending) end
    if intent == "DOOR_CALLSIGN" then
        if string.sub(tostring(pending.event), 1, 4) ~= "law_" then return false, "callsign_unavailable" end
        if pending.event == "law_fake" then return true, "Uh... unit seven - just open the door, will ya?" end
        return true, "Unit 4-Adam, county sheriff - won't take long"
    end
    if intent == "DOOR_GIVE" then return Visit.give(player, listener, pending, house, gift) end
    if intent == "DOOR_SEARCH" then return Visit.search(player, listener, pending, house) end
    if intent == "DOOR_TRADE" then return Visit.tradeQuote(player, listener, pending, house) end
    if intent == "DOOR_TRADE_CONFIRM" then return Visit.tradeConfirm(player, listener, pending, house, quoteToken) end
    if intent == "DOOR_TRADE_CANCEL" then
        if pending.event ~= "trader" then return false, "trade_unavailable" end
        Visit.quotes[pending.id .. ":" .. tostring(ProjectALife.SafehouseDirector.playerKey(player))] = nil
        return true, "No swap, fine, I'll wait here"
    end
    if intent == "DOOR_CENSUS_CLEAR" or intent == "DOOR_CENSUS_BITTEN" then
        return Visit.census(player, pending, house, intent == "DOOR_CENSUS_BITTEN")
    end
    if intent ~= "DOOR_LEAVE" and intent ~= "DOOR_LEAVE_RUDE" then return false, "invalid_choice" end
    if pending.event == "racket" then Visit.ladderUp(house, pending, "racket_refused") end
    local rude = intent == "DOOR_LEAVE_RUDE"
    local farewell = Visit.door().leaveLine(pending.event, rude)
    Visit.leave(pending, rude and "rude_no" or "refused",
        ProjectALife.SafehouseDirector.playerKey(player), ProjectALife.SafehouseDirector.hours())
    return true, farewell or "Fine, I'm going"
end

function Visit.releasePerson(house, pending, outcome, by, now, reason)
    local visitors = ProjectALife.VisitorDirector
    if visitors == nil or type(visitors.release) ~= "function" or type(visitors.owns) ~= "function" or not visitors.owns(pending) then return 0 end
    local ok, written = pcall(visitors.release, pending, outcome, pending.uids,
        { house = house, by = by, now = now, reason = reason })
    if not ok then
        print("[ALIFE-SAFEHOUSE] visitor release failed: " .. tostring(written))
        return 0
    end
    return written
end

Visit.leaveTuning = { stuckMs = 25000, maxMs = 240000, moveTiles = 1.5, arriveTiles = 3 }
Visit.leavers = {}

function Visit.retireLeavers(pending)
    local visitors = ProjectALife.VisitorDirector
    local service = ProjectALife.SpawnService
    local retired = 0
    for _, uid in ipairs(pending.uids or {}) do
        local done = false
        if visitors ~= nil and type(visitors.retire) == "function" then
            done = visitors.retire(uid) == true
        elseif service ~= nil and type(service.retire) == "function" then
            done = service.retire(uid, "visitor_done") ~= false
        end
        if done then retired = retired + 1 end
    end
    return retired
end

function Visit.leaveWatch(house, pending, point, now)
    local ms = Visit.millis()
    if ms == nil or point == nil then return false end
    local tuning = Visit.leaveTuning
    local row = Visit.leavers[pending.id]
    if row == nil then
        row = { x = point.x, y = point.y, z = point.z, ms = ms, startMs = ms }
        Visit.leavers[pending.id] = row
        return false
    end
    local why = nil
    local spawn = pending.spawn
    if type(spawn) == "table" and tonumber(spawn.x) ~= nil and tonumber(spawn.y) ~= nil
            and (point.x - spawn.x) ^ 2 + (point.y - spawn.y) ^ 2 <= tuning.arriveTiles ^ 2 then
        why = "leave_arrived"
    elseif ms - row.startMs >= tuning.maxMs then
        why = "leave_timeout"
    elseif (point.x - row.x) ^ 2 + (point.y - row.y) ^ 2 > tuning.moveTiles ^ 2 or math.abs(point.z - row.z) > 0.5 then
        row.x, row.y, row.z, row.ms = point.x, point.y, point.z, ms
    elseif ms - row.ms >= tuning.stuckMs then
        why = "leave_stuck"
    end
    if why == nil then return false end
    Visit.metrics.leaveRetired = (Visit.metrics.leaveRetired or 0) + 1
    Visit.settle(house, pending, pending.outcome or "ignored", pending.by, now, why)
    Visit.retireLeavers(pending)
    return true
end

function Visit.settle(house, pending, outcome, by, now, reason)
    if type(isClient) == "function" and isClient() == true then return false end
    if pending.resolved == true then return false end
    local director = ProjectALife.SafehouseDirector
    if type(house) ~= "table" or director.store().houses[house.key] ~= house then return false end
    local listed = false
    for _, row in ipairs(house.pending or {}) do if row == pending then listed = true end end
    if not listed then return false end
    if outcome == "cancelled" and pending.completedOutcome ~= nil then
        outcome, by = pending.completedOutcome, pending.completedBy
    end
    Visit.holdRelease(pending)
    local previousState = pending.state
    pending.resolved, pending.state = true, "outcome"
    if pending.uids == nil and Visit.refunded[outcome] == true then director.refund(house, pending) end
    director.remember(house, { id = pending.id, event = pending.event, faction = pending.faction,
        outcome = outcome, reason = reason or outcome, previousState = previousState, by = by, hours = now, census = pending.census, trade = pending.trade,
        uids = pending.uids, generations = pending.generations, spawn = pending.spawn, spot = pending.spot,
        persons = type(pending.person) == "table" and type(pending.person.ids) == "table"
            and table.concat(pending.person.ids, ",") or nil })
    director.removePending(house, pending)
    director.noteVisitEnd(house, pending, now)
    director.dirty()
    Visit.releasePerson(house, pending, outcome, by, now, reason)
    for _, uid in ipairs(pending.uids or {}) do Visit.clear(uid, pending.id, pending.generations and pending.generations[uid]) end
    Visit.seen[pending] = nil
    Visit.leavers[pending.id] = nil
    if Visit.knocks[pending.id] ~= nil then
        Visit.knocks[pending.id] = nil
        Visit.metrics.knockStates = math.max(0, Visit.metrics.knockStates - 1)
    end
    local cues = ProjectALife.InteractionCues
    if cues ~= nil and type(cues.last) == "table" then
        for _, memory in pairs(cues.last) do
            for _, uid in ipairs(pending.uids or {}) do memory[uid] = nil end
        end
    end
    if outcome == "rude_no" or outcome == "gave_food" or outcome == "census_answer" or outcome == "fair_trade"
            or outcome == "let_sleep" or outcome == "treated_wounded" or outcome == "sheltered_chased"
            or outcome == "neighbour_watch" then
        local hosted = nil
        if tonumber(pending.insideAt) ~= nil and tonumber(now) ~= nil then
            hosted = { hosted = math.max(0, now - pending.insideAt) }
        end
        local accepted, why = director.deed(outcome, by, pending.faction, Visit.leadUid(pending), pending.id, hosted)
        pending.deedAccepted, pending.deedReason = accepted == true, why
        house.history[1].deedAccepted, house.history[1].deedReason = pending.deedAccepted, why
        director.dirty()
    end
    return true
end

Visit.knockKinds = {
    beggar = "knock_soft", trader = "knock_soft", neighbour = "knock_soft", returning_things = "knock_soft",
    preacher = "knock_soft", medic_rounds = "knock_soft", messenger = "knock_soft", neighbour_borrow = "knock_soft",
    sleep_one_night = "knock_soft", radio_rumour = "knock_soft",
    law_stay_inside = "knock_series", law_census = "knock_series", law_guns = "knock_series", law_fake = "knock_series",
    chased = "knock_panic", wounded = "knock_panic", asks_help = "knock_panic", panic_knock = "knock_panic",
    family_in_need = "knock_soft", returning_guest = "knock_soft", lodger_request = "knock_soft",
    weather_shelter = "knock_soft", medical_visit = "knock_soft",
    racket = "knock_aggressive", drunk = "knock_aggressive",
}
Visit.knockEscalate = { law_fake = "knock_aggressive" }
Visit.knockAlt = { knock_series = "knock_soft", knock_panic = "knock_aggressive", garage_try = "knock_aggressive" }
Visit.knockTuning = { max = 4, minMs = 30000, spreadMs = 15001, gapMs = 1500, retryMs = 5000, tries = 120,
    seriesPercent = 25, cap = 64 }
Visit.knocks = {}
Visit.cueBusyUntilMs = 0
Visit.metrics = { knocks = 0, knockFar = 0, knockBusy = 0, knockOff = 0, knockStates = 0,
    adminSpawned = 0, adminAtDoor = 0, adminKnock = 0, adminTalkable = 0, adminLast = "-" }

function Visit.knockState(pending)
    local state = Visit.knocks[pending.id]
    if state == nil then
        if Visit.metrics.knockStates >= Visit.knockTuning.cap then Visit.knocks, Visit.metrics.knockStates = {}, 0 end
        state = { count = 0, tries = 0, nextMs = 0, open = false }
        Visit.knocks[pending.id] = state
        Visit.metrics.knockStates = Visit.metrics.knockStates + 1
    end
    return state
end

function Visit.knockKind(house, pending, again)
    local doors, door = ProjectALife.SafehouseDoor, Visit.doorFor(house, pending)
    if type(door) == "table" and door.mode == "door" then
        local object = doors.entryDoor(door)
        if object ~= nil and doors.isGarage(object) then return "garage_try" end
    end
    local kind = Visit.knockKinds[pending.event]
    if kind == nil then
        local row = ProjectALife.SafehouseEvents.row(pending.event)
        if row ~= nil and row.hostileOk == true then kind = "knock_aggressive" else kind = "knock_soft" end
    end
    if again and Visit.knockEscalate[pending.event] ~= nil then kind = Visit.knockEscalate[pending.event] end
    if kind == "knock_soft" and ProjectALife.SafehouseDirector.rand(100) < Visit.knockTuning.seriesPercent then
        kind = "knock_series"
    end
    return kind
end

function Visit.doorSquare(house, pending)
    local doors, door = ProjectALife.SafehouseDoor, Visit.doorFor(house, pending)
    if type(door) == "table" and door.mode == "door" then
        local object = doors.entryDoor(door)
        local square = object ~= nil and doors.ask(object, "getSquare") or nil
        if square ~= nil then return square end
    end
    if type(door) == "table" and tonumber(door.sx) ~= nil and tonumber(door.sy) ~= nil then
        return doors.square(door.sx, door.sy, tonumber(door.z) or 0)
    end
    local stand = Visit.standFor(house, pending)
    if type(stand) == "table" and tonumber(stand.x) ~= nil and tonumber(stand.y) ~= nil then
        return doors.square(stand.x, stand.y, tonumber(stand.z) or 0)
    end
    return nil
end

function Visit.knockCue(house, pending, again)
    local director, cues = ProjectALife.SafehouseDirector, ProjectALife.InteractionCues
    if director.settings.knockSounds ~= true then
        Visit.metrics.knockOff = Visit.metrics.knockOff + 1
        return false, "off"
    end
    if cues == nil or type(cues.pick) ~= "function" or type(cues.playAt) ~= "function" then return false, "no_cues" end
    local millis, state = Visit.millis(), Visit.knockState(pending)
    if millis == nil then return false, "clock_unavailable" end
    state.tries = state.tries + 1
    local tuning = Visit.knockTuning
    if millis < Visit.cueBusyUntilMs then
        Visit.metrics.knockBusy = Visit.metrics.knockBusy + 1
        state.nextMs = Visit.cueBusyUntilMs + tuning.gapMs
        return false, "busy"
    end
    local square = Visit.doorSquare(house, pending)
    if square == nil then state.nextMs = millis + tuning.retryMs; return false, "no_square" end
    local key = pending.uids ~= nil and Visit.leadUid(pending) or pending.id
    local id, seconds = cues.pick(Visit.knockKind(house, pending, again), key)
    if id ~= nil and id == state.last then
        local kind = cues.sounds[id] ~= nil and cues.sounds[id].kind or nil
        if kind ~= nil and Visit.knockAlt[kind] ~= nil then id, seconds = cues.pick(Visit.knockAlt[kind], key) end
    end
    if id == nil then return false, "no_cue" end
    local ok, why = cues.playAt(square, id)
    if not ok then
        if why == "far" then Visit.metrics.knockFar = Visit.metrics.knockFar + 1 end
        state.nextMs = millis + tuning.retryMs
        return false, why
    end
    local x, y, z = cues.pointOf(square)
    state.last, state.count = id, state.count + 1
    state.at = { id = id, x = (x or 0) + 0.5, y = (y or 0) + 0.5, z = z or 0 }
    local span = math.floor((tonumber(seconds) or 0) * 1000)
    Visit.cueBusyUntilMs = millis + span
    state.nextMs = millis + math.max(tuning.minMs + ProjectALife.SafehouseDirector.rand(tuning.spreadMs), span + tuning.gapMs)
    Visit.metrics.knocks = Visit.metrics.knocks + 1
    return true, id
end

function Visit.heard(state, player)
    local at, cues = state ~= nil and state.at or nil, ProjectALife.InteractionCues
    if at == nil or cues == nil or type(cues.pointOf) ~= "function" then return false end
    local px, py, pz = cues.pointOf(player)
    if px == nil then return false end
    local reach = cues.hearTiles(at.id)
    return (px - at.x) ^ 2 + (py - at.y) ^ 2 <= reach * reach and math.abs(pz - at.z) <= 4
end

function Visit.knockArrive(house, pending)
    local state = Visit.knockState(pending)
    state.open = Visit.facingOpen(house, pending)
    if state.open then return false, "door_open" end
    return Visit.knockCue(house, pending, false)
end

function Visit.doorWatch(house, pending)
    local state = Visit.knocks[pending.id]
    if state == nil then return false end
    local open = Visit.facingOpen(house, pending)
    local was = state.open
    state.open = open
    if open and not was and (pending.state == "at_door" or pending.state == "talking" or pending.state == "invited") then
        state.nextMs = math.huge
        return true
    end
    return false
end

function Visit.knockTick(house, pending)
    local state = Visit.knocks[pending.id]
    local tuning = Visit.knockTuning
    if state == nil or pending.state ~= "at_door" or state.open or state.count >= tuning.max or state.tries >= tuning.tries then
        return false
    end
    local millis = Visit.millis()
    if millis == nil or millis < state.nextMs then return false end
    return Visit.knockCue(house, pending, state.count > 0)
end

function Visit.nearDoor(house, pending, player)
    local point, door = Visit.position(player), Visit.doorFor(house, pending)
    if point == nil or type(door) ~= "table" or tonumber(door.ix) == nil or tonumber(door.iy) == nil then return false end
    return point.x >= house.x1 and point.x < house.x2 and point.y >= house.y1 and point.y < house.y2
        and math.floor(point.z) == math.floor(tonumber(door.z) or 0)
        and (point.x - door.ix) ^ 2 + (point.y - door.iy) ^ 2 <= 64
end

function Visit.nearUid(uid, player)
    local pending, house = Visit.live(uid)
    return pending ~= nil and Visit.nearDoor(house, pending, player) == true
end

function Visit.knock(house, pending, stand, recipient)
    if type(isClient) == "function" and isClient() == true then return end
    if stand == nil then return end
    local server = type(isServer) == "function" and isServer() == true
    local lead = Visit.leadUid(pending)
    if lead == nil then return end
    for _, player in ipairs(Visit.nearResidents(house, stand)) do
        if (recipient == nil or recipient == player) and ProjectALife.SafehouseDirector.isPlayer(player) and type(player.isDead) == "function" and not player:isDead()
                and type(player.isAsleep) == "function" and player:isAsleep() == false
                and type(player.getUsername) == "function" then
            local args = { house = house.key, pendingId = pending.id, uid = lead,
                generation = pending.generations[lead], row = pending.event,
                username = player:getUsername(), x = stand.x, y = stand.y, z = stand.z,
                untilHours = pending.untilHours }
            if recipient == nil and Visit.heard(Visit.knocks[pending.id], player) then args.cued = true end
            local door = Visit.doorFor(house, pending)
            if type(door) == "table" and (door.mode == "door" or door.mode == "window") then
                args.door = { sx = door.sx, sy = door.sy, ix = door.ix, iy = door.iy,
                    z = door.z, x1 = house.x1, y1 = house.y1, x2 = house.x2, y2 = house.y2 }
                if door.mode == "window" then args.door.kind = "window" end
            end
            if server then
                if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", "safehouseKnock", args) end
            else
                local client = ProjectALife.SafehouseClient
                if client ~= nil and type(client.knock) == "function" then client.knock(args, player) end
            end
        end
    end
end

function Visit.syncDoor(player)
    local director = ProjectALife.SafehouseDirector
    if type(isClient) == "function" and isClient() == true then return false end
    if not director.isPlayer(player) or type(player.isDead) ~= "function" or player:isDead()
            or type(player.isAsleep) ~= "function" or player:isAsleep() then return false end
    local key, point, now = director.playerKey(player), Visit.position(player), director.hours()
    if key == nil or point == nil then return false end
    for _, house in pairs(director.store().houses) do
        local stand = director.standOf(house)
        if Visit.authorized(house) and house.residents[key] ~= nil and stand ~= nil
                and point.x >= house.x1 and point.x < house.x2 and point.y >= house.y1 and point.y < house.y2
                and math.abs(point.z - stand.z) <= 1 and (point.x - stand.x)^2 + (point.y - stand.y)^2 <= 3600 then
            for _, pending in ipairs(house.pending or {}) do
                if pending.resolved ~= true and pending.knocked == true
                        and (pending.state == "at_door" or pending.state == "talking")
                        and now < (tonumber(pending.untilHours) or -math.huge) then
                    local uid = type(pending.uids) == "table" and Visit.leadUid(pending) or nil
                    local actor, shell = uid and Visit.record(uid), uid and Visit.shell(uid)
                    local stamp = actor and type(actor.memory) == "table" and actor.memory.visit or nil
                    local outside = Visit.position(shell)
                    local at = Visit.standFor(house, pending)
                    local identified, identity = false, nil
                    if shell ~= nil and type(shell.getModData) == "function" then identified, identity = pcall(shell.getModData, shell) end
                    if actor ~= nil and actor.lifecycle == "active" and type(pending.generations) == "table"
                            and pending.generations[uid] == actor.generation and type(stamp) == "table"
                            and stamp.house == house.key and stamp.pendingId == pending.id and stamp.generation == actor.generation
                            and now <= (tonumber(stamp.untilHours) or -math.huge)
                            and now <= (tonumber(stamp.renewedHours) or -math.huge) + 3
                            and identified and type(identity) == "table" and identity.ProjectALifeUID == uid
                            and identity.ProjectALifeGeneration == actor.generation
                            and outside ~= nil and at ~= nil and math.abs(outside.z - at.z) <= 1
                            and (outside.x - at.x)^2 + (outside.y - at.y)^2 <= 2.25
                            and type(shell.isDead) == "function" and shell:isDead() == false
                            and Visit.hostile(actor, player) == false then
                        Visit.knock(house, pending, at, player)
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Visit.announce(house, pending, shell, event, reply, fallback)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    if speech == nil or type(speech.say) ~= "function" then return end
    local actor = Visit.record(Visit.leadUid(pending))
    if actor == nil or pending.generations[actor.uid] ~= actor.generation then return end
    local target
    for _, player in ipairs(Visit.nearResidents(house, Visit.standFor(house, pending))) do
        if ProjectALife.SafehouseDirector.playerKey(player) == pending.target
                and type(player.isAsleep) == "function" and player:isAsleep() == false then target = player; break end
    end
    local facts = { [pending.event] = true }
    if pending.outcome == "ignored" then facts.ignored = true end
    local near = function(player) return Visit.nearDoor(house, pending, player) end
    if data ~= nil and type(data.load) == "function" and type(speech.bark) == "function" then
        data.load()
        local records
        if reply then records = type(data.replies) == "table" and data.replies[event] or nil end
        if reply and records == nil then records = {} end
        local text = speech.bark(actor, shell, event, { player = target, records = records, context = { facts = facts },
            scope = "visitor", near = near })
        if text ~= nil then return end
    end
    speech.say(shell, fallback, { earshot = 60, scope = "visitor", near = near })
end

function Visit.adminLine(house, pending, cued, cueWhy)
    if pending.direct ~= true and pending.debug ~= true then return nil end
    local uid = type(pending.uids) == "table" and Visit.leadUid(pending) or nil
    local talkable, talkWhy, menu = false, "no_resident", 0
    for _, resident in ipairs(ProjectALife.SafehouseDirector.onlineResidents(house)) do
        if uid ~= nil and Visit.peer(resident, uid, false) ~= nil then
            talkable, talkWhy = true, nil
            for _ in pairs(Visit.choices(uid, resident)) do menu = menu + 1 end
            break
        end
        talkWhy = uid ~= nil and Visit.peerWhy[uid] or "no_uid"
    end
    local metrics = Visit.metrics
    metrics.adminAtDoor = metrics.adminAtDoor + 1
    if pending.knocked == true then metrics.adminKnock = metrics.adminKnock + 1 end
    if talkable then metrics.adminTalkable = metrics.adminTalkable + 1 end
    local knock = cued == true and "yes" or ("no(" .. tostring(cueWhy) .. ")")
    local talk = talkable and "yes" or ("no(" .. tostring(talkWhy) .. ")")
    local line = string.format("visitor spawned by admin: event=%s knock=%s state=%s talkable=%s menu=%d",
        tostring(pending.event), knock, tostring(pending.state), talk, menu)
    metrics.adminLast = string.format("%s/%s/knock=%s/talkable=%s", tostring(pending.event), tostring(pending.state),
        cued == true and "yes" or "no", talkable and "yes" or "no")
    print("[ALIFE-SAFEHOUSE] " .. line)
    return line
end

function Visit.tick(house, pending, now)
    if type(isClient) == "function" and isClient() == true then return 0 end
    if pending.resolved == true or pending.state == "queued" then return 0 end
    if Visit.seen[pending] ~= true and type(pending.trade) == "table" and pending.trade.state == "preparing" then
        pending.trade.state, pending.trade.reason = "uncertain", "interrupted_exchange"
        Visit.settle(house, pending, "trade_transfer_uncertain", nil, now); return 1
    end
    if Visit.seen[pending] ~= true and pending.state ~= "talking" then
        local outcome = pending.state == "leaves" and pending.outcome or "cancelled"
        Visit.settle(house, pending, outcome, pending.by, now, "unrestored_visit"); return 1
    end
    for _, uid in ipairs(pending.uids or {}) do
        local actor = Visit.record(uid)
        if actor == nil or actor.lifecycle ~= "active" or pending.generations[uid] ~= actor.generation then
            Visit.settle(house, pending, pending.state == "leaves" and pending.outcome or "cancelled", pending.by, now, "actor_inactive_or_generation_changed"); return 1
        end
    end
    local shell = Visit.liveShell(pending)
    local point = Visit.position(shell)
    if point == nil or type(shell.isDead) ~= "function" or shell:isDead()
            or type(shell.getSquare) ~= "function" or shell:getSquare() == nil then
        Visit.settle(house, pending, pending.state == "leaves" and pending.outcome or "cancelled", pending.by, now, "shell_dead_missing_or_unloaded"); return 1
    end
    if pending.waitingSpots == nil and (pending.state == "approach" or pending.state == "at_door" or pending.state == "talking") then
        local spots = Visit.waitingSpots(house, pending, pending.uids)
        if spots == nil then Visit.settle(house, pending, "cancelled", nil, now, "waiting_positions_unavailable"); return 1 end
        for _, uid in ipairs(pending.uids) do
            Visit.write(uid, function(memory)
                memory.stance, memory.stanceAnchor = "visit", spots[uid]
                if pending.spot.fx ~= nil and pending.spot.fy ~= nil then
                    memory.stanceFace = { x = pending.spot.fx, y = pending.spot.fy }
                end
            end)
        end
        ProjectALife.SafehouseDirector.dirty()
    end
    local stand = Visit.standFor(house, pending)
    local d2 = stand and (point.x - stand.x)^2 + (point.y - stand.y)^2 or math.huge
    if pending.state == "leaves" then
        if d2 >= 3600 or now >= pending.untilHours then Visit.settle(house, pending, pending.outcome or "ignored", pending.by, now)
        else Visit.leaveWatch(house, pending, point, now) end
        return 1
    end
    if Visit.seen[pending] == true then Visit.doorWatch(house, pending) end
    if Visit.guestState(pending) and Visit.seen[pending] == true then return Visit.guestTick(house, pending, point, now) end
    if Visit.seen[pending] ~= true then
        Visit.seen[pending] = true
        Visit.atDoor(pending)
    end
    local residents = Visit.nearResidents(house, stand)
    if pending.state == "approach" and #residents == 0 then
        Visit.settle(house, pending, "cancelled", nil, now, "no_near_resident")
        return 1
    end
    for _, resident in ipairs(residents) do
        for _, uid in ipairs(pending.uids or {}) do
            if Visit.hostile(Visit.record(uid), resident) ~= false then
                Visit.settle(house, pending, "cancelled", nil, now, "hostile_or_relation_unavailable")
                return 1
            end
        end
    end
    if pending.state == "talking" then
        local millis = Visit.millis()
        if #residents == 0 or millis == nil or millis >= (tonumber(pending.talkUntilMs) or -math.huge) then
            Visit.atDoor(pending)
        end
    end
    if Visit.eventTick(house, pending, shell, point, now) then return 1 end
    if now >= pending.untilHours and Visit.sessionOpen(pending) then
        pending.untilHours = now + 1 / 3
        ProjectALife.SafehouseDirector.dirty()
    end
    if now >= pending.untilHours then
        local late, lateBy = Visit.lateOutcome(pending)
        Visit.leave(pending, late, lateBy, now)
        Visit.announce(house, pending, shell, "DOOR_LEAVE_REPLY", true, "Right, I'm out of here")
        return 1
    end
    if pending.event == "radio_rumour" and pending.radioDone ~= true and pending.state == "approach" and d2 <= 196 then
        Visit.radioNews(house, pending)
    end
    if pending.state == "approach" and d2 <= 2.25 then
        pending.state, pending.untilHours = "at_door", now + 2
        Visit.arrived(house, pending, point, now)
        if pending.knocked ~= true then
            pending.knocked = true
            local cued, cueWhy = Visit.knockArrive(house, pending)
            Visit.knock(house, pending, stand)
            Visit.announce(house, pending, shell, "DOOR_KNOCK", false, "Anyone home?")
            Visit.adminLine(house, pending, cued, cueWhy)
        end
        ProjectALife.SafehouseDirector.dirty()
    end
    Visit.holdTick(house, pending)
    Visit.knockTick(house, pending)
    for _, uid in ipairs(pending.uids or {}) do
        Visit.write(uid, function(memory)
            if type(memory.visit) == "table" and memory.visit.pendingId == pending.id then
                memory.visit.untilHours, memory.visit.renewedHours = pending.untilHours, now
            end
        end)
    end
    return 1
end

return Visit
