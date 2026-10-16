require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Fear/ALifeSurvival"
require "ProjectALife/Fear/ALifeModuleWithdraw"
require "ProjectALife/Fear/ALifeFirstDays"
require "ProjectALife/Talk/ALifeDialogueRoles"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Fear = {
    id = "fear",
    settings = {
        days = 7,
        lingering = 0.5,
        level = 2,
        levelScale = { 0.6, 1, 1.5 },

        scanTiles = 6,
        scanCacheMs = 1000,
        roleCacheMs = 30000,

        afraidAt = 4,
        steadyBelow = 2.5,
        crowdExponent = 1.4,
        lossWeight = 2,
        healthWeight = 2,
        unarmedScale = 1.5,
        squadAfraidBonus = 1.5,

        farTiles = 8,
        ignoreMs = 1000,
        combatCheckMs = 1000,
        avoidHoldMs = 300,

        fleeTiles = 18,
        minFleeTiles = 6,
        fleeStep = 2,
        squadReuseTiles = 8,
        squadPruneMs = 60000,
        bearingTiles = 6,
        fleeTimeoutMs = 14000,
        sprintMs = 3000,
        postureMs = 15000,
        squadBearingMs = 10000,
        squadAfraidMs = 12000,

        safeMs = 5000,
        minFlightMs = 30000,
        flightMaxMs = 120000,
        stallTiles = 2,
        stallCheckMs = 2500,
        cornerTiles = 4,
        graspTiles = 2,
        stallLegs = 2,
        braveMs = 10000,
        sprinterTiles = 6,
        sprintTiles = 4,

        shoutMs = 20000,
    },
    classCourage = { civilian = 1, rescue = 0.8, worker = 0.6 },
    inferredClass = "worker",
    blocClass = {
        family = "civilian", civilian = "civilian", worker = "worker", rescue = "rescue",
        law = "police", military = "military", elite = "military",
        prison = "criminal", crime = "criminal", club = "criminal", gang = "criminal", raider = "criminal",
    },
    hardened = { veteran = true, predator = true },
    exemptConduct = { sniper = true, ambusher = true },

    actors = {},
    squads = {},
    roles = {},
    scans = {},
    combatChecks = {},
    prunedAtMs = 0,
    metrics = { asked = 0, avoided = 0, overlooked = 0, afraid = 0, steadied = 0, fled = 0, fallbacks = 0,
        cornered = 0, safe = 0, ineligible = 0, ineligibleBy = {} },
}
ProjectALife.ModuleFear = Fear

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function gameDay()
    local day = 0
    pcall(function() day = getGameTime():getNightsSurvived() end)
    return tonumber(day) or 0
end

local function distanceBetween(a, b)
    local ok, result = pcall(function()
        local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
        return math.sqrt(dx * dx + dy * dy)
    end)
    if ok then return result end
    return nil
end

function Fear.configure(options)
    options = type(options) == "table" and options or {}
    local settings = Fear.settings
    if options.days ~= nil then
        settings.days = math.max(0, math.min(30, math.floor(tonumber(options.days) or settings.days)))
    end
    if options.lingering ~= nil then
        local percent = math.max(0, math.min(100, math.floor(tonumber(options.lingering) or settings.lingering * 100)))
        settings.lingering = percent / 100
    end
    if options.level ~= nil then
        settings.level = math.max(1, math.min(3, math.floor(tonumber(options.level) or settings.level)))
    end
    return settings
end

function Fear.reset()
    Fear.actors, Fear.squads, Fear.roles, Fear.scans, Fear.combatChecks = {}, {}, {}, {}, {}
    Fear.prunedAtMs = 0
    Fear.metrics = { asked = 0, avoided = 0, overlooked = 0, afraid = 0, steadied = 0, fled = 0, fallbacks = 0,
        cornered = 0, safe = 0, ineligible = 0, ineligibleBy = {} }
end

function Fear.forgetActor(uid)
    if uid == nil then return end
    Fear.actors[uid] = nil
    Fear.roles[uid] = nil
    Fear.scans[uid] = nil
    Fear.combatChecks[uid] = nil
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.forget) == "function" then first.forget(uid) end
end

