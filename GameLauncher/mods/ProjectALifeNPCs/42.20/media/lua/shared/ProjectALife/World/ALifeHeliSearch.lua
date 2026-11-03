ProjectALife = ProjectALife or {}

local Heli = {
    enabled = true,
    settings = {
        arriveSpeed = 11, searchSpeed = 4.2, convergeSpeed = 7.5, trackSpeed = 8.5, leaveSpeed = 14,
        accel = 5, turnSearch = 42, turnFast = 110,
        legTiles = 18, areaStart = 28, areaMax = 75, areaGrowS = 90, cellTiles = 12,
        radius = 11, brightness = 1, beamFraction = 0.75, lockHysteresis = 1.3,
        spotSeconds = 2.6, decayPerSecond = 0.45, loseSeconds = 7,
        sneakFactor = 0.5, runFactor = 1.4, stillFactor = 0.8, canopyFactor = 0.55,
        arriveRadius = 8, fadeSeconds = 4, interestRadius = 90, interestHoldS = 14,
        interestGapS = 10, siteEveryS = 30, siteRadius = 80, noiseEveryS = 18,
    },
    flights = {},
    metrics = { started = 0, ended = 0, spotted = 0, lost = 0, cues = 0, sites = 0, syncs = 0,
        reactions = 0, hiddenOverRoof = 0, cleared = 0 },
}
ProjectALife.HeliSearch = Heli

