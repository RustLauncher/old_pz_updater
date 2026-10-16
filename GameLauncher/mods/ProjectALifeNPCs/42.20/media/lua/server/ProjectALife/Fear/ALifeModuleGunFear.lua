require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local GunFear = {
    id = "gunFear",
    settings = {
        percent = 60,
        raisedScale = 0.5,
        shotPercent = 75,
        runDistance = 35,
        runSpeed = "sprint",
        reactDelayMs = 400,
        seeTiles = 24,
        aimTiles = 16,
        aimSlackDegrees = 16,
        checkMs = 500,
        raisedCacheMs = 250,
        classCacheMs = 30000,
        memoryMs = 45000,
        fearHoldMs = 9000,
        resumeAfterMs = 6000,
        maxFlightMs = 60000,
        legTimeoutMs = 16000,
        minLegTiles = 8,
        stepTiles = 2,
        hideBonus = 100,
        barkGapMs = 5000,
        armedFlee = false,
        hardenedFlee = false,
        commitMs = 8000,
        commitTiles = 10,
        boostMs = 12000,
        boostFraction = 0.8,
        hurtPercent = 90,
        hurtBelow = 0.95,
        hurtMemoryMs = 15000,
        standRetryMs = 5000,
        escalatePercent = 20,
    },
    flights = {},
    nextCheckAtMs = {},
    barkedAtMs = {},
    classes = {},
    metrics = { gunFearTriggered = 0, gunFearRan = 0, gunFearResumed = 0, gunFearStood = 0,
        gunFearCornered = 0, hurtFled = 0, boosted = 0, committed = 0, committedLegs = 0 },
}
ProjectALife.ModuleGunFear = GunFear

GunFear.defaultClasses = { civilian = true, worker = true, rescue = true }
GunFear.hardenedTemperaments = { veteran = true, predator = true }
GunFear.busyIntents = { talk_hold = true, ordered_surrender = true, ordered_leave = true, ordered_follow = true,
    ordered_follow_wait = true, ordered_flee = true }

function GunFear.clock()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function GunFear.hash(value)
    local text, result = tostring(value or ""), 0
    for index = 1, #text do result = (result * 31 + string.byte(text, index)) % 2147483647 end
    return result
end

function GunFear.roll(uid, key)
    return GunFear.hash(tostring(uid) .. "|" .. tostring(key)) % 100
end

function GunFear.rolls(uid, key, percent)
    return GunFear.roll(uid, key) < (tonumber(percent) or 0)
end

function GunFear.ask(object, method, ...)
    if object == nil then return nil end
    local query = object[method]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object, ...)
    if not ok then return nil end
    return value
end

function GunFear.configure(options)
    options = type(options) == "table" and options or {}
    local settings = GunFear.settings
    if options.percent ~= nil then
        settings.percent = math.max(0, math.min(100, tonumber(options.percent) or settings.percent))
    end
    if options.shotPercent ~= nil then
        settings.shotPercent = math.max(0, math.min(100, tonumber(options.shotPercent) or settings.shotPercent))
    end
    if options.runDistance ~= nil then
        settings.runDistance = math.max(8, math.min(80, tonumber(options.runDistance) or settings.runDistance))
    end
    if options.runSpeed ~= nil then settings.runSpeed = options.runSpeed == "run" and "run" or "sprint" end
    if options.reactDelayMs ~= nil then
        settings.reactDelayMs = math.max(0, math.min(3000, tonumber(options.reactDelayMs) or settings.reactDelayMs))
    end
    if options.fearHoldMs ~= nil then
        settings.fearHoldMs = math.max(1000, tonumber(options.fearHoldMs) or settings.fearHoldMs)
    end
    if options.armedFlee ~= nil then settings.armedFlee = options.armedFlee == true end
    if options.hardenedFlee ~= nil then settings.hardenedFlee = options.hardenedFlee == true end
    return settings
end

function GunFear.reset()
    GunFear.flights, GunFear.nextCheckAtMs, GunFear.barkedAtMs, GunFear.classes = {}, {}, {}, {}
    GunFear.raisedCache = nil
    GunFear.metrics = { gunFearTriggered = 0, gunFearRan = 0, gunFearResumed = 0, gunFearStood = 0,
        gunFearCornered = 0, hurtFled = 0, boosted = 0, committed = 0, committedLegs = 0 }
    return true
end