function Fear.combatCheckDue(uid, now)
    if uid == nil then return false end
    now = tonumber(now) or 0
    if now < (Fear.combatChecks[uid] or 0) then return false end
    Fear.combatChecks[uid] = now + Fear.settings.combatCheckMs
    return true
end

function Fear.courageOf(class)
    return tonumber(Fear.classCourage[tostring(class or "")]) or 0
end

function Fear.classOfBloc(bloc)
    return Fear.blocClass[tostring(bloc or "")]
end

function Fear.dayScale(day, days, lingering)
    local settings = Fear.settings
    day = math.max(0, tonumber(day) or 0)
    days = tonumber(days) or settings.days
    lingering = math.max(0, math.min(1, tonumber(lingering) or settings.lingering))
    if days <= 0 then return lingering end
    local settled = math.min(1, day / days)
    return 1 - (1 - lingering) * settled
end

function Fear.courageFor(class, forced)
    local courage = Fear.courageOf(class)
    if courage <= 0 and forced == true then return 1 end
    return courage
end

function Fear.eligible(facts)
    facts = type(facts) == "table" and facts or {}
    local settings = Fear.settings
    if Fear.dayScale(facts.day, facts.days, facts.lingering) <= 0 then return false, "past_days" end
    if Fear.exemptConduct[tostring(facts.conduct or "")] == true then return false, "conduct" end
    if facts.holdingPost == true then return false, "holding_post" end
    if facts.ordered == true then return false, "ordered" end
    if Fear.courageFor(facts.class, facts.forced) <= 0 then return false, "category" end
    if Fear.hardened[tostring(facts.temperament or "")] == true then return false, "hardened" end
    return true, "category"
end

function Fear.score(inputs)
    inputs = type(inputs) == "table" and inputs or {}
    local settings = Fear.settings
    local weight = math.max(0, tonumber(inputs.crowd) or 0)
    local value = weight > 0 and weight ^ settings.crowdExponent or 0
    if inputs.loss == true then value = value + settings.lossWeight end
    local health = math.max(0, math.min(1, tonumber(inputs.health) or 1))
    value = value + (1 - health) * settings.healthWeight
    if inputs.armed ~= true then value = value * settings.unarmedScale end
    if inputs.squadAfraid == true then value = value + settings.squadAfraidBonus end
    local level = math.floor(tonumber(inputs.level) or settings.level)
    local scale = settings.levelScale[level] or 1
    local courage = tonumber(inputs.courage) or 1
    return value * scale * courage
end

function Fear.step(previous, score)
    local settings = Fear.settings
    score = tonumber(score) or 0
    if previous == "afraid" then
        if score < settings.steadyBelow then return "steady" end
        return "afraid"
    end
    if score >= settings.afraidAt then return "afraid" end
    return "steady"
end

function Fear.paceFor(chaser, nearest)
    local settings = Fear.settings
    chaser, nearest = tonumber(chaser), tonumber(nearest)
    if chaser ~= nil and chaser <= settings.sprintTiles then return "sprint" end
    if nearest ~= nil and nearest <= settings.graspTiles then return "sprint" end
    if chaser ~= nil or nearest ~= nil then return "run" end
    return "walk"
end

function Fear.flightOver(record, now)
    local flight = type(record) == "table" and record.flight or nil
    if flight == nil then return false, nil end
    now = tonumber(now) or 0
    local settings = Fear.settings
    local running = now - (tonumber(flight.startedAtMs) or 0)
    if running >= settings.flightMaxMs then return true, "worn_out" end
    if running < settings.minFlightMs then return false, nil end
    if now - (tonumber(flight.seenAtMs) or 0) >= settings.safeMs then return true, "safe" end
    return false, nil
end

