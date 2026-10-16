ProjectALife = ProjectALife or {}

local FirstDays = {
    settings = {
        enabled = true,
        strengthPercent = 100,
        lengthDays = 12,
        contagion = true,

        span = 12,
        nightBonus = 0.08,
        defaultFactor = 0.8,
        steadyBelow = 0.5,
        cacheMs = 500,
        clockMs = 1000,
        roleMs = 30000,

        infectedBonus = 0.3,
        biteBonus = 0.2,
        hitBonus = 0.15,
        healthBonus = 0.3,
        woundCap = 0.5,
        steadyWound = 0.4,

        fleeLevel = 0.5,
        stareLevel = 0.6,
        startleLevel = 0.45,
        idleLevel = 0.7,
        sprintLevel = 0.6,
        scatterLevel = 0.8,
        hideLevel = 0.7,
        alertLevel = 0.2,

        triggerBase = 4,
        triggerSpan = 10,
        armedScale = 0.55,
        holdTiles = 3.5,
        farPace = 9,
        shelterTiles = 24,
        shelterMs = 25000,
        arriveTiles = 2,

        stareMinMs = 700,
        stareSpanMs = 1300,
        stareGapMs = 40000,
        startleMinMs = 600,
        startleSpanMs = 800,
        startleGapMs = 8000,
        alertMs = 800,
        alertGapMs = 12000,
        holdMs = 1500,

        idleMemoryMs = 30000,
        idleMemorySpanMs = 60000,
        hideMinMs = 40000,
        hideSpanMs = 50000,
        openHideMs = 12000,
        travelMs = 16000,

        sprintSpanMs = 4000,

        spreadLevel = 0.5,
        spreadGapMs = 4000,
        spreadBase = 0.45,
        spreadGroupTiles = 30,
        spreadNearTiles = 12,
        spreadMinMs = 30000,
        spreadSpanMs = 30000,
        spreadStranger = 0.6,
        steadyTiles = 10,
        steadyScale = 0.5,

        noiseGunPlayer = 0.3,
        noiseGunOther = 0.15,
        noiseOther = 0.2,
        noiseWindowMs = 30000,
        noiseKeepMs = 20000,
        noiseCap = 12,
        minNoiseRadius = 20,

        barkGapMs = 7000,
        groupBarkGapMs = 3500,
        hideBarkMs = 15000,
        barkMaxDay = 4,
        sceneMaxDay = 4,
        groupBarkDelayMs = 900,

        hearTiles = { gunfire = 60, scream = 45, heli = 80, siren = 90, explosion = 90 },
    },
    curve = { { 0, 1 }, { 1, 1 }, { 2, 0.85 }, { 3, 0.65 }, { 4, 0.65 }, { 12, 0.1 }, { 16, 0 } },
    registers = {
        family = 1, civilian = 1, worker = 0.95, rescue = 0.85,
        law = 0.45, swat = 0.2, military = 0.25, elite = 0.1,
        outlaw = 0.3, crime = 0.3, prison = 0.35, gang = 0.3, club = 0.3, raider = 0.2,
    },
    classes = { civilian = 1, worker = 0.95, rescue = 0.85, police = 0.45, military = 0.25, criminal = 0.3 },
    alertRegisters = { law = true, swat = true, military = true, elite = true },
    alertClasses = { police = true, military = true },
    temperaments = { fresh = 1.1, seasoned = 0.95, veteran = 0.75, predator = 0.6 },
    stagger = { fresh = 1, seasoned = 0.75, veteran = 0.5, predator = 0.4 },
    holdIntents = { hold = true, alerted = true, idle_alert = true, fear_avoid = true, scan = true,
        panic_hide = true, panic_startle = true, panic_stare = true },
    states = {},
    noises = {},
    groupBarkAtMs = {},
    count = 0,
    metrics = { level = 0, personal = 0, noises = 0, panicStartles = 0, panicStares = 0, panicFlights = 0,
        panicHides = 0, panicContagion = 0, panicAlerts = 0, idleSuppressed = 0, doorsShut = 0, barks = 0,
        barkFallbacks = 0 },
}
ProjectALife.FirstDays = FirstDays

function FirstDays.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function FirstDays.readClock()
    local clock = getGameTime()
    local day = clock:getNightsSurvived()
    local hour
    if type(clock.getTimeOfDay) == "function" then hour = clock:getTimeOfDay() else hour = clock:getHour() end
    return day, hour
end

function FirstDays.clockNow(now)
    now = tonumber(now) or FirstDays.nowMs()
    local cache = FirstDays.cache
    if cache ~= nil and now >= cache.atMs and now - cache.atMs < FirstDays.settings.clockMs then
        return cache.day, cache.hour
    end
    local day, hour = 0, 12
    if type(getGameTime) == "function" then
        local ok, readDay, readHour = pcall(FirstDays.readClock)
        if ok then day, hour = tonumber(readDay) or 0, tonumber(readHour) or 12 end
    end
    FirstDays.cache = { atMs = now, day = day, hour = hour }
    return day, hour
end

function FirstDays.nightFactor(hour)
    hour = tonumber(hour)
    if hour == nil then return 0 end
    if hour >= 22 or hour < 5 then return 1 end
    if hour >= 20 then return (hour - 20) / 2 end
    if hour < 7 then return (7 - hour) / 2 end
    return 0
end