function GunFear.forgetActor(uid)
    if uid == nil then return end
    GunFear.flights[uid] = nil
    GunFear.nextCheckAtMs[uid] = nil
    GunFear.barkedAtMs[uid] = nil
    GunFear.classes[uid] = nil
end

function GunFear.alive(body)
    if body == nil then return false end
    return GunFear.ask(body, "isDead") ~= true
end

function GunFear.xyz(body)
    local x, y, z = GunFear.ask(body, "getX"), GunFear.ask(body, "getY"), GunFear.ask(body, "getZ")
    if tonumber(x) == nil or tonumber(y) == nil then return nil end
    return x, y, tonumber(z) or 0
end

function GunFear.distance(left, right)
    local ax, ay, az = GunFear.xyz(left)
    local bx, by, bz = GunFear.xyz(right)
    if ax == nil or bx == nil then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2), math.abs(az - bz)
end

function GunFear.kindOf(body)
    if body == nil then return nil end
    if type(instanceof) == "function" and instanceof(body, "IsoPlayer") then return "player" end
    local data = GunFear.ask(body, "getModData")
    if type(data) == "table" and data.ProjectALifeOwned == true then return "actor" end
    return "zombie"
end

function GunFear.keyOf(target)
    local panic = ProjectALife.ModulePanic
    if panic ~= nil and type(panic.keyOf) == "function" then return panic.keyOf(target, "player") end
    return tostring(target)
end

function GunFear.sexOf(target, kind)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.threatSex) == "function" then return speech.threatSex(target, kind) end
    return nil
end

function GunFear.stateOf(actor)
    local loop = ProjectALife.DecisionLoop
    if loop == nil or type(loop.states) ~= "table" or type(actor) ~= "table" then return nil end
    return loop.states[actor.uid]
end

function GunFear.classOf(actor)
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.memberClass) ~= "function" or type(actor) ~= "table" then return nil end
    local now = GunFear.clock()
    local cached = GunFear.classes[actor.uid]
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < GunFear.settings.classCacheMs then return cached.value end
    local ok, class = pcall(fear.memberClass, actor)
    if not ok or type(class) ~= "string" then class = nil end
    GunFear.classes[actor.uid] = { atMs = now, value = class }
    return class
end

function GunFear.defaultOn(actor)
    return GunFear.defaultClasses[GunFear.classOf(actor)] == true
end

function GunFear.enabledFor(actor)
    if type(actor) ~= "table" then return false, "no_actor" end
    if not Registry.allows(actor, "gunFear") then return false, "module_off" end
    local override = Registry.override(actor, "gunFear")
    if override == nil and not GunFear.defaultOn(actor) then return false, "class_off" end
    return true, override
end

function GunFear.temperament(actor, now)
    local risk = ProjectALife.Risk
    if risk == nil or type(risk.temperament) ~= "function" then return "seasoned" end
    local ok, value = pcall(risk.temperament, actor, now)
    if ok and type(value) == "string" then return value end
    return "seasoned"
end

function GunFear.busy(actor, state)
    if type(state) == "table" and GunFear.busyIntents[state.intent] == true then return true end
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory ~= nil and (type(memory.robbery) == "table" or type(memory.orderedTo) == "table") then return true end
    return false
end

function GunFear.eligible(actor, shell, now)
    if type(actor) ~= "table" or actor.uid == nil or shell == nil then return false, "no_actor" end
    local enabled, override = GunFear.enabledFor(actor)
    if not enabled then return false, override end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local panic = ProjectALife.ModulePanic
    if panic ~= nil and type(panic.exempt) == "function" and panic.exempt(memory.conduct) then
        return false, "calm_by_identity"
    end
    if panic ~= nil and type(panic.holdingPost) == "function" and panic.holdingPost(actor) then
        return false, "holding_post"
    end
    if override ~= "on" and (memory.garrisonPost ~= nil or memory.holdPost == true) then
        return false, "garrison"
    end
    if GunFear.settings.armedFlee ~= true then
        local survival = ProjectALife.Survival
        if survival ~= nil and type(survival.hasFirearm) == "function" and survival.hasFirearm(shell) == true then
            return false, "armed"
        end
    end
    if override ~= "on" and GunFear.settings.hardenedFlee ~= true
            and GunFear.hardenedTemperaments[GunFear.temperament(actor, now)] == true then
        return false, "hardened"
    end
    return true, override
end