function Fear.noteLeg(record, now, x, y, nearest)
    local settings = Fear.settings
    now = tonumber(now) or 0
    if now < (tonumber(record.braveUntilMs) or 0) then return false, "brave" end
    local flight = record.flight
    local judged = true
    if flight == nil then
        flight = { startedAtMs = now, seenAtMs = now, legs = 0, stalls = 0 }
        record.flight = flight
    elseif now - (tonumber(flight.lastAtMs) or 0) < settings.stallCheckMs then
        judged = false
    elseif x ~= nil and y ~= nil and flight.lastX ~= nil then
        local dx, dy = x - flight.lastX, y - flight.lastY
        local pressed = tonumber(nearest) ~= nil and tonumber(nearest) <= settings.cornerTiles
        if pressed and dx * dx + dy * dy < settings.stallTiles * settings.stallTiles then
            flight.stalls = flight.stalls + 1
        else
            flight.stalls = 0
        end
    end
    if flight.stalls >= settings.stallLegs then
        record.braveUntilMs = now + settings.braveMs
        record.flight = nil
        return false, "cornered"
    end
    if judged then flight.lastX, flight.lastY, flight.lastAtMs = x, y, now end
    flight.legs = flight.legs + 1
    return true, flight.legs == 1 and "start" or "leg"
end

function Fear.recordFor(uid)
    local record = Fear.actors[uid]
    if record == nil then
        record = { state = "steady", braveUntilMs = 0, shoutAtMs = -1e12 }
        Fear.actors[uid] = record
    end
    return record
end

function Fear.blocOf(factionId)
    local catalog = ProjectALife.Catalog
    if factionId == nil or catalog == nil or type(catalog.faction) ~= "function" then return nil end
    local ok, faction = pcall(catalog.faction, factionId)
    if not ok or type(faction) ~= "table" then return nil end
    local layers = ProjectALife.RelationLayers
    if layers ~= nil and type(layers.blocOf) == "function" then
        local found, bloc = pcall(layers.blocOf, faction)
        if found and bloc ~= nil then return bloc end
    end
    return type(faction.relations) == "table" and faction.relations.bloc or nil
end

function Fear.memberClass(actor)
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(catalog.npc) == "function" and actor.profileId ~= nil then
        local ok, profile = pcall(catalog.npc, actor.profileId)
        local general = ok and type(profile) == "table" and type(profile.general) == "table" and profile.general or nil
        local own = general ~= nil and general.npcClass or nil
        if type(own) == "string" and own ~= "" then return own end
    end
    local class = Fear.classOfBloc(Fear.blocOf(actor.factionId))
    if class ~= nil then return class end
    return Fear.inferClass(actor)
end

function Fear.inferClass(actor)
    local inferred = Fear.inferredClass
    if inferred == nil or type(actor) ~= "table" then return nil end
    if Registry.override(actor, "gunFear") ~= "on" then return nil end
    return inferred
end

function Fear.roleOf(actor, now, day)
    local cached = Fear.roles[actor.uid]
    if cached ~= nil and now < cached.untilMs then return cached end
    local roles = ProjectALife.DialogueRoles
    local value = { untilMs = now + Fear.settings.roleCacheMs, class = Fear.memberClass(actor) }
    if roles ~= nil and type(roles.describe) == "function" then
        local ok, who = pcall(roles.describe, actor, day)
        if ok and type(who) == "table" then value.temperament = who.temperament end
    end
    Fear.roles[actor.uid] = value
    return value
end

local function ordered(actor, now)
    local decisions = ProjectALife.DecisionLoop
    local orders = decisions ~= nil and decisions.orders or nil
    local order = type(orders) == "table" and orders[actor.uid] or nil
    if type(order) ~= "table" then return false end
    if order.generation ~= actor.generation or order.source == "leader" then return false end
    return order.untilMs == nil or now < order.untilMs
end

local function holdingPost(actor)
    local panic = ProjectALife.ModulePanic
    if panic == nil or type(panic.holdingPost) ~= "function" then return false end
    local ok, holding = pcall(panic.holdingPost, actor)
    return ok and holding == true
end

function Fear.eligibleActor(actor, now)
    if type(actor) ~= "table" or actor.uid == nil then return false, "no_actor" end
    local day = gameDay()
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if Fear.dayScale(day) <= 0 then return false, "past_days" end
    local role = Fear.roleOf(actor, now, day)
    return Fear.eligible({
        day = day,
        days = Fear.settings.days,
        lingering = Fear.settings.lingering,
        conduct = memory.conduct,
        holdingPost = holdingPost(actor),
        ordered = ordered(actor, now),
        temperament = role.temperament,
        class = role.class,
        forced = Registry.override(actor, Fear.id) == "on",
    })
end