function Heli.clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function Heli.dist(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

function Heli.angle(dy, dx)
    if type(math.atan2) == "function" then return math.atan2(dy, dx) end
    return math.atan(dy, dx)
end

function Heli.wrap(angle)
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    return angle
end

function Heli.rand(flight)
    flight.seed = (flight.seed * 16807) % 2147483647
    return flight.seed / 2147483647
end

function Heli.configure(options)
    options = options or {}
    if options.enabled ~= nil then Heli.enabled = options.enabled ~= false end
    local settings = Heli.settings
    if tonumber(options.radius) ~= nil then settings.radius = Heli.clamp(options.radius, 4, 24) end
    if tonumber(options.brightness) ~= nil then settings.brightness = Heli.clamp(options.brightness, 0.2, 1) end
    return true
end

function Heli.reset()
    Heli.flights = {}
    Heli.metrics = { started = 0, ended = 0, spotted = 0, lost = 0, cues = 0, sites = 0, syncs = 0,
        reactions = 0, hiddenOverRoof = 0, cleared = 0 }
end

function Heli.beamRadius(flight)
    return flight.radius * Heli.settings.beamFraction
end

function Heli.areaRadius(flight)
    local settings = Heli.settings
    local grown = Heli.clamp(flight.searchT / settings.areaGrowS, 0, 1)
    return settings.areaStart + (settings.areaMax - settings.areaStart) * grown
end

function Heli.start(spec)
    if type(spec) ~= "table" or spec.id == nil then return nil end
    local settings = Heli.settings
    local ax, ay = tonumber(spec.anchorX) or 0, tonumber(spec.anchorY) or 0
    local sx, sy = tonumber(spec.startX) or ax, tonumber(spec.startY) or ay
    local seed = math.floor(math.abs(tonumber(spec.seed) or 1)) % 2147483646 + 1
    local flight = {
        id = tostring(spec.id), seed = seed, phase = "arriving", t = 0, searchT = 0, fade = 0,
        durationS = Heli.clamp(spec.durationS, 5, 600),
        x = sx, y = sy, z = 0, anchorX = ax, anchorY = ay, baseX = ax, baseY = ay,
        waypointX = ax, waypointY = ay, speed = settings.arriveSpeed * 0.6, vx = 0, vy = 0,
        radius = Heli.clamp(spec.radius or settings.radius, 4, 24),
        bright = Heli.clamp(spec.brightness or settings.brightness, 0.2, 1),
        groupId = spec.groupId, factionId = spec.factionId, targetKey = spec.targetKey,
        visited = {}, visitedCount = 0, exposure = {}, events = {}, sites = {}, siteSeen = {},
        spotted = 0, lostFor = 0, nextSiteT = settings.siteEveryS, nextNoiseT = 0,
        lastX = ax, lastY = ay,
    }
    local length = Heli.dist(sx, sy, ax, ay)
    if length > 0.01 then flight.heading = Heli.angle(ay - sy, ax - sx)
    else flight.heading = Heli.rand(flight) * 2 * math.pi end
    flight.vx, flight.vy = math.cos(flight.heading) * flight.speed, math.sin(flight.heading) * flight.speed
    Heli.flights[flight.id] = flight
    Heli.metrics.started = Heli.metrics.started + 1
    return flight
end

function Heli.push(flight, event)
    flight.events[#flight.events + 1] = event
    return event
end

function Heli.setPhase(flight, phase)
    if flight.phase == phase then return end
    flight.phase = phase
    Heli.push(flight, { kind = "phase", phase = phase })
end

function Heli.exposureRate(flight, target, radius)
    if target.outdoors ~= true or target.covered == true then return 0, nil end
    local settings = Heli.settings
    local d = Heli.dist(flight.x, flight.y, target.x, target.y)
    if d > radius then return 0, d end
    local edge = Heli.clamp((d - 0.45 * radius) / (0.55 * radius), 0, 1)
    local stance = settings.stillFactor
    if target.running == true then stance = settings.runFactor
    elseif target.sneaking == true then stance = settings.sneakFactor
    elseif target.moving == true then stance = 1 end
    local cover = target.canopy == true and settings.canopyFactor or 1
    return (1 / settings.spotSeconds) * stance * cover * (1 - 0.5 * edge), d
end

function Heli.lock(flight, target)
    flight.lockKey = target.key
    flight.lostFor = 0
    flight.lastX, flight.lastY, flight.z = target.x, target.y, target.z or 0
    flight.interest = nil
    flight.spotted = flight.spotted + 1
    Heli.metrics.spotted = Heli.metrics.spotted + 1
    Heli.setPhase(flight, "tracking")
    Heli.push(flight, { kind = "spotted", key = target.key, x = target.x, y = target.y, z = target.z or 0 })
end

function Heli.unlock(flight, why)
    local key = flight.lockKey
    flight.lockKey = nil
    if key ~= nil then flight.exposure[key] = 0 end
    flight.lostFor = 0
    flight.baseX, flight.baseY = flight.lastX, flight.lastY
    flight.searchT = 0
    flight.z = 0
    Heli.metrics.lost = Heli.metrics.lost + 1
    Heli.push(flight, { kind = "lost", key = key, reason = why, x = flight.lastX, y = flight.lastY })
    if flight.phase ~= "leaving" then Heli.setPhase(flight, "searching") end
end

function Heli.observe(flight, dt, world)
    if flight.phase == "leaving" then return end
    local settings = Heli.settings
    local targets = world.targets or {}
    local radius = Heli.beamRadius(flight)
    local best, bestExposure
    local locked
    for index = 1, #targets do
        local target = targets[index]
        local key = target.key
        if key ~= nil then
            if flight.lockKey == key then
                locked = target
            else
                local rate = Heli.exposureRate(flight, target, radius)
                local exposure = flight.exposure[key] or 0
                if rate > 0 then exposure = math.min(1.25, exposure + rate * dt)
                else exposure = math.max(0, exposure - settings.decayPerSecond * dt) end
                flight.exposure[key] = exposure
                if flight.lockKey == nil and exposure >= 1 and (best == nil or exposure > bestExposure) then
                    best, bestExposure = target, exposure
                end
            end
        end
    end
    if flight.lockKey ~= nil then
        if locked == nil then
            Heli.unlock(flight, "gone")
            return
        end
        local rate = Heli.exposureRate(flight, locked, radius * settings.lockHysteresis)
        if rate > 0 then
            flight.lostFor = 0
            flight.lastX, flight.lastY, flight.z = locked.x, locked.y, locked.z or 0
        else
            flight.lostFor = flight.lostFor + dt
            if flight.lostFor >= settings.loseSeconds then Heli.unlock(flight, "hidden") end
        end
    elseif best ~= nil then
        Heli.lock(flight, best)
    end
end

function Heli.cue(flight, x, y, kind)
    if flight == nil or flight.done or flight.phase == "leaving" or flight.lockKey ~= nil then return false end
    local settings = Heli.settings
    if Heli.dist(x, y, flight.baseX, flight.baseY) > settings.interestRadius then return false end
    local held = flight.interest
    if held ~= nil and flight.t < held.untilT - settings.interestHoldS + settings.interestGapS
            and Heli.dist(x, y, held.x, held.y) < 12 then
        return false
    end
    flight.interest = { x = x, y = y, kind = kind or "noise", untilT = flight.t + settings.interestHoldS }
    Heli.metrics.cues = Heli.metrics.cues + 1
    Heli.setPhase(flight, "converging")
    Heli.push(flight, { kind = "cue", cue = flight.interest.kind, x = x, y = y })
    return true
end

function Heli.cell(flight, x, y)
    local size = Heli.settings.cellTiles
    return math.floor(x / size) .. ":" .. math.floor(y / size)
end

function Heli.chooseWaypoint(flight, world)
    local settings = Heli.settings
    local offsets = { 0, -25, 25, -50, 50, -80, 80 }
    local area = Heli.areaRadius(flight)
    local best, bestScore
    for index = 1, #offsets do
        local offset = offsets[index]
        local heading = flight.heading + math.rad(offset)
        local px = flight.x + math.cos(heading) * settings.legTiles
        local py = flight.y + math.sin(heading) * settings.legTiles
        local score = -(math.abs(offset) / 90) * 0.7 + Heli.rand(flight) * 0.5
        local away = Heli.dist(px, py, flight.baseX, flight.baseY)
        if away > area then score = score - 3 - (away - area) / 10
        else score = score + 0.6 * (1 - away / area) end
        if flight.visited[Heli.cell(flight, px, py)] then score = score - 1.6 else score = score + 0.6 end
        if type(world.isRoad) == "function" then
            if world.isRoad(px, py) == true then score = score + 2.2 end
            if world.isRoad((px + flight.x) / 2, (py + flight.y) / 2) == true then score = score + 1 end
        end
        if bestScore == nil or score > bestScore then best, bestScore = { x = px, y = py, heading = heading }, score end
    end
    if flight.visitedCount > 64 then flight.visited, flight.visitedCount = {}, 0 end
    local cellKey = Heli.cell(flight, best.x, best.y)
    if not flight.visited[cellKey] then flight.visited[cellKey] = true; flight.visitedCount = flight.visitedCount + 1 end
    flight.waypointX, flight.waypointY = best.x, best.y
    return best
end

function Heli.nextSite(flight)
    local settings = Heli.settings
    local best, bestD
    for index = 1, #flight.sites do
        local site = flight.sites[index]
        if not flight.siteSeen[site.id] then
            local d = Heli.dist(site.x, site.y, flight.baseX, flight.baseY)
            if d <= settings.siteRadius and (bestD == nil or d < bestD) then best, bestD = site, d end
        end
    end
    return best
end

function Heli.aim(flight, world)
    local settings = Heli.settings
    local phase = flight.phase
    if phase == "tracking" then
        flight.waypointX, flight.waypointY = flight.lastX, flight.lastY
    elseif phase == "arriving" then
        flight.waypointX, flight.waypointY = flight.anchorX, flight.anchorY
        if Heli.dist(flight.x, flight.y, flight.anchorX, flight.anchorY) <= settings.arriveRadius then
            Heli.setPhase(flight, "searching")
        end
    elseif phase == "converging" then
        local interest = flight.interest
        if interest == nil or flight.t >= interest.untilT then
            flight.interest = nil
            Heli.setPhase(flight, "searching")
        else
            flight.waypointX, flight.waypointY = interest.x, interest.y
            if Heli.dist(flight.x, flight.y, interest.x, interest.y) <= settings.arriveRadius then
                flight.baseX, flight.baseY, flight.searchT = interest.x, interest.y, 0
                flight.interest = nil
                Heli.setPhase(flight, "searching")
            end
        end
    elseif phase == "leaving" then
        flight.waypointX = flight.x + math.cos(flight.heading) * 300
        flight.waypointY = flight.y + math.sin(flight.heading) * 300
    end
    if flight.phase == "searching" then
        if flight.t >= flight.nextSiteT then
            flight.nextSiteT = flight.t + settings.siteEveryS
            local site = Heli.nextSite(flight)
            if site ~= nil then
                flight.siteSeen[site.id] = true
                Heli.metrics.sites = Heli.metrics.sites + 1
                Heli.cue(flight, site.x, site.y, "site")
                return
            end
        end
        local reached = Heli.dist(flight.x, flight.y, flight.waypointX, flight.waypointY)
            <= math.max(2.5, flight.speed * 0.5)
        if reached or flight.leg == nil then
            flight.leg = true
            Heli.chooseWaypoint(flight, world)
        end
    end
end

function Heli.move(flight, dt)
    local settings = Heli.settings
    local phase = flight.phase
    local dx, dy = flight.waypointX - flight.x, flight.waypointY - flight.y
    local length = math.sqrt(dx * dx + dy * dy)
    if phase == "tracking" then
        local want = flight.lostFor > 0 and 0.8 or math.min(settings.trackSpeed, 1.2 + length * 1.6)
        flight.speed = want
        local step = math.min(length, want * dt)
        if length > 0.01 then
            flight.heading = Heli.angle(dy, dx)
            flight.x = flight.x + dx / length * step
            flight.y = flight.y + dy / length * step
        end
        flight.vx, flight.vy = math.cos(flight.heading) * want * (length > 0.3 and 1 or 0),
            math.sin(flight.heading) * want * (length > 0.3 and 1 or 0)
        return
    end
    local want, turn = settings.searchSpeed, settings.turnSearch
    if phase == "arriving" then want, turn = settings.arriveSpeed, settings.turnFast
    elseif phase == "converging" then want, turn = settings.convergeSpeed, settings.turnFast
    elseif phase == "leaving" then want, turn = settings.leaveSpeed, settings.turnFast end
    if length > 0.01 then
        local diff = Heli.wrap(Heli.angle(dy, dx) - flight.heading)
        local step = math.rad(turn) * dt
        flight.heading = flight.heading + Heli.clamp(diff, -step, step)
    end
    local change = settings.accel * dt
    flight.speed = flight.speed + Heli.clamp(want - flight.speed, -change, change)
    flight.vx, flight.vy = math.cos(flight.heading) * flight.speed, math.sin(flight.heading) * flight.speed
    flight.x = flight.x + flight.vx * dt
    flight.y = flight.y + flight.vy * dt
end

function Heli.advance(flight, dt, world)
    if flight == nil then return {} end
    flight.events = {}
    if flight.done then return flight.events end
    dt = Heli.clamp(dt, 0, 1)
    world = world or {}
    flight.t = flight.t + dt
    if flight.phase == "searching" then flight.searchT = flight.searchT + dt end
    if flight.phase ~= "leaving" and flight.t >= flight.durationS then
        if flight.lockKey ~= nil then Heli.unlock(flight, "ended") end
        Heli.setPhase(flight, "leaving")
    end
    Heli.observe(flight, dt, world)
    Heli.aim(flight, world)
    Heli.move(flight, dt)
    if flight.phase == "leaving" then
        flight.fade = flight.fade + dt
        if flight.fade >= Heli.settings.fadeSeconds then
            flight.done = true
            Heli.metrics.ended = Heli.metrics.ended + 1
            Heli.push(flight, { kind = "ended" })
        end
    end
    return flight.events
end

function Heli.brightness(flight)
    local fade = 1 - Heli.clamp(flight.fade / Heli.settings.fadeSeconds, 0, 1)
    return flight.bright * fade
end

function Heli.snapshot(flight)
    return {
        id = flight.id, x = flight.x, y = flight.y, z = flight.z, vx = flight.vx, vy = flight.vy,
        h = flight.heading, ph = flight.phase, r = flight.radius, b = Heli.brightness(flight),
        k = flight.lockKey or "", n = flight.spotted, d = flight.durationS, t = flight.t,
    }
end

function Heli.extrapolate(snapshot, ageS)
    local age = Heli.clamp(ageS, 0, 1.5)
    return snapshot.x + (snapshot.vx or 0) * age, snapshot.y + (snapshot.vy or 0) * age
end

function Heli.apex(snapshot, x, y)
    local heading = tonumber(snapshot.h) or 0
    return x - math.cos(heading) * 9, y - math.sin(heading) * 9, (tonumber(snapshot.z) or 0) + 4
end

function Heli.litAt(x, y, z, actor, margin)
    for _, flight in pairs(Heli.flights) do
        if not flight.done and flight.phase ~= "leaving" and Heli.brightness(flight) > 0.3
                and math.abs((tonumber(z) or 0) - (flight.z or 0)) < 1.5 then
            local friendly = actor ~= nil and flight.factionId ~= nil and actor.factionId == flight.factionId
            if not friendly then
                local d = Heli.dist(flight.x, flight.y, x, y)
                if d <= Heli.beamRadius(flight) + (tonumber(margin) or 0) then return flight, d end
            end
        end
    end
    return nil
end

function Heli.stop(id)
    local flight = Heli.flights[tostring(id)]
    if flight == nil then return false end
    Heli.flights[tostring(id)] = nil
    Heli.metrics.cleared = Heli.metrics.cleared + 1
    return true
end

return Heli