function GunFear.aiming(player, now)
    local watch = ProjectALife.ThreatWatch
    if watch ~= nil and type(watch.aiming) == "function" and type(watch.hands) == "table" then
        local speech = ProjectALife.Speech
        local key = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(player) or nil
        local entry = key ~= nil and watch.hands[key] or nil
        return watch.aiming(player, entry, now) == true
    end
    return GunFear.ask(player, "isAiming") == true
end

function GunFear.pointedAt(player, shell)
    local watch = ProjectALife.ThreatWatch
    if watch == nil or type(watch.aimedAt) ~= "function" then return false end
    local settings = GunFear.settings
    local ok, aimed = pcall(watch.aimedAt, player, shell, settings.aimTiles, settings.aimSlackDegrees, 0)
    return ok and aimed == true
end

function GunFear.armedState(threat, kind, shell, now)
    if kind == "player" then
        local weapon = GunFear.ask(threat, "getPrimaryHandItem")
        if weapon == nil or GunFear.ask(weapon, "isRanged") ~= true then return nil end
        if not GunFear.aiming(threat, now) then return nil end
        if GunFear.pointedAt(threat, shell) then return "aimed" end
        return "raised"
    end
    if kind == "actor" then
        local combat = ProjectALife.Combat
        if combat == nil or type(combat.targetIsGunman) ~= "function" then return nil end
        local data = GunFear.ask(threat, "getModData")
        if type(data) ~= "table" or data.ProjectALifeDangerPosture ~= "threat" then return nil end
        local ok, gunman = pcall(combat.targetIsGunman, threat)
        if ok and gunman == true then return "raised" end
    end
    return nil
end

function GunFear.visible(shell, threat)
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.visible) == "function" then
        local ok, seen = pcall(perception.visible, shell, threat)
        return ok and seen == true
    end
    return GunFear.ask(shell, "CanSee", threat) == true
end