function Fear.chasedBy(zombie, uid)
    if type(zombie.getModData) ~= "function" then return false end
    if type(zombie.hasModData) == "function" then
        local okHas, has = pcall(zombie.hasModData, zombie)
        if not okHas or has ~= true then return false end
    end
    local ok, data = pcall(zombie.getModData, zombie)
    local target = ok and type(data) == "table" and data.ALifeChaseTargetId or nil
    if type(target) ~= "string" then return false end
    local prefix = tostring(uid) .. ":"
    return string.sub(target, 1, #prefix) == prefix
end

function Fear.targets(shell, zombie, uid)
    if type(zombie.getTarget) == "function" then
        local ok, target = pcall(zombie.getTarget, zombie)
        if ok and target == shell then return true end
    end
    return Fear.chasedBy(zombie, uid)
end

function Fear.closing(shell, zombie, uid)
    if Fear.chasedBy(zombie, uid) then return true end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.closingSpeed) == "function" then
        local ok, speed = pcall(perception.closingSpeed, shell, zombie)
        return ok and (tonumber(speed) or 0) > 0
    end
    return false
end

local function sprinter(zombie)
    if type(zombie.getSpeedType) ~= "function" then return false end
    local ok, speed = pcall(zombie.getSpeedType, zombie)
    return ok and speed == 1
end

local function replica(perception, body, now)
    if perception == nil or type(perception.knownReplica) ~= "function" then return false end
    local ok, known = pcall(perception.knownReplica, body, now)
    return ok and known == true
end

local function living(body)
    if type(body.isDead) ~= "function" then return true end
    local ok, dead = pcall(body.isDead, body)
    return ok and dead ~= true
end

function Fear.scan(actor, shell, now)
    local cached = Fear.scans[actor.uid]
    if cached ~= nil and now < cached.untilMs then return cached end
    local settings = Fear.settings
    local result = { weight = 0, count = 0, nearest = nil, chasers = 0, chaser = nil, body = nil,
        sprinterClose = false, untilMs = now + settings.scanCacheMs }
    local withdraw = ProjectALife.ModuleWithdraw
    if withdraw == nil or type(withdraw.crowdSquare) ~= "function" or type(getCell) ~= "function" then
        Fear.scans[actor.uid] = result
        return result
    end
    local perception = ProjectALife.Perception
    local scanned = pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local sx, sy, sz = math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ())
        local tiles = settings.scanTiles
        local seen = {}
        for dx = -tiles, tiles do
            for dy = -tiles, tiles do
                local bodies = withdraw.crowdSquare(cell, sx + dx, sy + dy, sz)
                for _, body in ipairs(bodies) do
                    if body ~= nil and body ~= shell and not seen[body] and living(body) and not withdraw.ours(body)
                            and not replica(perception, body, now) then
                        seen[body] = true
                        local span = math.sqrt(dx * dx + dy * dy)
                        local weight = math.max(0.2, 1 - span / (tiles + 1))
                        local closing = Fear.closing(shell, body, actor.uid)
                        if closing then weight = weight * 2 end
                        if closing and span <= settings.sprinterTiles and sprinter(body) then
                            result.sprinterClose = true
                        end
                        result.weight = result.weight + weight
                        result.count = result.count + 1
                        if result.nearest == nil or span < result.nearest then result.nearest = span end
                        if Fear.targets(shell, body, actor.uid) then
                            result.chasers = result.chasers + 1
                            if result.chaser == nil or span < result.chaser then
                                result.chaser, result.body = span, body
                            end
                        end
                    end
                end
            end
        end
    end)
    if scanned then Fear.scans[actor.uid] = result end
    return result
end