function FirstDays.curveAt(position)
    local curve = FirstDays.curve
    position = tonumber(position) or 0
    if position <= curve[1][1] then return curve[1][2] end
    for index = 2, #curve do
        local from, to = curve[index - 1], curve[index]
        if position <= to[1] then
            local width = to[1] - from[1]
            if width <= 0 then return to[2] end
            return from[2] + (to[2] - from[2]) * (position - from[1]) / width
        end
    end
    return curve[#curve][2]
end

function FirstDays.level(day, hour)
    local settings = FirstDays.settings
    if settings.enabled ~= true then return 0 end
    if day == nil then day, hour = FirstDays.clockNow() end
    day = math.max(0, tonumber(day) or 0)
    local length = math.max(1, tonumber(settings.lengthDays) or 12)
    local base = FirstDays.curveAt(day * settings.span / length)
    if base <= 0 then return 0 end
    local strength = math.max(0, tonumber(settings.strengthPercent) or 100) / 100
    local night = FirstDays.nightFactor(hour) * settings.nightBonus
    return math.max(0, math.min(1, (base + night) * strength))
end

function FirstDays.globalLevel(now)
    local settings = FirstDays.settings
    if settings.enabled ~= true then return 0 end
    now = tonumber(now) or FirstDays.nowMs()
    local cache = FirstDays.levelCache
    if cache ~= nil and now >= cache.atMs and now - cache.atMs < settings.clockMs then return cache.value end
    local day, hour = FirstDays.clockNow(now)
    local value = FirstDays.level(day, hour)
    FirstDays.levelCache = { atMs = now, value = value }
    FirstDays.metrics.level = math.floor(value * 100 + 0.5)
    return value
end

function FirstDays.active(now)
    return FirstDays.globalLevel(now) > 0
end

function FirstDays.configure(options)
    options = type(options) == "table" and options or {}
    local settings = FirstDays.settings
    if options.enabled ~= nil then settings.enabled = options.enabled == true end
    if options.strengthPercent ~= nil then
        settings.strengthPercent = math.max(0, math.min(200, math.floor(tonumber(options.strengthPercent) or 100)))
    end
    if options.lengthDays ~= nil then
        settings.lengthDays = math.max(2, math.min(60, math.floor(tonumber(options.lengthDays) or 12)))
    end
    if options.contagion ~= nil then settings.contagion = options.contagion == true end
    FirstDays.cache, FirstDays.levelCache = nil, nil
    return settings
end

function FirstDays.reset()
    FirstDays.states, FirstDays.noises, FirstDays.groupBarkAtMs = {}, {}, {}
    FirstDays.count = 0
    FirstDays.cache, FirstDays.levelCache = nil, nil
    FirstDays.metrics = { level = 0, personal = 0, noises = 0, panicStartles = 0, panicStares = 0, panicFlights = 0,
        panicHides = 0, panicContagion = 0, panicAlerts = 0, idleSuppressed = 0, doorsShut = 0, barks = 0,
        barkFallbacks = 0 }
    return true
end

function FirstDays.forget(uid)
    if uid == nil or FirstDays.states[uid] == nil then return false end
    FirstDays.states[uid] = nil
    FirstDays.count = math.max(0, FirstDays.count - 1)
    return true
end

function FirstDays.stateOf(uid)
    local state = FirstDays.states[uid]
    if state == nil then
        state = { level = 0, levelAtMs = -1e12, alarmAtMs = -1e12, seenAtMs = -1e12, stareAtMs = -1e12,
            startleAtMs = -1e12, noiseAtMs = -1e12, barkAtMs = -1e12, hideBarkAtMs = -1e12,
            spreadAtMs = -1e12, startleUntilMs = 0 }
        FirstDays.states[uid] = state
        FirstDays.count = FirstDays.count + 1
    end
    return state
end

function FirstDays.hash(text)
    text = tostring(text or "")
    local value = 0
    for index = 1, #text do value = (value * 31 + string.byte(text, index)) % 2147483647 end
    return value
end

function FirstDays.dataOf(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    if type(shell.hasModData) == "function" then
        local okHas, has = pcall(shell.hasModData, shell)
        if not okHas or has ~= true then return nil end
    end
    local ok, data = pcall(shell.getModData, shell)
    if ok and type(data) == "table" then return data end
    return nil
end

function FirstDays.xyzOf(body)
    return body:getX(), body:getY(), body:getZ()
end

function FirstDays.positionOf(body)
    if body == nil or type(body.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(FirstDays.xyzOf, body)
    if ok and type(x) == "number" and type(y) == "number" then return x, y, tonumber(z) or 0 end
    return nil
end

function FirstDays.flatDistance(shell, other)
    local sx, sy, sz = FirstDays.positionOf(shell)
    local ox, oy, oz = FirstDays.positionOf(other)
    if sx == nil or ox == nil then return nil end
    if math.abs(sz - oz) >= 2.5 then return nil end
    return math.sqrt((sx - ox) ^ 2 + (sy - oy) ^ 2)
end

function FirstDays.explicitClass(actor)
    local catalog = ProjectALife.Catalog
    if catalog == nil or type(catalog.npc) ~= "function" or actor.profileId == nil then return nil end
    local ok, profile = pcall(catalog.npc, actor.profileId)
    local general = ok and type(profile) == "table" and type(profile.general) == "table" and profile.general or nil
    local class = general ~= nil and general.npcClass or nil
    if type(class) == "string" and class ~= "" then return class end
    return nil
end

function FirstDays.roleOf(actor, now)
    local settings = FirstDays.settings
    local state = FirstDays.stateOf(actor.uid)
    now = tonumber(now) or FirstDays.nowMs()
    local cached = state.role
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < settings.roleMs then return cached end
    local role = { atMs = now, factor = settings.defaultFactor, temperament = "fresh" }
    local roles = ProjectALife.DialogueRoles
    if roles ~= nil and type(roles.describe) == "function" then
        local day = FirstDays.clockNow(now)
        local ok, who = pcall(roles.describe, actor, day)
        if ok and type(who) == "table" then
            role.register = who.register
            role.temperament = who.temperament or role.temperament
            local value = FirstDays.registers[tostring(who.register)]
            if value ~= nil then role.factor = value end
        end
    end
    local class = FirstDays.explicitClass(actor)
    if class == nil and role.register == nil then
        local fear = ProjectALife.ModuleFear
        if fear ~= nil and type(fear.memberClass) == "function" then
            local ok, found = pcall(fear.memberClass, actor)
            if ok and type(found) == "string" then class = found end
        end
    end
    if class ~= nil and FirstDays.classes[class] ~= nil then
        role.factor, role.class = FirstDays.classes[class], class
    end
    role.steady = role.factor <= settings.steadyBelow
    role.alert = FirstDays.alertRegisters[tostring(role.register)] == true
        or FirstDays.alertClasses[tostring(role.class)] == true
    state.role = role
    return role
end

function FirstDays.woundBonus(actor, shell, role, base, now)
    if shell == nil then return 0 end
    local settings = FirstDays.settings
    local bonus = 0
    local data = FirstDays.dataOf(shell)
    if data ~= nil then
        if data.ProjectALifeInfectedBy ~= nil then bonus = bonus + settings.infectedBonus end
        local bitten = tonumber(data.ProjectALifeLastBiteAtMs)
        if bitten ~= nil and now >= bitten and now - bitten < 20000 then bonus = bonus + settings.biteBonus end
        local hit = tonumber(data.ProjectALifeLastHitAtMs)
        if hit ~= nil and now >= hit and now - hit < 8000 then bonus = bonus + settings.hitBonus end
    end
    local survival = ProjectALife.Survival
    if survival ~= nil and type(survival.healthRatio) == "function" then
        local ok, ratio = pcall(survival.healthRatio, actor, shell)
        if ok and type(ratio) == "number" then
            bonus = bonus + (1 - math.max(0, math.min(1, ratio))) * settings.healthBonus
        end
    end
    bonus = math.min(bonus, settings.woundCap) * math.min(1, base * 1.5)
    if role.steady then bonus = bonus * settings.steadyWound end
    return bonus
end

function FirstDays.contagionBonus(state, now)
    local spread = state.contagion
    if spread == nil then return 0 end
    if now >= spread.untilMs then
        state.contagion = nil
        return 0
    end
    if now <= spread.atMs then return spread.bonus end
    return spread.bonus * (1 - (now - spread.atMs) / (spread.untilMs - spread.atMs))
end

function FirstDays.levelFor(actor, shell, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return 0 end
    now = tonumber(now) or FirstDays.nowMs()
    local state = FirstDays.stateOf(actor.uid)
    if now >= state.levelAtMs and now - state.levelAtMs < settings.cacheMs then return state.level end
    local base = FirstDays.globalLevel(now)
    local level = 0
    if base > 0 then
        local role = FirstDays.roleOf(actor, now)
        level = base * role.factor * (FirstDays.temperaments[role.temperament] or 1)
        level = level + FirstDays.woundBonus(actor, shell, role, base, now)
        level = level + FirstDays.contagionBonus(state, now)
        level = math.max(0, math.min(1, level))
    end
    state.level, state.levelAtMs = level, now
    FirstDays.metrics.personal = math.floor(level * 100 + 0.5)
    return level
end

function FirstDays.addContagion(uid, bonus, now, windowMs)
    local state = FirstDays.stateOf(uid)
    if bonus <= FirstDays.contagionBonus(state, now) then return false end
    state.contagion = { bonus = bonus, atMs = now, untilMs = now + windowMs }
    state.alarmAtMs = now
    state.levelAtMs = -1e12
    return true
end

function FirstDays.peek(uid)
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return nil end
    if type(registry.peek) == "function" then return registry.peek(uid) end
    if type(registry.read) == "function" then return registry.read(uid) end
    return nil
end

function FirstDays.gather(actor, shell, now)
    local watchdog = ProjectALife.Watchdog
    local settings = FirstDays.settings
    local result = { members = {}, strangers = {}, steady = {} }
    if watchdog == nil or type(watchdog.bindings) ~= "table" then return result end
    local sx, sy, sz = FirstDays.positionOf(shell)
    if sx == nil then return result end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local reach = math.max(settings.spreadGroupTiles, settings.spreadNearTiles)
    for uid, binding in pairs(watchdog.bindings) do
        if uid ~= actor.uid and type(binding) == "table" and binding.shell ~= nil then
            local ox, oy, oz = FirstDays.positionOf(binding.shell)
            if ox ~= nil and math.abs(oz - sz) < 3.5 then
                local flat = math.sqrt((ox - sx) ^ 2 + (oy - sy) ^ 2)
                local record = nil
                if flat <= reach then record = FirstDays.peek(uid) end
                if type(record) == "table" and record.lifecycle ~= "dead" then
                    local other = type(record.memory) == "table" and record.memory or {}
                    local same = memory.groupId ~= nil and other.groupId == memory.groupId
                    local range = same and settings.spreadGroupTiles or settings.spreadNearTiles
                    if flat <= range then
                        local row = { uid = uid, record = record, shell = binding.shell, x = ox, y = oy,
                            distance = flat, range = range, same = same }
                        if FirstDays.roleOf(record, now).steady then
                            result.steady[#result.steady + 1] = row
                        elseif same then
                            result.members[#result.members + 1] = row
                        else
                            result.strangers[#result.strangers + 1] = row
                        end
                    end
                end
            end
        end
    end
    return result
end

function FirstDays.spread(actor, shell, level, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or settings.contagion ~= true then return 0 end
    if type(actor) ~= "table" or actor.uid == nil or shell == nil then return 0 end
    level = tonumber(level) or 0
    if level < settings.spreadLevel then return 0 end
    now = tonumber(now) or FirstDays.nowMs()
    local mine = FirstDays.stateOf(actor.uid)
    if now - mine.spreadAtMs < settings.spreadGapMs then return 0 end
    mine.spreadAtMs = now
    local found = FirstDays.gather(actor, shell, now)
    local windowMs = settings.spreadMinMs + settings.spreadSpanMs * level
    local affected, first = 0, nil
    local lists = { found.members, found.strangers }
    for listIndex = 1, 2 do
        local list = lists[listIndex]
        for index = 1, #list do
            local row = list[index]
            local bonus = settings.spreadBase * level * (row.same and 1 or settings.spreadStranger)
                * (1 - 0.5 * row.distance / row.range)
            for steadyIndex = 1, #found.steady do
                if FirstDays.near(found.steady[steadyIndex], row, settings.steadyTiles) then
                    bonus = bonus * settings.steadyScale
                    break
                end
            end
            if FirstDays.addContagion(row.uid, bonus, now, windowMs) then
                affected = affected + 1
                if row.same and (first == nil or row.distance < first.distance) then first = row end
            end
        end
    end
    if affected > 0 then
        FirstDays.metrics.panicContagion = FirstDays.metrics.panicContagion + affected
        local calm = nil
        for index = 1, #found.steady do
            if calm == nil or found.steady[index].distance < calm.distance then calm = found.steady[index] end
        end
        if calm ~= nil then FirstDays.steadyShout(calm.shell) end
        if first ~= nil then FirstDays.groupShout(first, now) end
    end
    return affected
end

function FirstDays.near(a, b, tiles)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= tiles * tiles
end

function FirstDays.steadyShout(shell)
    local voice = ProjectALife.Voice
    if voice == nil or type(voice.play) ~= "function" then return false end
    local ok, played = pcall(voice.play, shell, "STEADY", { urgent = true })
    return ok and played == true
end

function FirstDays.groupShout(row, now)
    local talk = ProjectALife.Talk
    local delay = FirstDays.settings.groupBarkDelayMs + FirstDays.hash(row.uid) % 700
    if talk ~= nil and type(talk.later) == "function" then
        return talk.later(delay, function()
            FirstDays.bark(row.record, row.shell, "PANIC_DAY_GROUP", now + delay)
        end) == true
    end
    return FirstDays.bark(row.record, row.shell, "PANIC_DAY_GROUP", now)
end

function FirstDays.noteNoise(x, y, z, radius, kind, player, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true then return false end
    x, y, radius = tonumber(x), tonumber(y), tonumber(radius) or 0
    if x == nil or y == nil or radius < settings.minNoiseRadius then return false end
    now = tonumber(now) or FirstDays.nowMs()
    local list = FirstDays.noises
    local last = list[#list]
    if last ~= nil and last.kind == kind and now >= last.atMs and now - last.lastMs < 400
            and (last.x - x) ^ 2 + (last.y - y) ^ 2 < 9 then
        last.lastMs = now
        return true
    end
    list[#list + 1] = { x = x, y = y, z = tonumber(z) or 0, radius = radius, kind = kind, atMs = now,
        lastMs = now, player = player == true }
    while #list > settings.noiseCap do table.remove(list, 1) end
    FirstDays.metrics.noises = FirstDays.metrics.noises + 1
    return true
end

function FirstDays.noteMark(x, y, z, radius, kind, source)
    if FirstDays.settings.enabled ~= true or kind == "contact" then return false end
    local player = false
    if source ~= nil and type(instanceof) == "function" then
        local ok, is = pcall(instanceof, source, "IsoPlayer")
        player = ok and is == true
    end
    return FirstDays.noteNoise(x, y, z, radius, kind == "shout" and "scream" or "gunfire", player)
end

function FirstDays.hearing(noise)
    local limit = FirstDays.settings.hearTiles[noise.kind] or 60
    return math.min(noise.radius, limit)
end

function FirstDays.heardNoise(shell, mine, now)
    local list = FirstDays.noises
    local settings = FirstDays.settings
    local sx, sy = FirstDays.positionOf(shell)
    if sx == nil then return nil end
    for index = #list, 1, -1 do
        local noise = list[index]
        if now - noise.atMs > settings.noiseKeepMs then return nil end
        if noise.atMs > mine.noiseAtMs and now >= noise.atMs then
            local hear = FirstDays.hearing(noise)
            if (noise.x - sx) ^ 2 + (noise.y - sy) ^ 2 <= hear * hear then return noise end
        end
    end
    return nil
end

function FirstDays.heardRecent(shell, now, windowMs)
    local list = FirstDays.noises
    local sx, sy = FirstDays.positionOf(shell)
    if sx == nil then return nil end
    for index = #list, 1, -1 do
        local noise = list[index]
        if now >= noise.atMs and now - noise.atMs <= windowMs then
            local hear = FirstDays.hearing(noise)
            if (noise.x - sx) ^ 2 + (noise.y - sy) ^ 2 <= hear * hear then return noise.atMs end
        end
    end
    return nil
end

function FirstDays.noteSeen(actor, now)
    if FirstDays.settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return false end
    local state = FirstDays.stateOf(actor.uid)
    state.seenAtMs, state.alarmAtMs = now, now
    return true
end

function FirstDays.memoryMs(level)
    local settings = FirstDays.settings
    local share = (level - settings.idleLevel) / math.max(0.01, 1 - settings.idleLevel)
    return settings.idleMemoryMs + settings.idleMemorySpanMs * math.max(0, math.min(1, share))
end

function FirstDays.idleHold(actor, shell, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return nil end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return nil end
    local level = FirstDays.levelFor(actor, shell, now)
    if level < settings.idleLevel or not FirstDays.moduleOn(actor) then return nil end
    local state = FirstDays.stateOf(actor.uid)
    if state.hide ~= nil and now < state.hide.untilMs then
        FirstDays.metrics.idleSuppressed = FirstDays.metrics.idleSuppressed + 1
        return "panic"
    end
    local window = FirstDays.memoryMs(level)
    local heard = FirstDays.heardRecent(shell, now, window)
    if heard ~= nil and heard > state.alarmAtMs then state.alarmAtMs = heard end
    if now >= state.alarmAtMs and now - state.alarmAtMs <= window then
        FirstDays.metrics.idleSuppressed = FirstDays.metrics.idleSuppressed + 1
        return "panic"
    end
    return nil
end

function FirstDays.alarmed(actor, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    local state = FirstDays.states[actor.uid]
    if state == nil or state.level < settings.idleLevel then return false end
    now = tonumber(now) or FirstDays.nowMs()
    if state.hide ~= nil and now < state.hide.untilMs then return true end
    return now >= state.alarmAtMs and now - state.alarmAtMs <= FirstDays.memoryMs(state.level)
end

function FirstDays.groupAlarmed(members, now)
    if FirstDays.settings.enabled ~= true or type(members) ~= "table" then return false end
    for index = 1, #members do
        if FirstDays.alarmed(members[index], now) then return true end
    end
    return false
end

function FirstDays.refusesLead(actor, shell, mark, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return false end
    if FirstDays.levelFor(actor, shell, now) < settings.startleLevel then return false end
    return not FirstDays.roleOf(actor, now).steady
end

function FirstDays.sceneTopic(actor, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return nil end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return nil end
    local day = FirstDays.clockNow(now)
    if day > settings.sceneMaxDay then return nil end
    local data = ProjectALife.DialogueData
    local pool = data ~= nil and type(data.scenesByTopic) == "table" and data.scenesByTopic.panic_days or nil
    if type(pool) ~= "table" or #pool == 0 then return nil end
    if FirstDays.levelFor(actor, nil, now) < settings.fleeLevel then return nil end
    return "panic_days"
end

function FirstDays.armed(shell)
    local survival = ProjectALife.Survival
    if survival == nil or type(survival.hasFirearm) ~= "function" then return false end
    local ok, armed = pcall(survival.hasFirearm, shell)
    return ok and armed == true
end

function FirstDays.triggerTiles(level, shell)
    local settings = FirstDays.settings
    local tiles = settings.triggerBase + settings.triggerSpan * level
    if FirstDays.armed(shell) then tiles = tiles * settings.armedScale end
    return tiles
end

function FirstDays.insideBuilding(shell)
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.buildingIdAt) ~= "function" then return false end
    local ok, id = pcall(life.buildingIdAt, shell)
    return ok and id ~= nil
end

function FirstDays.squareBuildingOf(body)
    local square = body:getCurrentSquare()
    if square == nil or type(square.getBuilding) ~= "function" then return nil end
    return square:getBuilding()
end

function FirstDays.outside(body)
    if body == nil or type(body.getCurrentSquare) ~= "function" then return true end
    local ok, building = pcall(FirstDays.squareBuildingOf, body)
    if not ok then return true end
    return building == nil
end

function FirstDays.inTrigger(actor, shell, threat, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return false end
    local level = FirstDays.levelFor(actor, shell, now)
    if level < settings.fleeLevel or FirstDays.roleOf(actor, now).steady then return false end
    local distance = FirstDays.flatDistance(shell, threat)
    return distance ~= nil and distance <= FirstDays.triggerTiles(level, shell)
end

function FirstDays.sees(actor, shell, threat, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return false end
    FirstDays.noteSeen(actor, now)
    return FirstDays.inTrigger(actor, shell, threat, now) and FirstDays.eligible(actor, now)
end

function FirstDays.staggerMs(actor, role, level, minimum, span)
    local share = (FirstDays.hash(actor.uid) % 100) / 100
    local scale = FirstDays.stagger[role.temperament] or 1
    return math.floor(minimum + span * share * scale * (0.5 + 0.5 * level))
end

function FirstDays.hideMs(level)
    local settings = FirstDays.settings
    local share = (level - settings.fleeLevel) / math.max(0.01, 1 - settings.fleeLevel)
    return settings.hideMinMs + settings.hideSpanMs * math.max(0, math.min(1, share))
end

function FirstDays.face(shell, x, y)
    if x == nil or y == nil then return false end
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.face) ~= "function" then return false end
    local ok, done = pcall(speech.face, shell, { x = x, y = y })
    return ok and done == true
end

function FirstDays.bark(actor, shell, event, now)
    local settings = FirstDays.settings
    if type(actor) ~= "table" or actor.uid == nil or shell == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    local state = FirstDays.stateOf(actor.uid)
    if now - state.barkAtMs < settings.barkGapMs then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local group = memory.groupId
    if group ~= nil and now - (FirstDays.groupBarkAtMs[group] or -1e12) < settings.groupBarkGapMs then return false end
    local said = false
    local day = FirstDays.clockNow(now)
    local speech = ProjectALife.Speech
    if day <= settings.barkMaxDay and speech ~= nil and type(speech.bark) == "function" then
        local ok, text = pcall(speech.bark, actor, shell, event, {})
        said = ok and type(text) == "string" and text ~= ""
    end
    if not said then
        local voice = ProjectALife.Voice
        if voice ~= nil and type(voice.play) == "function" then
            local ok, played = pcall(voice.play, shell, "PANIC", { urgent = true })
            said = ok and played == true
            if said then FirstDays.metrics.barkFallbacks = FirstDays.metrics.barkFallbacks + 1 end
        end
    end
    if said then
        state.barkAtMs = now
        if group ~= nil then FirstDays.groupBarkAtMs[group] = now end
        FirstDays.metrics.barks = FirstDays.metrics.barks + 1
    end
    return said
end

function FirstDays.holdState(actor, shell, mine, context, now)
    local hide = mine.hide
    if hide ~= nil then FirstDays.face(shell, hide.fromX, hide.fromY) end
    if type(context) == "table" and type(context.setActivity) == "function" then
        context.setActivity(actor, "idle", "panic_hide")
    end
    return { kind = "idle", intent = "panic_hide", cooldownUntilMs = now + FirstDays.settings.holdMs }
end

function FirstDays.beginHide(actor, shell, mine, fromX, fromY, level, context, now, reason)
    local settings = FirstDays.settings
    local length = reason == "open" and settings.openHideMs or FirstDays.hideMs(level)
    mine.hide = { untilMs = now + length, fromX = fromX or mine.fromX, fromY = fromY or mine.fromY,
        atMs = now, reason = reason, arrived = true }
    mine.alarmAtMs = now
    FirstDays.metrics.panicHides = FirstDays.metrics.panicHides + 1
    FirstDays.bark(actor, shell, "PANIC_DAY_HIDE", now)
    return FirstDays.holdState(actor, shell, mine, context, now)
end

function FirstDays.verdict(actor, shell, threat, record, context, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return nil end
    now = tonumber(now) or FirstDays.nowMs()
    if FirstDays.globalLevel(now) <= 0 then return nil end
    local level = FirstDays.levelFor(actor, shell, now)
    if level < settings.fleeLevel then return nil end
    local role = FirstDays.roleOf(actor, now)
    if role.steady then return nil end
    local mine = FirstDays.stateOf(actor.uid)
    mine.seenAtMs, mine.alarmAtMs = now, now
    local distance = FirstDays.flatDistance(shell, threat)
    if distance == nil then return nil end
    local tx, ty = FirstDays.positionOf(threat)
    mine.fromX, mine.fromY = tx, ty
    if distance <= settings.holdTiles then return nil end
    if mine.hide ~= nil and mine.hide.arrived == true and mine.hide.reason ~= "open" and now < mine.hide.untilMs then
        return "hold", FirstDays.holdState(actor, shell, mine, context, now)
    end
    if distance > FirstDays.triggerTiles(level, shell) then return nil end
    if level >= settings.hideLevel and FirstDays.insideBuilding(shell) and FirstDays.outside(threat) then
        return "hold", FirstDays.beginHide(actor, shell, mine, tx, ty, level, context, now, "inside")
    end
    if level >= settings.stareLevel and now - mine.stareAtMs > settings.stareGapMs then
        mine.stareAtMs = now
        local length = FirstDays.staggerMs(actor, role, level, settings.stareMinMs, settings.stareSpanMs)
        FirstDays.face(shell, tx, ty)
        FirstDays.metrics.panicStares = FirstDays.metrics.panicStares + 1
        if type(context) == "table" and type(context.setActivity) == "function" then
            context.setActivity(actor, "idle", "panic_stare")
        end
        return "stare", { kind = "idle", intent = "panic_stare", cooldownUntilMs = now + length }
    end
    return "flee"
end

function FirstDays.pace(actor, pace, nearest, chaser)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return pace end
    local state = FirstDays.states[actor.uid]
    if state == nil or state.level < settings.sprintLevel then return pace end
    if pace == "walk" then return "run" end
    if pace == "run" and (chaser ~= nil or (nearest ~= nil and nearest <= settings.farPace)) then return "sprint" end
    return pace
end

function FirstDays.scatter(actor)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    local state = FirstDays.states[actor.uid]
    if state == nil or state.level < settings.scatterLevel then return false end
    return type(actor.memory) == "table" and actor.memory.groupId ~= nil
end

function FirstDays.sprintMs(actor, base)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return base end
    local state = FirstDays.states[actor.uid]
    if state == nil or state.level < settings.sprintLevel then return base end
    return base + settings.sprintSpanMs * state.level
end

function FirstDays.shelterFor(actor, shell, now, threatX, threatY)
    local settings = FirstDays.settings
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.pickBuilding) ~= "function" or type(life.interiorSpot) ~= "function" then
        return nil
    end
    local ok, id, _, building = pcall(life.pickBuilding, shell, settings.shelterTiles)
    if not ok or id == nil or building == nil then return nil end
    local okSpot, opening, spot = pcall(life.interiorSpot, actor, shell, building, now)
    if not okSpot or opening == nil or type(spot) ~= "table" then return nil end
    local okDeeper, deeper = pcall(FirstDays.deeperSpot, building, opening, spot)
    if okDeeper and type(deeper) == "table" then spot = deeper end
    local sx, sy = FirstDays.positionOf(shell)
    if sx ~= nil and threatX ~= nil and threatY ~= nil then
        local toX, toY = spot.x - sx, spot.y - sy
        local awayX, awayY = sx - threatX, sy - threatY
        local lengthTo, lengthAway = math.sqrt(toX * toX + toY * toY), math.sqrt(awayX * awayX + awayY * awayY)
        if lengthTo > 0.01 and lengthAway > 0.01
                and (toX * awayX + toY * awayY) / (lengthTo * lengthAway) < -0.15 then
            local entrances = ProjectALife.Entrances
            if entrances ~= nil and type(entrances.release) == "function" then pcall(entrances.release, actor.uid) end
            return nil
        end
    end
    return { id = id, spot = spot, opening = opening }
end

function FirstDays.deeperSpot(building, opening, spot)
    if type(getCell) ~= "function" or type(opening) ~= "table" or tonumber(opening.ix) == nil then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local x = math.floor(spot.x + (opening.ix - opening.x))
    local y = math.floor(spot.y + (opening.iy - opening.y))
    local square = cell:getGridSquare(x, y, tonumber(opening.z) or 0)
    if square == nil or type(square.getBuilding) ~= "function" or square:getBuilding() ~= building then return nil end
    if square:isFree(false) ~= true or square:TreatAsSolidFloor() ~= true then return nil end
    return { x = x + 0.5, y = y + 0.5, z = spot.z }
end

function FirstDays.shutDoorAt(traversal, opening)
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local z = tonumber(opening.z) or 0
    local outside = cell:getGridSquare(math.floor(opening.x), math.floor(opening.y), z)
    local inside = cell:getGridSquare(math.floor(opening.ix), math.floor(opening.iy), z)
    if outside == nil or inside == nil or type(outside.getDoorTo) ~= "function" then return false end
    local door = outside:getDoorTo(inside)
    if door == nil or type(door.IsOpen) ~= "function" or door:IsOpen() ~= true then return false end
    if traversal.doorwayClear(door, nil) ~= true then return false end
    return traversal.shutDoor(door, outside) == true
end

function FirstDays.shutEntrance(opening)
    local traversal = ProjectALife.ObstacleTraversal
    if type(opening) ~= "table" or tonumber(opening.ix) == nil or type(getCell) ~= "function" or traversal == nil
            or type(traversal.shutDoor) ~= "function" or type(traversal.doorwayClear) ~= "function" then
        return false
    end
    local ok, shut = pcall(FirstDays.shutDoorAt, traversal, opening)
    if ok and shut == true then
        FirstDays.metrics.doorsShut = FirstDays.metrics.doorsShut + 1
        return true
    end
    return false
end

function FirstDays.fleeDestination(actor, shell, threat, flight, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(flight) ~= "table" or flight.firstDays ~= true then return nil end
    local spot = flight.shelter
    if spot ~= nil then
        if now < (tonumber(flight.shelterUntilMs) or 0) then return { x = spot.x - 0.5, y = spot.y - 0.5, z = spot.z } end
        return nil
    end
    if flight.shelterTried == true then return nil end
    flight.shelterTried = true
    local mine = FirstDays.stateOf(actor.uid)
    if mine.level < settings.hideLevel then return nil end
    local tx, ty = FirstDays.positionOf(threat)
    local found = FirstDays.shelterFor(actor, shell, now, tx, ty)
    if found == nil then return nil end
    flight.shelter, flight.shelterUntilMs, flight.shelterOpening = found.spot, now + settings.shelterMs, found.opening
    return { x = found.spot.x - 0.5, y = found.spot.y - 0.5, z = found.spot.z }
end

function FirstDays.flightLeg(actor, shell, record, scan, context, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(record) ~= "table" then return nil end
    local flight = record.flight
    if type(flight) ~= "table" or flight.firstDays ~= true or flight.shelter == nil then return nil end
    local nearest = type(scan) == "table" and tonumber(scan.nearest) or nil
    if nearest ~= nil and nearest <= settings.holdTiles then return nil end
    local x, y = FirstDays.positionOf(shell)
    local spot = flight.shelter
    if x == nil or (x - spot.x) ^ 2 + (y - spot.y) ^ 2 > settings.arriveTiles * settings.arriveTiles then return nil end
    local mine = FirstDays.stateOf(actor.uid)
    record.flight = nil
    FirstDays.shutEntrance(flight.shelterOpening)
    return FirstDays.beginHide(actor, shell, mine, nil, nil, mine.level, context, now, "shelter")
end

function FirstDays.onFlight(actor, shell, now)
    local mine = FirstDays.stateOf(actor.uid)
    mine.alarmAtMs = now
    FirstDays.metrics.panicFlights = FirstDays.metrics.panicFlights + 1
    local barked = FirstDays.bark(actor, shell, "PANIC_DAY_ZOMBIE", now)
    FirstDays.spread(actor, shell, mine.level, now)
    return barked
end

function FirstDays.awayPoint(shell, noiseX, noiseY)
    local withdraw, fear = ProjectALife.ModuleWithdraw, ProjectALife.ModuleFear
    if withdraw == nil or fear == nil or type(withdraw.rayOut) ~= "function"
            or type(fear.awayBearing) ~= "function" or type(getCell) ~= "function" then return nil end
    local sx, sy, sz = FirstDays.positionOf(shell)
    if sx == nil then return nil end
    local index = fear.awayBearing(sx, sy, noiseX, noiseY, withdraw.bearings)
    if index == nil then return nil end
    local ok, found = pcall(withdraw.rayOut, getCell(), math.floor(sx), math.floor(sy), math.floor(sz), index, 14, 2)
    if ok and type(found) == "table" and found.x ~= nil then
        return { x = found.x + 0.5, y = found.y + 0.5, z = found.z }
    end
    return nil
end

function FirstDays.moduleOn(actor)
    local registry = ProjectALife.ModuleRegistry
    if registry == nil or type(registry.allows) ~= "function" then return true end
    local ok, allowed = pcall(registry.allows, actor, "fear")
    return not ok or allowed == true
end

function FirstDays.eligible(actor, now)
    if not FirstDays.moduleOn(actor) then return false end
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.eligibleActor) ~= "function" then return true end
    local ok, eligible = pcall(fear.eligibleActor, actor, now)
    return ok and eligible == true
end

function FirstDays.alert(actor, shell, noise, mine, context, now)
    local settings = FirstDays.settings
    mine.startleAtMs = now
    FirstDays.face(shell, noise.x, noise.y)
    local data = FirstDays.dataOf(shell)
    if data ~= nil and (data.ProjectALifeDangerPosture == nil or data.ProjectALifeDangerPosture == "relaxed") then
        data.ProjectALifeDangerPosture = "alert"
    end
    FirstDays.metrics.panicAlerts = FirstDays.metrics.panicAlerts + 1
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "panic_alert") end
    return { kind = "idle", intent = "panic_alert", cooldownUntilMs = now + settings.alertMs }
end

function FirstDays.noiseBonus(noise, distance)
    local settings = FirstDays.settings
    local base = settings.noiseOther
    if noise.kind == "gunfire" then base = noise.player and settings.noiseGunPlayer or settings.noiseGunOther end
    return base * (1 - 0.5 * math.min(1, distance / math.max(1, FirstDays.hearing(noise))))
end

function FirstDays.hear(actor, shell, state, context, now)
    local settings = FirstDays.settings
    local mine = FirstDays.stateOf(actor.uid)
    local noise = FirstDays.heardNoise(shell, mine, now)
    if noise == nil then return nil end
    mine.noiseAtMs = noise.atMs
    mine.alarmAtMs = now
    local level = FirstDays.levelFor(actor, shell, now)
    local role = FirstDays.roleOf(actor, now)
    if role.steady then
        if role.alert and level >= settings.alertLevel and now - mine.startleAtMs >= settings.alertGapMs then
            return FirstDays.alert(actor, shell, noise, mine, context, now)
        end
        return nil
    end
    if level < settings.startleLevel or now - mine.startleAtMs < settings.startleGapMs then return nil end
    if not FirstDays.eligible(actor, now) then return nil end
    local sx, sy = FirstDays.positionOf(shell)
    local distance = sx ~= nil and math.sqrt((noise.x - sx) ^ 2 + (noise.y - sy) ^ 2) or 0
    FirstDays.addContagion(actor.uid, FirstDays.noiseBonus(noise, distance), now, settings.noiseWindowMs)
    level = FirstDays.levelFor(actor, shell, now)
    mine.startleAtMs = now
    FirstDays.face(shell, noise.x, noise.y)
    FirstDays.metrics.panicStartles = FirstDays.metrics.panicStartles + 1
    FirstDays.bark(actor, shell, "PANIC_DAY_GUNFIRE", now)
    local length = FirstDays.staggerMs(actor, role, level, settings.startleMinMs, settings.startleSpanMs)
    if level >= settings.hideLevel then mine.pending = { x = noise.x, y = noise.y, kind = noise.kind } end
    mine.startleUntilMs = now + length
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "panic_startle") end
    return { kind = "idle", intent = "panic_startle", cooldownUntilMs = now + length }
end

function FirstDays.fromNoise(actor, shell, mine, pending, context, now)
    local settings = FirstDays.settings
    local level = FirstDays.levelFor(actor, shell, now)
    if FirstDays.insideBuilding(shell) then
        return FirstDays.beginHide(actor, shell, mine, pending.x, pending.y, level, context, now, "inside")
    end
    local found = FirstDays.shelterFor(actor, shell, now, pending.x, pending.y)
    local destination = found ~= nil and found.spot or FirstDays.awayPoint(shell, pending.x, pending.y)
    local started
    if destination ~= nil and type(context.startMovement) == "function" then
        started = context.startMovement(actor, shell, destination, "fear_flee", {
            kind = "movement", activity = "moving", pace = "run", timeoutMs = settings.travelMs, tolerance = 0.8,
        })
    end
    if started == nil then
        return FirstDays.beginHide(actor, shell, mine, pending.x, pending.y, level, context, now, "open")
    end
    local length = found ~= nil and FirstDays.hideMs(level) or settings.openHideMs
    mine.hide = { untilMs = now + settings.travelMs + length, fromX = pending.x, fromY = pending.y,
        atMs = now, reason = found ~= nil and "shelter" or "open", arrived = false,
        opening = found ~= nil and found.opening or nil }
    mine.alarmAtMs = now
    FirstDays.metrics.panicFlights = FirstDays.metrics.panicFlights + 1
    return started
end

function FirstDays.hold(actor, shell, state, mine, context, now)
    local settings = FirstDays.settings
    local hide = mine.hide
    if now >= hide.untilMs then
        mine.hide = nil
        if state.intent == "panic_hide" then
            if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "alerted") end
            return { kind = "idle", intent = "alerted", cooldownUntilMs = now + 300 }
        end
        return nil
    end
    if state.kind == "movement" and state.intent == "fear_flee" then return nil end
    if state.kind ~= "idle" or (state.intent ~= nil and FirstDays.holdIntents[tostring(state.intent)] ~= true) then
        mine.hide = nil
        return nil
    end
    if state.intent == "panic_hide" and now < (tonumber(state.cooldownUntilMs) or 0) - 300 then return nil end
    local caution = ProjectALife.Caution
    local close = false
    if caution ~= nil and type(caution.zombiesNear) == "function" then
        local ok, near = pcall(caution.zombiesNear, shell, now, settings.holdTiles)
        close = ok and near == true
    end
    if close or not FirstDays.eligible(actor, now) then
        mine.hide = nil
        return nil
    end
    if hide.arrived ~= true and hide.opening ~= nil then FirstDays.shutEntrance(hide.opening) end
    hide.arrived = true
    if now - mine.hideBarkAtMs >= settings.hideBarkMs then
        mine.hideBarkAtMs = now
        FirstDays.bark(actor, shell, "PANIC_DAY_HIDE", now)
    end
    return FirstDays.holdState(actor, shell, mine, context, now)
end

function FirstDays.step(actor, shell, state, context)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil or type(state) ~= "table"
            or type(context) ~= "table" then return nil end
    local kind = state.kind
    if kind ~= "idle" and kind ~= "movement" and kind ~= "scavenging" then return nil end
    local now = tonumber(context.now) or FirstDays.nowMs()
    local mine = FirstDays.states[actor.uid]
    if mine ~= nil and mine.hide ~= nil then
        local held = FirstDays.hold(actor, shell, state, mine, context, now)
        if held ~= nil then return held end
    end
    if mine ~= nil and mine.pending ~= nil and now >= mine.startleUntilMs then
        local pending = mine.pending
        mine.pending = nil
        FirstDays.release(context, actor, state)
        return FirstDays.fromNoise(actor, shell, mine, pending, context, now)
    end
    if #FirstDays.noises == 0 or FirstDays.globalLevel(now) <= 0 then return nil end
    local heard = FirstDays.hear(actor, shell, state, context, now)
    if heard ~= nil then FirstDays.release(context, actor, state) end
    return heard
end

function FirstDays.release(context, actor, state)
    if type(context.clear) == "function" then context.clear(actor, state) end
end

function FirstDays.busy(actor, now)
    local settings = FirstDays.settings
    if settings.enabled ~= true or type(actor) ~= "table" or actor.uid == nil then return false end
    now = tonumber(now) or FirstDays.nowMs()
    local mine = FirstDays.states[actor.uid]
    if mine ~= nil and (mine.hide ~= nil or mine.pending ~= nil) then return true end
    local newest = FirstDays.noises[#FirstDays.noises]
    if newest == nil then return false end
    if now - newest.atMs > settings.noiseKeepMs then
        FirstDays.noises = {}
        return false
    end
    return FirstDays.globalLevel(now) > 0
end

return FirstDays