function GunFear.stance(actor, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return nil end
    local ok, stance = pcall(relations.playerStance, actor, player)
    if ok then return stance end
    return nil
end

function GunFear.raisedPlayers(now)
    local cache = GunFear.raisedCache
    if cache ~= nil and now >= cache.atMs and now - cache.atMs < GunFear.settings.raisedCacheMs then return cache.list end
    local list = {}
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then
        local ok, players = pcall(locator.list)
        if ok and type(players) == "table" then
            for _, player in ipairs(players) do
                local weapon = GunFear.alive(player) and GunFear.ask(player, "getPrimaryHandItem") or nil
                if weapon ~= nil and GunFear.ask(weapon, "isRanged") == true and GunFear.aiming(player, now) then
                    list[#list + 1] = player
                end
            end
        end
    end
    GunFear.raisedCache = { atMs = now, list = list }
    return list
end

function GunFear.sees(actor, shell, now)
    local players = GunFear.raisedPlayers(now)
    local settings = GunFear.settings
    for _, player in ipairs(players) do
        if GunFear.alive(player) then
            local gap, rise = GunFear.distance(shell, player)
            if gap ~= nil and gap <= settings.seeTiles and rise < 1 then
                local state = GunFear.armedState(player, "player", shell, now)
                if state ~= nil and GunFear.visible(shell, player) then
                    local stance = GunFear.stance(actor, player)
                    if stance ~= "allied" and (stance ~= "friendly" or state == "aimed") then
                        return player, state
                    end
                end
            end
        end
    end
    return nil
end

function GunFear.spent(memory, key, now)
    return type(memory) == "table" and memory.fearSpentFor ~= nil and memory.fearSpentFor == key
        and now - (tonumber(memory.fearSpentAtMs) or -1e12) < GunFear.settings.memoryMs
end

function GunFear.remember(actor, key, value)
    local panic = ProjectALife.ModulePanic
    if panic ~= nil and type(panic.remember) == "function" then
        panic.remember(actor, key, value)
        return
    end
    if type(actor.memory) ~= "table" then actor.memory = {} end
    actor.memory[key] = value
end

function GunFear.speak(shell, event, target, kind, attack)
    local speech, voice = ProjectALife.Speech, ProjectALife.Voice
    if voice == nil or type(voice.play) ~= "function" then return false end
    if speech ~= nil and type(speech.allows) == "function"
            and not speech.allows(shell, nil, event, nil, nil) then return false end
    local ok, played = pcall(voice.play, shell, event, { urgent = true,
        context = { targetKind = kind, reason = "gun_fear", attack = attack, psex = GunFear.sexOf(target, kind) } })
    return ok and played == true
end

function GunFear.newFlight(actor, threat, kind, key, now, delayMs, shell)
    local flight = { uid = actor.uid, generation = actor.generation, threat = threat, kind = kind, key = key,
        startedAtMs = now, seenAtMs = now, reactUntilMs = now + (tonumber(delayMs) or 0), legs = 0 }
    local x, y = GunFear.xyz(shell)
    flight.originX, flight.originY = x, y
    return flight
end

function GunFear.committed(flight, shell, now)
    local settings = GunFear.settings
    if now - flight.startedAtMs < settings.commitMs then return false end
    local x, y = GunFear.xyz(shell)
    if x == nil or flight.originX == nil then return true end
    return (x - flight.originX) ^ 2 + (y - flight.originY) ^ 2 >= settings.commitTiles ^ 2
end

function GunFear.boost(actor, shell, now)
    local endurance = ProjectALife.Endurance
    if endurance == nil or type(endurance.boost) ~= "function" then return false end
    local settings = GunFear.settings
    local ok, done = pcall(endurance.boost, actor, shell, settings.boostMs, settings.boostFraction, now)
    if ok and done == true then
        GunFear.metrics.boosted = GunFear.metrics.boosted + 1
        return true
    end
    return false
end

function GunFear.frighten(actor, shell, target, now, options)
    options = type(options) == "table" and options or {}
    if type(actor) ~= "table" or shell == nil then return false, "no_actor" end
    now = tonumber(now) or GunFear.clock()
    local eligible, why = GunFear.eligible(actor, shell, now)
    if not eligible then return false, why end
    if GunFear.busy(actor, GunFear.stateOf(actor)) then return false, "busy" end
    local key = tostring(options.key or (GunFear.keyOf(target) .. ":aim"))
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if GunFear.spent(memory, key, now) then return false, "spent" end
    GunFear.remember(actor, "fearSpentFor", key)
    GunFear.remember(actor, "fearSpentAtMs", now)
    local metrics = GunFear.metrics
    local settings = GunFear.settings
    local stands = memory.fearStandKey == key and math.floor(tonumber(memory.fearStands) or 0) or 0
    local percent = math.min(100, (tonumber(options.percent) or settings.percent) + stands * settings.escalatePercent)
    if not GunFear.rolls(actor.uid, stands == 0 and key or (key .. "#" .. stands), percent) then
        metrics.gunFearStood = metrics.gunFearStood + 1
        GunFear.remember(actor, "fearStandKey", key)
        GunFear.remember(actor, "fearStands", stands + 1)
        GunFear.remember(actor, "fearSpentAtMs", now - math.max(0, settings.memoryMs - settings.standRetryMs))
        return false, "stands"
    end
    if stands > 0 then
        metrics.gunFearEscalated = (metrics.gunFearEscalated or 0) + 1
        GunFear.remember(actor, "fearStands", 0)
    end
    local data = GunFear.ask(shell, "getModData")
    if type(data) ~= "table" then return false, "no_shell" end
    data.ProjectALifeFearUntilMs = now + GunFear.settings.fearHoldMs
    data.ProjectALifeFearOf = key
    local kind = options.kind or GunFear.kindOf(target) or "player"
    GunFear.flights[actor.uid] = GunFear.newFlight(actor, target, kind, key, now, GunFear.settings.reactDelayMs, shell)
    GunFear.boost(actor, shell, now)
    metrics.gunFearTriggered = metrics.gunFearTriggered + 1
    local panic = ProjectALife.ModulePanic
    if panic ~= nil and type(panic.metrics) == "table" then panic.metrics.fears = (panic.metrics.fears or 0) + 1 end
    if GunFear.speak(shell, "GUN_FEAR", target, kind) then GunFear.barkedAtMs[actor.uid] = now end
    return true, "flees"
end

function GunFear.onAimedAt(record, shell, player, now)
    return GunFear.frighten(record, shell, player, now, {
        key = GunFear.keyOf(player) .. ":aim",
        percent = GunFear.settings.percent,
        kind = "player",
    })
end

function GunFear.onShot(record, shell, attacker, ranged, now)
    if ranged ~= true then return false, "not_a_bullet" end
    return GunFear.frighten(record, shell, attacker, now, {
        key = GunFear.keyOf(attacker) .. ":shot",
        percent = GunFear.settings.shotPercent,
    })
end

function GunFear.onHurt(record, shell, attacker, now)
    if type(record) ~= "table" or shell == nil or attacker == nil then return false, "no_actor" end
    local kind = GunFear.kindOf(attacker)
    if kind ~= "player" and kind ~= "actor" then return false, "not_a_person" end
    now = tonumber(now) or GunFear.clock()
    local own = type(record.memory) == "table" and record.memory or {}
    if own.hostileOverride == true then return false, "aggressor" end
    local engaged = GunFear.stateOf(record)
    if type(engaged) == "table" and engaged.kind == "combat" and engaged.threat == attacker then
        return false, "fighting"
    end
    local survival = ProjectALife.Survival
    if survival ~= nil and type(survival.healthRatio) == "function" then
        local ok, ratio = pcall(survival.healthRatio, record, shell)
        if ok and tonumber(ratio) ~= nil and ratio > GunFear.settings.hurtBelow then return false, "unhurt" end
    end
    local existing = GunFear.flights[record.uid]
    if existing ~= nil then
        existing.threat, existing.kind = attacker, kind
        GunFear.boost(record, shell, now)
        return true, "flees"
    end
    local key = GunFear.keyOf(attacker) .. ":hurt"
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.fearSpentFor == key and now - (tonumber(memory.fearSpentAtMs) or -1e12) < GunFear.settings.hurtMemoryMs then
        return false, "spent"
    end
    local fled, why = GunFear.frighten(record, shell, attacker, now, {
        key = key, percent = GunFear.settings.hurtPercent, kind = kind })
    if fled then GunFear.metrics.hurtFled = GunFear.metrics.hurtFled + 1 end
    return fled, why
end

function GunFear.hidden(tx, ty, tz, cx, cy, cz)
    local sight = ProjectALife.Sight
    if sight == nil or type(sight.hides) ~= "function" or type(sight.between) ~= "function" then return false end
    return sight.hides(sight.between(tx, ty, tz, cx, cy, cz)) == true
end

function GunFear.flightPoint(shell, threat)
    local withdraw = ProjectALife.ModuleWithdraw
    if withdraw == nil or type(withdraw.rayOut) ~= "function" or type(withdraw.bearings) ~= "table"
            or type(getCell) ~= "function" then return nil end
    local sx, sy, sz = GunFear.xyz(shell)
    local tx, ty, tz = GunFear.xyz(threat)
    if sx == nil or tx == nil then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local settings = GunFear.settings
    local fx, fy = sx - tx, sy - ty
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.01 then fx, fy, length = 1, 0, 1 end
    fx, fy = fx / length, fy / length
    local floorX, floorY, floorZ = math.floor(sx), math.floor(sy), math.floor(sz)
    local best, bestScore
    for index = 1, #withdraw.bearings do
        local bearing = withdraw.bearings[index]
        local dot = fx * bearing[1] + fy * bearing[2]
        if dot > -0.1 then
            local ok, found = pcall(withdraw.rayOut, cell, floorX, floorY, floorZ, index,
                settings.runDistance, settings.stepTiles)
            if ok and found ~= nil then
                local reach = math.sqrt((found.x - floorX) ^ 2 + (found.y - floorY) ^ 2)
                if reach >= 3 then
                    local score = math.min(reach, settings.runDistance) + dot * 4
                    if reach >= settings.minLegTiles then score = score + 2 end
                    if GunFear.hidden(tx, ty, tz, found.x, found.y, floorZ) then score = score + settings.hideBonus end
                    if bestScore == nil or score > bestScore then best, bestScore = found, score end
                end
            end
        end
    end
    local cover = ProjectALife.ModuleCover
    if cover ~= nil and type(cover.find) == "function" then
        local ok, point = pcall(cover.find, shell, threat, { away = true, range = 0 })
        if ok and type(point) == "table" and tonumber(point.x) ~= nil and tonumber(point.y) ~= nil then
            local reach = math.sqrt((point.x - sx) ^ 2 + (point.y - sy) ^ 2)
            local score = math.min(reach, settings.runDistance) * 0.5 + settings.hideBonus
            if bestScore == nil or score > bestScore then
                best, bestScore = { x = point.x - 0.5, y = point.y - 0.5, z = point.z or floorZ }, score
            end
        end
    end
    return best
end

function GunFear.stampFlight(shell, untilMs)
    local data = GunFear.ask(shell, "getModData")
    if type(data) ~= "table" then return end
    data.ProjectALifeFlightUntilMs = untilMs
    data.ProjectALifeFlightPace = GunFear.settings.runSpeed
    if data.ProjectALifeDangerPosture == nil or data.ProjectALifeDangerPosture == "relaxed" then
        data.ProjectALifeDangerPosture = "alert"
    end
    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.setAimWalk) == "function" then pcall(combat.setAimWalk, shell, false, "flight") end
end

function GunFear.clearFlight(shell)
    local data = GunFear.ask(shell, "getModData")
    if type(data) ~= "table" then return end
    data.ProjectALifeFlightUntilMs = nil
    data.ProjectALifeFlightPace = nil
end

function GunFear.finish(actor, shell, flight, reason)
    GunFear.flights[actor.uid] = nil
    GunFear.clearFlight(shell)
    local endurance = ProjectALife.Endurance
    if endurance ~= nil and type(endurance.release) == "function" then pcall(endurance.release, actor) end
    local survival = ProjectALife.Survival
    if survival ~= nil and type(survival.forget) == "function" then survival.forget(actor.uid, actor.generation) end
    if reason == "cornered" then
        GunFear.metrics.gunFearCornered = GunFear.metrics.gunFearCornered + 1
    elseif flight ~= nil and flight.legs > 0 then
        GunFear.metrics.gunFearResumed = GunFear.metrics.gunFearResumed + 1
    end
    return nil
end

function GunFear.leg(actor, shell, threat, flight, context, now)
    local settings = GunFear.settings
    local point = GunFear.flightPoint(shell, threat)
    if point == nil or type(context.startMovement) ~= "function" then
        return GunFear.finish(actor, shell, flight, "cornered")
    end
    GunFear.boost(actor, shell, now)
    GunFear.stampFlight(shell, now + settings.legTimeoutMs + 1500)
    local state = context.startMovement(actor, shell, { x = point.x + 0.5, y = point.y + 0.5, z = point.z },
        "gun_flee", {
            kind = "retreat",
            activity = "moving",
            pace = settings.runSpeed,
            timeoutMs = settings.legTimeoutMs,
            threat = threat,
            threatKind = flight.kind,
        })
    if state == nil then return GunFear.finish(actor, shell, flight, "cornered") end
    state.reason = "gun_fear"
    state.aimed = false
    flight.legs = flight.legs + 1
    local survival = ProjectALife.Survival
    if survival ~= nil and type(survival.beginDisengage) == "function" then
        survival.beginDisengage(actor, shell, threat, now, settings.resumeAfterMs + settings.legTimeoutMs)
    end
    if flight.legs == 1 then
        GunFear.metrics.gunFearRan = GunFear.metrics.gunFearRan + 1
        if now - (GunFear.barkedAtMs[actor.uid] or -1e12) >= settings.barkGapMs then
            GunFear.barkedAtMs[actor.uid] = now
            GunFear.speak(shell, "RETREAT", threat, flight.kind, "firearm")
        end
    end
    return state
end

function GunFear.continueFlight(actor, shell, context)
    if type(actor) ~= "table" or actor.uid == nil or shell == nil or type(context) ~= "table" then return nil end
    local flight = GunFear.flights[actor.uid]
    if flight == nil then return nil end
    local now = tonumber(context.now) or GunFear.clock()
    if flight.generation ~= actor.generation then
        GunFear.flights[actor.uid] = nil
        return nil
    end
    local threat = flight.threat
    if not GunFear.alive(threat) or not Registry.isEnabled("gunFear") then
        return GunFear.finish(actor, shell, flight, "over")
    end
    local settings = GunFear.settings
    local fear = ProjectALife.ModuleFear
    if fear ~= nil and type(fear.bitten) == "function" and fear.bitten(shell) == true then
        return GunFear.finish(actor, shell, flight, "cornered")
    end
    local seen = GunFear.visible(shell, threat)
    if seen then flight.seenAtMs = now end
    if now - flight.startedAtMs >= settings.maxFlightMs then
        return GunFear.finish(actor, shell, flight, "worn_out")
    end
    local committed = flight.committed == true
    if not committed and flight.legs > 0 and GunFear.committed(flight, shell, now) then
        flight.committed = true
        committed = true
        GunFear.metrics.committed = GunFear.metrics.committed + 1
    end
    if not seen and flight.legs > 0 and committed and now - flight.seenAtMs >= settings.resumeAfterMs then
        return GunFear.finish(actor, shell, flight, "out_of_sight")
    end
    if now < flight.reactUntilMs then
        GunFear.ask(shell, "faceThisObject", threat)
        if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "gun_react") end
        return { kind = "idle", intent = "gun_react", cooldownUntilMs = flight.reactUntilMs }
    end
    if not seen and flight.legs > 0 and committed then
        if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "gun_hide") end
        return { kind = "idle", intent = "gun_hide", cooldownUntilMs = now + 500 }
    end
    if flight.legs > 0 and not committed then GunFear.metrics.committedLegs = GunFear.metrics.committedLegs + 1 end
    return GunFear.leg(actor, shell, threat, flight, context, now)