local function pruneSquads(now)
    if now < Fear.prunedAtMs then return end
    Fear.prunedAtMs = now + Fear.settings.squadPruneMs
    local expired = {}
    for groupId, squad in pairs(Fear.squads) do
        if now >= (squad.afraidUntilMs or 0) and now >= (squad.bearingUntilMs or 0) then expired[#expired + 1] = groupId end
    end
    for _, groupId in ipairs(expired) do Fear.squads[groupId] = nil end
end

local function squadOf(actor, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local groupId = memory.groupId
    if groupId == nil then return nil, nil end
    pruneSquads(now)
    local squad = Fear.squads[groupId]
    if squad == nil then
        squad = { afraidUntilMs = 0, bearingUntilMs = 0 }
        Fear.squads[groupId] = squad
    end
    return squad, groupId
end

local function note(actor, record, state, score, reason)
    if record.state == state then return end
    record.state = state
    if state == "afraid" then
        Fear.metrics.afraid = Fear.metrics.afraid + 1
    else
        Fear.metrics.steadied = Fear.metrics.steadied + 1
    end
    local shown = math.floor((tonumber(score) or 0) * 100 + 0.5) / 100
    print("[ALIFE-FEAR] uid=" .. tostring(actor.uid) .. " state=" .. tostring(state) .. " score=" .. tostring(shown)
        .. " reason=" .. tostring(reason) .. " day=" .. tostring(gameDay()))
end

local function shout(actor, shell, record, now)
    if now - (tonumber(record.shoutAtMs) or -1e12) < Fear.settings.shoutMs then return end
    record.shoutAtMs = now
    pcall(function()
        local voice = ProjectALife.Voice
        if voice ~= nil and type(voice.play) == "function" then
            voice.play(shell, "RETREAT", { urgent = true, context = { targetKind = "zombie", reason = "fear" } })
        end
    end)
end

local function wrapBearing(index)
    local wrapped = (index - 1) % 8
    if wrapped < 0 then wrapped = wrapped + 8 end
    return wrapped + 1
end

function Fear.awayBearing(sx, sy, tx, ty, bearings)
    local dx, dy = sx - tx, sy - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 or type(bearings) ~= "table" then return nil end
    dx, dy = dx / length, dy / length
    local best, bestDot = nil, -2
    for index = 1, #bearings do
        local dot = dx * bearings[index][1] + dy * bearings[index][2]
        if dot > bestDot then best, bestDot = index, dot end
    end
    return best
end

local function candidateBearings(withdraw, shell, threat, crowded, sx, sy)
    local candidates = {}
    if crowded and type(withdraw.crowdBearings) == "function" then
        for _, index in ipairs(withdraw.crowdBearings(shell, Fear.settings.bearingTiles)) do
            candidates[#candidates + 1] = index
            if #candidates >= 3 then break end
        end
        return candidates
    end
    local tx, ty
    if threat ~= nil then pcall(function() tx, ty = threat:getX(), threat:getY() end) end
    local away = tx ~= nil and Fear.awayBearing(sx, sy, tx, ty, withdraw.bearings) or nil
    if away ~= nil then
        candidates[1], candidates[2], candidates[3] = away, wrapBearing(away + 1), wrapBearing(away - 1)
    end
    return candidates
end

local function facesThreat(withdraw, index, sx, sy, threat)
    local tx, ty
    if threat ~= nil then pcall(function() tx, ty = threat:getX(), threat:getY() end) end
    if tx == nil then return false end
    local away = Fear.awayBearing(sx, sy, tx, ty, withdraw.bearings)
    if away == nil then return false end
    local count = #withdraw.bearings
    local turn = (index - away) % count
    if turn < 0 then turn = turn + count end
    return turn >= 3 and turn <= count - 3
end

local function fleePoint(shell, threat, squad, now, crowded, heading)
    local settings = Fear.settings
    local withdraw = ProjectALife.ModuleWithdraw
    if withdraw == nil or type(withdraw.rayOut) ~= "function" or type(getCell) ~= "function" then return nil end
    local point, chosen, fresh, sx, sy
    pcall(function()
        local cell = getCell()
        local sz
        sx, sy, sz = math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ())
        local candidates = candidateBearings(withdraw, shell, threat, crowded or threat == nil, sx, sy)
        local minimum = settings.minFleeTiles * settings.minFleeTiles
        if heading ~= nil and not facesThreat(withdraw, heading, sx, sy, threat) then
            local found = withdraw.rayOut(cell, sx, sy, sz, heading, settings.fleeTiles, settings.fleeStep)
            if found ~= nil and (found.x - sx) ^ 2 + (found.y - sy) ^ 2 >= minimum then
                point, chosen = found, heading
            end
        end
        if point == nil and squad ~= nil and squad.bearing ~= nil and now < squad.bearingUntilMs then
            local ox, oy = tonumber(squad.originX) or sx, tonumber(squad.originY) or sy
            local near = (ox - sx) ^ 2 + (oy - sy) ^ 2 <= settings.squadReuseTiles * settings.squadReuseTiles
            local agreed = false
            for _, index in ipairs(candidates) do
                if index == squad.bearing then agreed = true end
            end
            if near and agreed then
                local found = withdraw.rayOut(cell, sx, sy, sz, squad.bearing, settings.fleeTiles, settings.fleeStep)
                if found ~= nil and (found.x - sx) ^ 2 + (found.y - sy) ^ 2 >= minimum then
                    point, chosen = found, squad.bearing
                end
            end
        end
        if point == nil then
            local reach = 0
            for _, index in ipairs(candidates) do
                local found = withdraw.rayOut(cell, sx, sy, sz, index, settings.fleeTiles, settings.fleeStep)
                local length = found ~= nil and (found.x - sx) ^ 2 + (found.y - sy) ^ 2 or 0
                if length > reach then point, reach, chosen = found, length, index end
            end
            if reach < minimum then point, chosen = nil, nil end
            fresh = point ~= nil
        end
    end)
    return point, chosen, fresh, sx, sy
end

local function hurry(shell, now, pace, actor)
    local settings = Fear.settings
    if pace == "walk" then return end
    local sprintMs = settings.sprintMs
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.sprintMs) == "function" then sprintMs = first.sprintMs(actor, sprintMs) end
    pcall(function()
        local data = shell:getModData()
        if pace == "sprint" then data.ProjectALifeSprintUntilMs = now + sprintMs end
        if data.ProjectALifeDangerPosture == nil or data.ProjectALifeDangerPosture == "relaxed" then
            data.ProjectALifeDangerPosture = "alert"
        end
    end)
    pcall(function()
        local combat = ProjectALife.Combat
        if combat ~= nil and type(combat.postureUntilMs) == "table" then
            combat.postureUntilMs[shell] = now + settings.postureMs
        end
    end)
end

function Fear.flee(actor, shell, threat, context, now, squad, crowded, flight, pace)
    local settings = Fear.settings
    hurry(shell, now, pace, actor)
    local point, bearing, fresh, sx, sy
    local first = ProjectALife.FirstDays
    if first ~= nil and flight ~= nil and flight.firstDays == true and type(first.fleeDestination) == "function" then
        local ok, sheltered = pcall(first.fleeDestination, actor, shell, threat, flight, now)
        if ok then point = sheltered end
    end
    local pack = squad
    if flight ~= nil and flight.firstDays == true and first ~= nil and type(first.scatter) == "function"
            and first.scatter(actor) == true then
        pack = nil
    end
    if point == nil then
        point, bearing, fresh, sx, sy = fleePoint(shell, threat, pack, now, crowded,
            flight ~= nil and flight.bearing or nil)
    end
    local state
    if point ~= nil and type(context.startMovement) == "function" then
        local endurance = ProjectALife.Endurance
        if endurance ~= nil then pcall(endurance.beginRetreat, actor, shell, now) end
        state = context.startMovement(actor, shell, { x = point.x + 0.5, y = point.y + 0.5, z = point.z },
            "fear_flee", {
                kind = threat ~= nil and "retreat" or "movement",
                activity = "moving",
                pace = pace == "walk" and "walk" or "run",
                timeoutMs = settings.fleeTimeoutMs,
                threat = threat,
                threatKind = "zombie",
            })
        if state ~= nil then
            state.reason = "fear"
            if flight ~= nil then flight.bearing = bearing end
            if pack ~= nil and fresh then
                squad.bearing = bearing
                squad.bearingUntilMs = now + settings.squadBearingMs
                squad.originX, squad.originY = sx, sy
            end
        end
    end
    if state == nil and threat ~= nil and type(context.startRetreat) == "function" then
        Fear.metrics.fallbacks = Fear.metrics.fallbacks + 1
        state = context.startRetreat(actor, shell, threat, "zombie", now, "fear")
    end
    if state == nil then return nil end
    if state.kind ~= "retreat" and not (threat == nil and state.kind == "movement") then return nil end
    return state
end

function Fear.bitten(shell)
    local horde = ProjectALife.HordeRelations
    if horde == nil or type(horde.mouthsOn) ~= "function" then
        if type(getTimestampMs) ~= "function" or shell == nil or type(shell.getModData) ~= "function" then return false end
        local ok, data = pcall(shell.getModData, shell)
        local stamp = ok and type(data) == "table" and tonumber(data.ProjectALifeLastBiteAtMs) or nil
        return stamp ~= nil and getTimestampMs() - stamp < 1500
    end
    local ok, count = pcall(horde.mouthsOn, shell)
    return ok and (tonumber(count) or 0) > 0
end

function Fear.avoids(shell, threat, uid)
    local distance = distanceBetween(shell, threat)
    if distance == nil or distance <= Fear.settings.farTiles then return false end
    if sprinter(threat) then return false end
    if Fear.closing(shell, threat, uid) then return false end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.ignore) == "function" then
        pcall(perception.ignore, uid, threat, Fear.settings.ignoreMs)
    end
    return true
