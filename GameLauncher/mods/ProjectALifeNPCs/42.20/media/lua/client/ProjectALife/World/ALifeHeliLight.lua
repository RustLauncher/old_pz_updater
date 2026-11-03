require "ProjectALife/World/ALifeHeliSearch"
require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local Heli = ProjectALife.HeliSearch

local Light = {
    state = nil,
    settings = {
        relocateMs = 220, easePerSecond = 6, staleMs = 6000, viewRange = 220, jumpTiles = 25,
        daylight = 0.85, color = { 1.0, 0.95, 0.84 }, minRadius = 3,
        spokes = 6, spokeAlpha = 0.07, coreAlpha = 0.16, flareAlpha = 0.55, beamShrink = 0.9,
    },
    metrics = { syncs = 0, ignored = 0, relocations = 0, roofed = 0, beams = 0, tells = 0, stops = 0 },
}
ProjectALife.HeliLight = Light

function Light.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Light.localPlayers()
    local out = {}
    pcall(function()
        local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
        for index = 0, math.max(1, tonumber(count) or 1) - 1 do
            local subject = getSpecificPlayer(index)
            if subject ~= nil then out[#out + 1] = subject end
        end
    end)
    return out
end

function Light.near(x, y)
    local limit = Light.settings.viewRange * Light.settings.viewRange
    for _, subject in ipairs(Light.localPlayers()) do
        local dx, dy = subject:getX() - x, subject:getY() - y
        if dx * dx + dy * dy <= limit then return true end
    end
    return false
end

function Light.removeLight(state)
    if state == nil or state.light == nil then return end
    pcall(function() getCell():removeLamppost(state.light) end)
    state.light = nil
end

function Light.stop()
    local state = Light.state
    if state == nil then return false end
    Light.removeLight(state)
    Light.state = nil
    Light.metrics.stops = Light.metrics.stops + 1
    return true
end

function Light.tell(key)
    for _, subject in ipairs(Light.localPlayers()) do
        local name
        pcall(function() name = subject:getUsername() end)
        if name ~= nil and name == key then
            Light.metrics.tells = Light.metrics.tells + 1
            pcall(function()
                subject:addLineChatElement(ProjectALife.Text.ui("Oh no- the light is on me!!"), 1.0, 0.6, 0.45)
            end)
        end
    end
end

function Light.apply(snapshot)
    if type(snapshot) ~= "table" or snapshot.id == nil or tonumber(snapshot.x) == nil then return false end
    if not Light.near(snapshot.x, snapshot.y) then
        Light.metrics.ignored = Light.metrics.ignored + 1
        if Light.state ~= nil and Light.state.id == snapshot.id then Light.stop() end
        return false
    end
    local now = Light.nowMs()
    local state = Light.state
    if state == nil or state.id ~= snapshot.id then
        Light.stop()
        state = { id = snapshot.id, dx = snapshot.x, dy = snapshot.y, key = "", lastTickMs = now, lightAtMs = 0 }
        Light.state = state
    end
    if snapshot.k ~= nil and snapshot.k ~= "" and snapshot.k ~= state.key then Light.tell(snapshot.k) end
    state.key = snapshot.k or ""
    state.snapshot = snapshot
    state.receivedMs = now
    Light.metrics.syncs = Light.metrics.syncs + 1
    return true
end

function Light.finish(id)
    local state = Light.state
    if state == nil or (id ~= nil and state.id ~= tostring(id)) then return false end
    return Light.stop()
end

function Light.dayLight()
    local strength = 0
    pcall(function() strength = getClimateManager():getDayLightStrength() end)
    return strength
end

function Light.place(state, now)
    local snapshot = state.snapshot
    local bright = tonumber(snapshot.b) or 0
    if bright < 0.05 or Light.dayLight() > Light.settings.daylight then
        Light.removeLight(state)
        state.roofed = true
        return
    end
    local tx, ty, tz = math.floor(state.dx), math.floor(state.dy), math.floor(tonumber(snapshot.z) or 0)
    local roofed = true
    pcall(function()
        local square = getCell():getGridSquare(tx, ty, tz)
        roofed = square == nil or not square:isOutside()
    end)
    if roofed then
        if state.roofed ~= true then Light.metrics.roofed = Light.metrics.roofed + 1 end
        state.roofed = true
        Light.removeLight(state)
        return
    end
    state.roofed = false
    local radius = math.max(Light.settings.minRadius, math.floor((tonumber(snapshot.r) or 11) * (0.75 + 0.25 * bright)))
    local level = math.floor(bright * 10)
    if state.light ~= nil and state.lx == tx and state.ly == ty and state.lz == tz
            and state.lradius == radius and state.llevel == level then
        return
    end
    if state.light ~= nil and now - state.lightAtMs < Light.settings.relocateMs and state.llevel == level then return end
    if IsoLightSource == nil then return end
    Light.removeLight(state)
    local scale = 0.3 + 0.7 * (level / 10)
    local color = Light.settings.color
    local placed = pcall(function()
        local light = IsoLightSource.new(tx, ty, tz, color[1] * scale, color[2] * scale, color[3] * scale, radius)
        getCell():addLamppost(light)
        state.light = light
    end)
    if placed and state.light ~= nil then
        state.lx, state.ly, state.lz, state.lradius, state.llevel, state.lightAtMs = tx, ty, tz, radius, level, now
        Light.metrics.relocations = Light.metrics.relocations + 1
    end
end

function Light.tick()
    local state = Light.state
    if state == nil then return end
    local now = Light.nowMs()
    local snapshot = state.snapshot
    if snapshot == nil or now - state.receivedMs > Light.settings.staleMs then
        Light.stop()
        return
    end
    local tx, ty = Heli.extrapolate(snapshot, (now - state.receivedMs) / 1000)
    local dt = Heli.clamp((now - state.lastTickMs) / 1000, 0, 0.25)
    state.lastTickMs = now
    if Heli.dist(state.dx, state.dy, tx, ty) > Light.settings.jumpTiles then
        state.dx, state.dy = tx, ty
    else
        local ease = Heli.clamp(dt * Light.settings.easePerSecond, 0, 1)
        state.dx = state.dx + (tx - state.dx) * ease
        state.dy = state.dy + (ty - state.dy) * ease
    end
    Light.place(state, now)
    local outside = false
    pcall(function()
        local subject = getSpecificPlayer(0)
        local square = subject ~= nil and subject:getSquare() or nil
        outside = square ~= nil and square:isOutside() == true and subject:getBuilding() == nil
    end)
    state.listenerOutside = outside
end

function Light.render()
    local state = Light.state
    if state == nil or state.roofed ~= false or state.light == nil or state.listenerOutside ~= true then return end
    local tracer = ProjectALife.Tracer
    if tracer == nil then return end
    local snapshot = state.snapshot
    local settings = Light.settings
    pcall(function()
        local tile = tracer.whiteTile()
        if tile == nil then return end
        local zoom = tracer.viewZoom()
        local renderer = getRenderer()
        local z = state.lz or 0
        local ax, ay, az = Heli.apex(snapshot, state.dx, state.dy)
        local topX, topY = tracer.screenPoint(ax, ay, az, zoom)
        local bright = tonumber(snapshot.b) or 1
        local c = settings.color
        local reach = (tonumber(snapshot.r) or 11) * Heli.settings.beamFraction * settings.beamShrink
        for index = 0, settings.spokes - 1 do
            local angle = index * 2 * math.pi / settings.spokes
            local px, py = state.dx + math.cos(angle) * reach, state.dy + math.sin(angle) * reach
            local sx, sy = tracer.screenPoint(px, py, z, zoom)
            renderer:renderline(tile, topX, topY, sx, sy, c[1], c[2], c[3], settings.spokeAlpha * bright)
        end
        local cx, cy = tracer.screenPoint(state.dx, state.dy, z, zoom)
        renderer:renderline(tile, topX, topY, cx, cy, c[1], c[2], c[3], settings.coreAlpha * bright)
        renderer:renderline(tile, topX - 3, topY, topX + 3, topY, 1, 1, 1, settings.flareAlpha * bright)
        renderer:renderline(tile, topX, topY - 3, topX, topY + 3, 1, 1, 1, settings.flareAlpha * bright)
        Light.metrics.beams = Light.metrics.beams + 1
    end)
end

if type(Events) == "table" then
    if Events.OnTick ~= nil then Events.OnTick.Add(Light.tick) end
    if Events.OnPreUIDraw ~= nil then Events.OnPreUIDraw.Add(Light.render) end
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(Light.stop) end
    if Events.OnPlayerDeath ~= nil then Events.OnPlayerDeath.Add(Light.stop) end
    if Events.OnDisconnect ~= nil then Events.OnDisconnect.Add(Light.stop) end
end

return Light