end

function GunFear.startFlight(actor, shell, threat, kind, now, context)
    if type(actor) ~= "table" or actor.uid == nil or shell == nil or threat == nil or type(context) ~= "table" then
        return nil
    end
    now = tonumber(now) or GunFear.clock()
    local flight = GunFear.flights[actor.uid]
    if flight == nil then
        flight = GunFear.newFlight(actor, threat, kind or GunFear.kindOf(threat) or "player",
            GunFear.keyOf(threat) .. ":order", now, 0, shell)
        GunFear.flights[actor.uid] = flight
    end
    flight.threat = threat
    local pass = { now = now }
    for name, value in pairs(context) do
        if name ~= "now" then pass[name] = value end
    end
    return GunFear.continueFlight(actor, shell, pass)
end

function GunFear.passOn(now, helpers)
    local pass = { now = now }
    if type(helpers) == "table" then
        for name, value in pairs(helpers) do pass[name] = value end
    end
    return pass
end

function GunFear.interrupt(actor, shell, state, now, helpers)
    local uid = type(actor) == "table" and actor.uid or nil
    if uid == nil then return nil end
    if GunFear.flights[uid] == nil then
        if now < (GunFear.nextCheckAtMs[uid] or 0) then return nil end
        GunFear.nextCheckAtMs[uid] = now + GunFear.settings.checkMs
        if #GunFear.raisedPlayers(now) == 0 then return nil end
        if not Registry.isEnabled("gunFear") or GunFear.busy(actor, state) then return nil end
        if not GunFear.eligible(actor, shell, now) then return nil end
        local player, armed = GunFear.sees(actor, shell, now)
        if player == nil then return nil end
        local settings = GunFear.settings
        local aimed = armed == "aimed"
        if not GunFear.frighten(actor, shell, player, now, {
                key = GunFear.keyOf(player) .. (aimed and ":aim" or ":raised"),
                percent = aimed and settings.percent or settings.percent * settings.raisedScale,
                kind = "player" }) then
            return nil
        end
    elseif GunFear.busy(actor, state) then
        return nil
    end
    return GunFear.continueFlight(actor, shell, GunFear.passOn(now, helpers))