end

function Fear.overlook(actor, shell, threat, threatKind, now)
    if threatKind ~= "zombie" or threat == nil or shell == nil then return false end
    if not Registry.allows(actor, Fear.id) then return false end
    now = tonumber(now) or nowMs()
    if not Fear.eligibleActor(actor, now) then return false end
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.inTrigger) == "function" then
        local ok, alarmed = pcall(first.inTrigger, actor, shell, threat, now)
        if ok and alarmed == true then return false end
    end
    if not Fear.avoids(shell, threat, actor.uid) then return false end
    Fear.metrics.overlooked = Fear.metrics.overlooked + 1
    return true
end

function Fear.continueFlight(actor, shell, context)
    if type(actor) ~= "table" or actor.uid == nil or shell == nil or type(context) ~= "table" then return nil end
    local record = Fear.actors[actor.uid]
    if record == nil or record.flight == nil then return nil end
    if not Registry.allows(actor, Fear.id) then
        record.flight = nil
        return nil
    end
    local now = tonumber(context.now) or nowMs()
    local scan = Fear.scan(actor, shell, now)
    if scan.chasers > 0 then record.flight.seenAtMs = now end
    local over, why = Fear.flightOver(record, now)
    if over then
        record.flight = nil
        Fear.metrics.safe = Fear.metrics.safe + 1
        note(actor, record, "steady", 0, why)
        return nil
    end
    if Fear.bitten(shell) then
        Fear.metrics.cornered = Fear.metrics.cornered + 1
        return nil
    end
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.flightLeg) == "function" then
        local ok, held = pcall(first.flightLeg, actor, shell, record, scan, context, now)
        if ok and held ~= nil then return held end
    end
    local x, y
    pcall(function() x, y = shell:getX(), shell:getY() end)
    local nearest = scan.nearest
    if context.threat ~= nil then
        local gap = distanceBetween(shell, context.threat)
        if gap ~= nil and (nearest == nil or gap < nearest) then nearest = gap end
    end
    local allowed, leg = Fear.noteLeg(record, now, x, y, nearest)
    if not allowed then
        if leg == "cornered" then
            Fear.metrics.cornered = Fear.metrics.cornered + 1
            print("[ALIFE-FEAR] uid=" .. tostring(actor.uid) .. " cornered: fighting")
        end
        return nil
    end
    local threat = scan.body or context.threat
    local fled = Fear.flee(actor, shell, threat, context, now, squadOf(actor, now), scan.count > 0,
        record.flight, Fear.paceFor(scan.chaser, nearest))
    if fled == nil then
        Fear.metrics.cornered = Fear.metrics.cornered + 1
        return nil
    end
    Fear.metrics.fled = Fear.metrics.fled + 1
    return fled