end

function GunFear.evaluate(actor, shell, context)
    if type(context) ~= "table" or context.threat == nil or type(actor) ~= "table" or actor.uid == nil
            or shell == nil then return nil end
    local kind = context.threatKind
    if kind ~= "player" and kind ~= "actor" then return nil end
    local now = tonumber(context.now) or GunFear.clock()
    if GunFear.flights[actor.uid] ~= nil then return GunFear.continueFlight(actor, shell, context) end
    if not GunFear.eligible(actor, shell, now) then return nil end
    local armed = GunFear.armedState(context.threat, kind, shell, now)
    if armed == nil then return nil end
    local settings = GunFear.settings
    local aimed = armed == "aimed"
    if not GunFear.frighten(actor, shell, context.threat, now, {
            key = GunFear.keyOf(context.threat) .. (aimed and ":aim" or ":raised"),
            percent = aimed and settings.percent or settings.percent * settings.raisedScale,
            kind = kind }) then
        return nil
    end
    return GunFear.continueFlight(actor, shell, context)
end

Registry.register({
    id = "gunFear",
    kind = "reaction",
    priority = 29,
    label = "Gun fear",
    summary = "An NPC that is not itself well armed backs away from a player or hostile who aims or raises a firearm: a per-NPC roll, then a run along a path that breaks line of sight, and a return to its goal once the gun has been out of sight for a few seconds. On by default for civilian, worker and rescue classes and melee crews.",
    defaultEnabled = true,
    evaluate = GunFear.evaluate,
})

return GunFear