end

function Fear.evaluate(actor, shell, context)
    if context == nil or context.threat == nil or context.threatKind ~= "zombie" then return nil end
    if type(actor) ~= "table" or actor.uid == nil or shell == nil then return nil end
    local now = tonumber(context.now) or nowMs()
    Fear.metrics.asked = Fear.metrics.asked + 1
    local eligible, why = Fear.eligibleActor(actor, now)
    if not eligible then
        Fear.metrics.ineligible = Fear.metrics.ineligible + 1
        local by = Fear.metrics.ineligibleBy
        local reason = tostring(why or "unknown")
        if reason == "category" then
            reason = reason .. ":" .. tostring(Fear.roleOf(actor, now, gameDay()).class)
        end
        by[reason] = (by[reason] or 0) + 1
        return nil
    end
    local threat = context.threat
    local uid = actor.uid
    local record = Fear.recordFor(uid)

    if record.flight ~= nil then
        local leg = Fear.continueFlight(actor, shell, context)
        if leg ~= nil or record.flight ~= nil then return leg end
    end

    local first = ProjectALife.FirstDays
    local verdict
    if first ~= nil and type(first.verdict) == "function" then
        local ok, called, held = pcall(first.verdict, actor, shell, threat, record, context, now)
        if ok then
            if held ~= nil then return held end
            verdict = called
        end
    end

    if verdict ~= "flee" and Fear.avoids(shell, threat, uid) then
        Fear.metrics.avoided = Fear.metrics.avoided + 1
        if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "fear_avoid") end
        return { kind = "idle", intent = "fear_avoid", cooldownUntilMs = now + Fear.settings.avoidHoldMs }
    end

    local scan = Fear.scan(actor, shell, now)
    if Fear.bitten(shell) or scan.sprinterClose then
        Fear.metrics.cornered = Fear.metrics.cornered + 1
        return nil
    end

    local survival = ProjectALife.Survival
    local squad = squadOf(actor, now)
    local inputs = {
        crowd = scan.weight,
        loss = survival ~= nil and survival.recentLoss(actor, shell, now) == true,
        health = survival ~= nil and survival.healthRatio(actor, shell) or 1,
        armed = survival ~= nil and survival.hasFirearm(shell) == true,
        squadAfraid = squad ~= nil and now < squad.afraidUntilMs,
        level = Fear.settings.level,
        courage = Fear.courageFor(Fear.roleOf(actor, now, gameDay()).class,
            Registry.override(actor, Fear.id) == "on") * Fear.dayScale(gameDay()),
    }
    local score = Fear.score(inputs)
    local state = Fear.step(record.state, score)
    if verdict == "flee" then state = "afraid" end
    note(actor, record, state, score, verdict == "flee" and "first_days" or (scan.count .. "_zombies"))
    if state ~= "afraid" then return nil end

    local x, y
    pcall(function() x, y = shell:getX(), shell:getY() end)
    local nearest = distanceBetween(shell, threat)
    if scan.nearest ~= nil and (nearest == nil or scan.nearest < nearest) then nearest = scan.nearest end
    local allowed, why = Fear.noteLeg(record, now, x, y, nearest)
    if not allowed then
        if why == "cornered" then
            Fear.metrics.cornered = Fear.metrics.cornered + 1
            print("[ALIFE-FEAR] uid=" .. tostring(uid) .. " cornered: fighting")
        end
        return nil
    end
    local pace = Fear.paceFor(scan.chaser, nearest)
    if verdict == "flee" then
        if record.flight ~= nil then record.flight.firstDays = true end
        if type(first.pace) == "function" then pace = first.pace(actor, pace, nearest, scan.chaser) end
    end
    local fled = Fear.flee(actor, shell, threat, context, now, squad, scan.count > 0, record.flight, pace)
    if fled == nil then
        Fear.metrics.cornered = Fear.metrics.cornered + 1
        return nil
    end
    if why == "start" then
        print("[ALIFE-FEAR] uid=" .. tostring(uid) .. " flight started pace=" .. pace)
    end
    if squad ~= nil then squad.afraidUntilMs = now + Fear.settings.squadAfraidMs end
    Fear.metrics.fled = Fear.metrics.fled + 1
    local barked = false
    if verdict == "flee" and why == "start" and type(first.onFlight) == "function" then
        local ok, said = pcall(first.onFlight, actor, shell, now)
        barked = ok and said == true
    end
    if not barked then shout(actor, shell, record, now) end
    return fled
end

Registry.register({
    id = Fear.id,
    kind = "reaction",
    priority = 28,
    label = "Fear of the dead",
    summary = "Members whose class is civilian, and to a lesser degree rescue and worker, leave distant zombies alone and run as a group when too many close in: at least 30 seconds, and until no zombie close by is after them, sprinting while the dead are on their heels, jogging while any are near and walking on once the way is clear. Cornered, they fight. Police, military and criminal members, veterans and hardened members stay steady.",
    defaultEnabled = true,
    evaluate = Fear.evaluate,
})

return Fear
