require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Interop = ProjectALife.Interop

local Tracer = {
    enabled = false,
    configured = false,
    flashEnabled = true,
    flashConfigured = false,
    settings = {
        capacity = 48,
        speed = 75,
        range = 32,
        streak = 3,
        muzzle = 0.55,
        height = 0.45,
        jitter = 1.1,
        cone = 7,
        alpha = 0.5,
        color = { 1, 1, 1 },
        flashCapacity = 24,
        flashMs = 85,
        flashLength = 0.75,
        flashColor = { 1.0, 0.8, 0.42 },
        coreColor = { 1.0, 0.96, 0.84 },
        tilePx = 42,
        atlas = 256,
        flashStyle = "atlas",
        additive = true,
        additiveAlpha = 0.008,
        dayDim = 0.3,
        glowDayDim = 0.7,
        glowGain = 0.9,
        starGain = 1.0,
        tongueGain = 1.0,
        coreGain = 1.0,
        coreBase = 0.5,
        coreScale = 0.25,
        cullMargin = 200,
        tongueAlpha = 0.9,
        minGlowPx = 5,
        minStarPx = 3,
        growStart = 0.8,
        growSpan = 0.35,
        holdFraction = 0.3,
        textureRetryMs = 5000,
        puffCapacity = 12,
        puffMs = 420,
        puffMinScale = 0.6,
        puffAlpha = 0.2,
        puffDrift = 0.7,
        puffRise = 0.25,
        seeRadius = 2.5,
        lightGapMs = 110,
        lightBurst = 4,
        lightWindowMs = 100,
        lightRange = 45,
        lightLife = 2,
        daylight = 0.7,
        brassDelayMs = 320,
        pendingCap = 24,
    },
    rounds = {},
    head = 0,
    flashes = {},
    flashHead = 0,
    puffs = {},
    puffHead = 0,
    fx = {},
    fxRetry = {},
    listeners = {},
    pending = {},
    lightAt = {},
    lightSeen = 0,
    lightWindow = 0,
    lightCount = 0,
    suppress2D = false,
    px = 42,
    originX = 0,
    originY = 0,
    viewRect = { -1e9, -1e9, 1e9, 1e9 },
}
ProjectALife.Tracer = Tracer

function Tracer.set2D(enabled)
    if type(enabled) ~= "boolean" then return false end
    Tracer.suppress2D = not enabled
    return true
end

function Tracer.shotText(value, uid)
    if type(value) ~= "string" or value == "" or #value > 64 then return nil end
    local pattern = "[^%w_%.%-]"
    if uid == true then pattern = "[^%w_%.%-%:]" end
    if string.find(value, pattern) then return nil end
    return value
end

function Tracer.publish(round, context, remote, index)
    if type(context) ~= "table" then context = {} end
    local shot = {
        x = round.x, y = round.y, z = round.z,
        dx = round.dx, dy = round.dy, born = round.born,
        weapon = Tracer.shotText(context.weapon, false),
        owner = Tracer.shotText(context.owner, true),
        remote = remote == true,
        suppressed = context.sp == 1,
        flash = index == 1 and Tracer.flashEnabled and context.sp ~= 1
            and (tonumber(context.fl) or 10) > 0,
    }
    Interop.emit("ProjectALife_Shot", shot)
end

Tracer.rays = {
    { 0, 1.0, 1.0 },
    { 24, 0.55, 0.7 },
    { -24, 0.55, 0.7 },
    { 55, 0.32, 0.5 },
    { -55, 0.32, 0.5 },
    { 180, 0.16, 0.4 },
}

Tracer.fxFiles = {
    flash = "media/textures/ProjectALife/MuzzleFlash.png",
    spark = "media/textures/FireSparksFlare.png",
    smoke = "media/textures/FireSmokes.png",
    tongue1 = "media/textures/weapons/firearm/fx/muzzle_flash_01.png",
    tongue2 = "media/textures/weapons/firearm/fx/muzzle_flash_02.png",
    tongue3 = "media/textures/weapons/firearm/fx/muzzle_flash_03.png",
    tongue5 = "media/textures/weapons/firearm/fx/muzzle_flash_05.png",
}

Tracer.fxSize = { flash = 512 }

Tracer.regionSets = {
    atlas = {
        glow = { "flash", 384, 256, 128, 128 },
        core = { "flash", 384, 384, 128, 128 },
        starA = { "flash", 0, 0, 256, 256 },
        starB = { "flash", 256, 0, 256, 256 },
        pistolA = { "flash", 0, 256, 128, 256 },
        pistolB = { "flash", 128, 256, 128, 256 },
        rifleA = { "flash", 0, 256, 128, 256 },
        rifleB = { "flash", 128, 256, 128, 256 },
        shotgunA = { "flash", 256, 256, 128, 256 },
    },
    vanilla = {
        glow = { "spark", 134, 6, 112, 112 },
        starA = { "spark", 128, 128, 128, 128 },
        starB = { "spark", 0, 128, 128, 128 },
        smokeA = { "smoke", 0, 128, 128, 128 },
        smokeB = { "smoke", 128, 128, 128, 128 },
        pistolA = { "tongue1", 26, 88, 32, 60 },
        pistolB = { "tongue5", 24, 86, 38, 76 },
        rifleA = { "tongue2", 22, 86, 38, 112 },
        rifleB = { "tongue5", 24, 86, 38, 76 },
        shotgunA = { "tongue3", 8, 84, 62, 128 },
    },
}

Tracer.styles = {
    atlas = { tongueAdditive = true, core = true, lengthGain = 2.0, widthGain = 1.45,
        glowTint = { 1, 0.92, 0.78 }, starTint = { 1, 0.96, 0.86 }, tongueTint = { 1, 0.95, 0.82 },
        coreTint = { 1, 1, 0.95 } },
    vanilla = { tongueAdditive = false, core = false, lengthGain = 1.0, widthGain = 1.0,
        glowTint = { 1, 0.86, 0.62 }, starTint = { 1, 0.9, 0.7 }, tongueTint = { 1, 1, 1 },
        coreTint = { 1, 1, 1 } },
}

Tracer.shapes = {
    pistol = { dur = 55, length = 0.62, widen = 1.0, star = 0.95, glow = 1.3, lift = 0, puff = 0.7,
        fork = false, tongues = { "pistolA", "pistolB" } },
    rifle = { dur = 65, length = 0.95, widen = 0.9, star = 1.1, glow = 1.5, lift = 0.04, puff = 1.0,
        fork = false, tongues = { "rifleA", "rifleB" } },
    shotgun = { dur = 72, length = 0.8, widen = 1.1, star = 1.35, glow = 1.8, lift = 0.04, puff = 1.4,
        fork = true, tongues = { "shotgunA" } },
}
Tracer.starRegions = { "starA", "starB" }
Tracer.puffRegions = { "smokeA", "smokeB" }
Tracer.forkDegrees = 16

local function nowMs()
    if type(getTimestampMs) ~= "function" then return 0 end
    return tonumber(getTimestampMs()) or 0
end

function Tracer.configure(options)
    options = options or {}
    if options.enabled ~= nil then
        Tracer.enabled = options.enabled == true
        Tracer.configured = true
    end
    if options.flash ~= nil then
        Tracer.flashEnabled = options.flash == true
        Tracer.flashConfigured = true
    end
    if not Tracer.enabled then Tracer.clearRounds() end
    if not Tracer.flashEnabled then Tracer.clearFlashes() end
    return true
end

function Tracer.syncFromSandbox()
    if not Tracer.configured then
        local value
        pcall(function() value = SandboxVars.ALife.Combat_VisibleTracers end)
        if value ~= nil then
            Tracer.enabled = value == true
            Tracer.configured = true
        end
    end
    if not Tracer.flashConfigured then
        local value
        pcall(function() value = SandboxVars.ALife.Combat_MuzzleFlash end)
        if value ~= nil then
            Tracer.flashEnabled = value == true
            Tracer.flashConfigured = true
        end
    end
end

function Tracer.clearRounds()
    Tracer.rounds, Tracer.head = {}, 0
end

function Tracer.clearFlashes()
    for _, flash in pairs(Tracer.flashes) do flash.alive = false end
    for _, puff in pairs(Tracer.puffs) do puff.alive = false end
    Tracer.flashHead, Tracer.puffHead = 0, 0
end

function Tracer.clear()
    Tracer.clearRounds()
    Tracer.clearFlashes()
end

function Tracer.unit()
    if type(ZombRand) ~= "function" then return 0.5 end
    return ZombRand(10001) / 10000
end

function Tracer.deviation(limit)
    return (Tracer.unit() * 2 - 1) * (tonumber(limit) or 0)
end

function Tracer.fan(bearing, pellets, cone)
    local count = math.max(1, math.min(12, math.floor(tonumber(pellets) or 1)))
    local list = {}
    if count == 1 then
        list[1] = bearing
        return list
    end
    local width = tonumber(cone) or 0
    for index = 1, count do
        list[index] = bearing + ((index - 1) / (count - 1) - 0.5) * width
    end
    return list
end

local function launch(x, y, z, bearing, startedAt)
    local s = Tracer.settings
    Tracer.head = Tracer.head % s.capacity + 1
    local radians = math.rad(bearing)
    Tracer.rounds[Tracer.head] = {
        x = x, y = y, z = z,
        dx = math.cos(radians), dy = math.sin(radians),
        born = startedAt,
    }
    return Tracer.rounds[Tracer.head]
end

function Tracer.bearingTo(x, y, aimX, aimY)
    local dx, dy = aimX - x, aimY - y
    if dx * dx + dy * dy < 0.0001 then return nil end
    if math.abs(dx) < 0.000001 then return dy >= 0 and 90 or -90 end
    local bearing = math.deg(math.atan(dy / dx))
    if dx < 0 then bearing = bearing + 180 end
    return bearing
end

function Tracer.add(worldX, worldY, worldZ, aimX, aimY, pellets, muzzle, context, remote)
    if not Tracer.configured then Tracer.syncFromSandbox() end
    if not Tracer.enabled then return end
    local x0, y0 = tonumber(worldX), tonumber(worldY)
    local ax, ay = tonumber(aimX), tonumber(aimY)
    if x0 == nil or y0 == nil or ax == nil or ay == nil then return end
    local aim = Tracer.bearingTo(x0, y0, ax, ay)
    if aim == nil then return end
    local s = Tracer.settings
    local bearing = aim + Tracer.deviation(s.jitter)
    local radians = math.rad(bearing)
    local forward = tonumber(muzzle) or s.muzzle
    local x = x0 + math.cos(radians) * forward
    local y = y0 + math.sin(radians) * forward
    local z = (tonumber(worldZ) or 0) + s.height
    local startedAt = nowMs()
    for index, heading in ipairs(Tracer.fan(bearing, pellets, s.cone)) do
        Tracer.publish(launch(x, y, z, heading, startedAt), context, remote, index)
    end
end

function Tracer.segment(age, speed, range, streak)
    local nose = math.max(0, age) / 1000 * speed
    if nose - streak >= range then return nil end
    return math.max(0, nose - streak), math.min(nose, range)
end

function Tracer.screenPoint(x, y, z, zoom)
    return (IsoUtils.XToScreen(x, y, z, 0) - getCameraOffX()) / zoom + Tracer.originX,
        (IsoUtils.YToScreen(x, y, z, 0) - getCameraOffY()) / zoom + Tracer.originY
end

function Tracer.whiteTile()
    if Tracer.tile == nil then Tracer.tile = getTexture("media/textures/ProjectALifeLine.png") end
    return Tracer.tile
end

function Tracer.drawRounds(renderer, tile, zoom, now)
    local s = Tracer.settings
    local live = 0
    for slot, round in pairs(Tracer.rounds) do
        local tail, nose = Tracer.segment(now - round.born, s.speed, s.range, s.streak)
        if tail == nil then
            Tracer.rounds[slot] = nil
        else
            live = live + 1
            local x1, y1 = Tracer.screenPoint(round.x + round.dx * tail, round.y + round.dy * tail, round.z, zoom)
            local x2, y2 = Tracer.screenPoint(round.x + round.dx * nose, round.y + round.dy * nose, round.z, zoom)
            local alpha = s.alpha * (1 - nose / (s.range + s.streak))
            renderer:renderline(tile, x1, y1, x2, y2, s.color[1], s.color[2], s.color[3], alpha)
        end
    end
    if live == 0 then Tracer.clearRounds() end
end

function Tracer.shapeFor(scale)
    if scale >= 1.4 then return Tracer.shapes.shotgun end
    if scale <= 1.0 then return Tracer.shapes.pistol end
    return Tracer.shapes.rifle
end

function Tracer.envelope(t)
    if t <= 0 then return 1 end
    if t >= 1 then return 0 end
    local hold = Tracer.settings.holdFraction
    if t <= hold then return 1 end
    local k = (1 - t) / (1 - hold)
    return k * k * (3 - 2 * k)
end

function Tracer.dayLight()
    local manager = type(getClimateManager) == "function" and getClimateManager() or nil
    if manager == nil or type(manager.getDayLightStrength) ~= "function" then return 0 end
    local value = tonumber(manager:getDayLightStrength()) or 0
    return math.max(0, math.min(1, value))
end

function Tracer.muzzleHeight(shape)
    return Tracer.settings.height + shape.lift
end

function Tracer.muzzlePoint(x, y, bearing, muzzle)
    local radians = math.rad(bearing)
    return x + math.cos(radians) * muzzle, y + math.sin(radians) * muzzle
end

function Tracer.pick(list)
    return list[math.min(#list, 1 + math.floor(Tracer.unit() * #list))]
end

function Tracer.styleName()
    if Tracer.settings.flashStyle == "atlas" then
        local tex = Tracer.fxTexture("flash")
        if tex ~= nil and (type(tex.isReady) ~= "function" or tex:isReady() == true) then return "atlas" end
    end
    return "vanilla"
end

function Tracer.flash(x, y, z, bearing, scale, muzzle)
    local s = Tracer.settings
    local shape = Tracer.shapeFor(scale)
    local radians = math.rad(bearing)
    Tracer.flashHead = Tracer.flashHead % s.flashCapacity + 1
    local flash = Tracer.flashes[Tracer.flashHead]
    if flash == nil then
        flash = {}
        Tracer.flashes[Tracer.flashHead] = flash
    end
    local day = Tracer.dayLight()
    flash.alive = true
    flash.shown = false
    flash.show = false
    flash.layers = false
    flash.dx, flash.dy = math.cos(radians), math.sin(radians)
    flash.x, flash.y = x + flash.dx * muzzle, y + flash.dy * muzzle
    flash.z = z + Tracer.muzzleHeight(shape)
    flash.bearing = bearing
    flash.scale = scale
    flash.shape = shape
    flash.style = Tracer.styleName()
    flash.look = Tracer.styles[flash.style]
    flash.tongue = Tracer.pick(shape.tongues)
    flash.star = Tracer.pick(Tracer.starRegions)
    flash.spin = Tracer.unit() * 6.2832
    flash.flip = Tracer.unit() < 0.5 and 1 or -1
    flash.jitter = Tracer.deviation(5)
    flash.spread = Tracer.deviation(0.15)
    flash.grow = 1 + Tracer.deviation(0.12)
    flash.dur = shape.dur * (0.92 + 0.16 * Tracer.unit())
    flash.dim = 1 - s.dayDim * day
    flash.glowDim = 1 - s.glowDayDim * day
    flash.born = nowMs()
    if scale >= s.puffMinScale then
        Tracer.puff(flash.x, flash.y, flash.z, flash.dx, flash.dy, scale * shape.puff, day, flash.born)
    end
    return flash
end

function Tracer.puff(x, y, z, dx, dy, scale, day, born)
    local s = Tracer.settings
    Tracer.puffHead = Tracer.puffHead % s.puffCapacity + 1
    local puff = Tracer.puffs[Tracer.puffHead]
    if puff == nil then
        puff = {}
        Tracer.puffs[Tracer.puffHead] = puff
    end
    puff.alive = true
    puff.x, puff.y, puff.z, puff.dx, puff.dy = x, y, z, dx, dy
    puff.scale, puff.day, puff.born = scale, day, born
    puff.spin = Tracer.unit() * 6.2832
    puff.region = Tracer.pick(Tracer.puffRegions)
    return puff
end

function Tracer.fxTexture(key)
    local cached = Tracer.fx[key]
    if cached ~= nil and cached ~= false then return cached end
    if type(getTexture) ~= "function" then return nil end
    local now = nowMs()
    if cached == false and now < (Tracer.fxRetry[key] or 0) then return nil end
    local loaded = getTexture(Tracer.fxFiles[key])
    if loaded == nil then
        Tracer.fx[key] = false
        Tracer.fxRetry[key] = now + Tracer.settings.textureRetryMs
        return nil
    end
    Tracer.fx[key] = loaded
    return loaded
end

function Tracer.region(name, style)
    local set = Tracer.regionSets[style]
    if set == nil then return nil end
    return set[name]
end

function Tracer.regionUV(name, style)
    local region = Tracer.region(name, style or "vanilla")
    if region == nil then return nil end
    local tex = Tracer.fxTexture(region[1])
    if tex == nil then return nil end
    if type(tex.isReady) == "function" and tex:isReady() ~= true then return nil end
    local atlas = Tracer.fxSize[region[1]] or Tracer.settings.atlas
    local xs, ys = tex:getXStart(), tex:getYStart()
    local du, dv = tex:getXEnd() - xs, tex:getYEnd() - ys
    return tex, xs + du * region[2] / atlas, ys + dv * region[3] / atlas,
        xs + du * (region[2] + region[4]) / atlas, ys + dv * (region[3] + region[5]) / atlas
end

function Tracer.regionAspect(name, style)
    local region = Tracer.region(name, style)
    if region == nil then return 0.5 end
    return region[4] / region[5]
end

function Tracer.poly(renderer, tex, x1, y1, x2, y2, x3, y3, x4, y4, r, g, b, a, u0, v0, u1, v1)
    renderer:renderPoly(tex, x1, y1, x2, y2, x3, y3, x4, y4, r, g, b, a, u0, v0, u1, v0, u1, v1, u0, v1)
end

function Tracer.sprite(renderer, tex, cx, cy, half, spin, flip, r, g, b, a, u0, v0, u1, v1)
    local ex, ey = math.cos(spin) * half, math.sin(spin) * half
    local fx, fy = -ey, ex
    if flip < 0 then u0, u1 = u1, u0 end
    Tracer.poly(renderer, tex, cx - ex - fx, cy - ey - fy, cx + ex - fx, cy + ey - fy,
        cx + ex + fx, cy + ey + fy, cx - ex + fx, cy - ey + fy, r, g, b, a, u0, v0, u1, v1)
end

function Tracer.axis(flash, zoom)
    local tx, ty = Tracer.screenPoint(flash.x + flash.dx, flash.y + flash.dy, flash.z, zoom)
    local ax, ay = tx - flash.ox, ty - flash.oy
    local length = math.sqrt(ax * ax + ay * ay)
    if length < 0.001 then return 1, 0 end
    return ax / length, ay / length
end

function Tracer.tongue(renderer, flash, zoom, name, lengthScale, widthScale, degrees, r, g, b, a)
    local tex, u0, v0, u1, v1 = Tracer.regionUV(name, flash.style)
    if tex == nil then return false end
    local shape, look = flash.shape, flash.look
    local ox, oy = flash.ox, flash.oy
    local radians = math.rad(flash.bearing + flash.jitter + degrees)
    local tiles = shape.length * look.lengthGain * flash.scale * flash.grow * lengthScale
    local tx, ty = Tracer.screenPoint(flash.x + math.cos(radians) * tiles,
        flash.y + math.sin(radians) * tiles, flash.z, zoom)
    local ax, ay = tx - ox, ty - oy
    local reach = math.sqrt(ax * ax + ay * ay)
    if reach < 1 then return false end
    local half = tiles * Tracer.px * Tracer.regionAspect(name, flash.style) * shape.widen * look.widthGain
        * widthScale * 0.5
    local nx, ny = -ay / reach * half, ax / reach * half
    local sx, sy = ox - ax * 0.05, oy - ay * 0.05
    local wx, wy = nx * 1.15, ny * 1.15
    Tracer.poly(renderer, tex, sx - nx, sy - ny, sx + nx, sy + ny, tx + wx, ty + wy, tx - wx, ty - wy,
        r, g, b, a, u0, v0, u1, v1)
    return true
end

function Tracer.drawTongues(renderer, flash, zoom)
    local s = Tracer.settings
    local alpha = s.tongueAlpha * flash.env * flash.dim
    if alpha <= 0.004 then return end
    local shape = flash.shape
    Tracer.tongue(renderer, flash, zoom, flash.tongue, 1, 1, 0, 1, 1, 1, alpha)
    Tracer.tongue(renderer, flash, zoom, flash.tongue, 0.68, 0.6, 0, 1.0, 0.92, 0.7, alpha * 0.85)
    if shape.fork then
        local spread = Tracer.forkDegrees * (1 + flash.spread)
        Tracer.tongue(renderer, flash, zoom, flash.tongue, 0.78, 0.7, spread, 1, 0.95, 0.85, alpha * 0.7)
        Tracer.tongue(renderer, flash, zoom, flash.tongue, 0.78, 0.7, -spread, 1, 0.95, 0.85, alpha * 0.7)
    end
end

function Tracer.drawBlaze(renderer, flash, zoom)
    local s, look = Tracer.settings, flash.look
    local gain = flash.env * flash.dim * s.tongueGain
    if gain <= 0.01 then return end
    local c, a = look.tongueTint, s.additiveAlpha
    Tracer.tongue(renderer, flash, zoom, flash.tongue, 1, 1, 0, c[1] * gain, c[2] * gain, c[3] * gain, a)
    gain = gain * 0.8
    Tracer.tongue(renderer, flash, zoom, flash.tongue, 0.62, 0.55, 0, c[1] * gain, c[2] * gain, c[3] * gain, a)
end

function Tracer.drawLayers(renderer, flash, zoom)
    local s, look = Tracer.settings, flash.look
    local px = Tracer.px
    local shape = flash.shape
    local ox, oy, axisX, axisY = flash.ox, flash.oy, flash.axx, flash.axy
    local grow = flash.grow * (s.growStart + s.growSpan * flash.t)
    local a = s.additiveAlpha
    local tex, u0, v0, u1, v1 = Tracer.regionUV("glow", flash.style)
    if tex ~= nil then
        local half = math.max(s.minGlowPx, shape.glow * flash.scale * 0.5 * px * grow)
        local gain = flash.env * flash.glowDim * s.glowGain
        local c = look.glowTint
        local lead = 0.15 * px * flash.scale
        Tracer.sprite(renderer, tex, ox + axisX * lead, oy + axisY * lead, half, 0, 1,
            c[1] * gain, c[2] * gain, c[3] * gain, a, u0, v0, u1, v1)
    end
    tex, u0, v0, u1, v1 = Tracer.regionUV(flash.star, flash.style)
    if tex ~= nil then
        local half = math.max(s.minStarPx, shape.star * flash.scale * 0.5 * px * grow)
        local gain = flash.env * flash.dim * s.starGain
        local c = look.starTint
        local lead = 0.12 * px * flash.scale
        Tracer.sprite(renderer, tex, ox + axisX * lead, oy + axisY * lead, half, flash.spin, flash.flip,
            c[1] * gain, c[2] * gain, c[3] * gain, a, u0, v0, u1, v1)
    end
    if look.core then
        tex, u0, v0, u1, v1 = Tracer.regionUV("core", flash.style)
        if tex ~= nil then
            local half = (s.coreBase + s.coreScale * flash.scale) * px * (1 - 0.3 * flash.t)
            local gain = flash.env * flash.dim * s.coreGain
            local c = look.coreTint
            Tracer.sprite(renderer, tex, ox + axisX * px * 0.05, oy + axisY * px * 0.05, half, flash.spin * 0.25, 1,
                c[1] * gain, c[2] * gain, c[3] * gain, a, u0, v0, u1, v1)
        end
    end
end

function Tracer.drawCore(renderer, tile, flash)
    local s = Tracer.settings
    local px = Tracer.px
    local core = s.coreColor
    local size = (0.12 + 0.08 * flash.scale) * px * (1 - 0.35 * flash.t)
    local alpha = math.min(1, flash.env * flash.dim * 1.1)
    local axisX, axisY = flash.axx, flash.axy
    local nx, ny = -axisY * size * 0.4, axisX * size * 0.4
    local cx, cy = flash.ox + axisX * size * 0.3, flash.oy + axisY * size * 0.3
    renderer:renderPoly(tile, cx - axisX * size * 0.6, cy - axisY * size * 0.6, cx + nx, cy + ny,
        cx + axisX * size * 1.3, cy + axisY * size * 1.3, cx - nx, cy - ny, core[1], core[2], core[3], alpha)
end

function Tracer.drawLines(renderer, tile, flash, zoom)
    local s = Tracer.settings
    local c = s.flashColor
    local ox, oy = flash.ox, flash.oy
    local fade = flash.env * flash.dim
    for _, ray in ipairs(Tracer.rays) do
        local radians = math.rad(flash.bearing + flash.jitter + ray[1])
        local length = s.flashLength * flash.scale * flash.grow * ray[2]
        local ex, ey = Tracer.screenPoint(flash.x + math.cos(radians) * length,
            flash.y + math.sin(radians) * length, flash.z, zoom)
        renderer:renderline(tile, ox, oy, ex, ey, c[1], c[2], c[3], 0.85 * fade * ray[3])
        renderer:renderline(tile, ox + 1, oy, ex + 1, ey, c[1], c[2], c[3], 0.4 * fade * ray[3])
        renderer:renderline(tile, ox, oy + 1, ex, ey + 1, c[1], c[2], c[3], 0.4 * fade * ray[3])
    end
end

function Tracer.flashPhase(flash, now)
    local t = (now - flash.born) / flash.dur
    if t >= 1 and flash.shown then return nil end
    if t > 0.9 and not flash.shown then t = 0.9 end
    if t < 0 then t = 0 end
    return t, Tracer.envelope(t)
end

function Tracer.onScreen(x, y)
    local view = Tracer.viewRect
    return x >= view[1] and x <= view[3] and y >= view[2] and y <= view[4]
end

function Tracer.prepareFlashes(zoom, now)
    local live = 0
    for slot = 1, Tracer.settings.flashCapacity do
        local flash = Tracer.flashes[slot]
        if flash ~= nil and flash.alive then
            local t, env = Tracer.flashPhase(flash, now)
            if t == nil then
                flash.alive = false
                flash.show = false
            else
                live = live + 1
                flash.t, flash.env = t, env
                flash.ox, flash.oy = Tracer.screenPoint(flash.x, flash.y, flash.z, zoom)
                flash.show = Tracer.onScreen(flash.ox, flash.oy)
                if flash.show then flash.axx, flash.axy = Tracer.axis(flash, zoom) end
            end
        end
    end
    return live
end

function Tracer.drawPuffs(renderer, zoom, now)
    local s = Tracer.settings
    local live = 0
    local px = Tracer.px
    for slot = 1, s.puffCapacity do
        local puff = Tracer.puffs[slot]
        if puff ~= nil and puff.alive then
            local t = (now - puff.born) / s.puffMs
            if t >= 1 then
                puff.alive = false
            else
                live = live + 1
                if t < 0 then t = 0 end
                local tex, u0, v0, u1, v1 = Tracer.regionUV(puff.region, "vanilla")
                if tex ~= nil then
                    local cx, cy = Tracer.screenPoint(puff.x + puff.dx * s.puffDrift * t,
                        puff.y + puff.dy * s.puffDrift * t, puff.z + s.puffRise * t, zoom)
                    if Tracer.onScreen(cx, cy) then
                        local alpha = s.puffAlpha * (1 - t) * (1 - t) * (0.1 + 0.9 * puff.day)
                        if t < 0.15 then alpha = alpha * t / 0.15 end
                        local half = (0.28 + 0.5 * t) * puff.scale * px * 0.5
                        Tracer.sprite(renderer, tex, cx, cy, half, puff.spin + t * 0.6, 1, 0.82, 0.82, 0.84, alpha,
                            u0, v0, u1, v1)
                    end
                end
            end
        end
    end
    if live == 0 then Tracer.puffHead = 0 end
end

function Tracer.additiveReady(renderer)
    return Tracer.settings.additive == true and type(renderer.setDoAdditive) == "function"
        and type(renderer.getDoAdditive) == "function"
end

function Tracer.drawAdditive(renderer, zoom)
    for slot = 1, Tracer.settings.flashCapacity do
        local flash = Tracer.flashes[slot]
        if flash ~= nil and flash.alive and flash.show and flash.layers then
            if flash.look.tongueAdditive then Tracer.drawBlaze(renderer, flash, zoom) end
            Tracer.drawLayers(renderer, flash, zoom)
        end
    end
end

function Tracer.drawFlashes(renderer, tile, zoom, now)
    local s = Tracer.settings
    if Tracer.prepareFlashes(zoom, now) == 0 then
        Tracer.flashHead = 0
        return
    end
    local additive = Tracer.additiveReady(renderer)
    local layered = false
    for slot = 1, s.flashCapacity do
        local flash = Tracer.flashes[slot]
        if flash ~= nil and flash.alive and flash.show then
            flash.layers = additive and Tracer.regionUV("glow", flash.style) ~= nil
            if flash.layers then
                layered = true
                if not flash.look.tongueAdditive then Tracer.drawTongues(renderer, flash, zoom) end
            else
                Tracer.drawLines(renderer, tile, flash, zoom)
            end
        end
    end
    if layered then
        local was = renderer:getDoAdditive() == true
        renderer:setDoAdditive(true)
        pcall(Tracer.drawAdditive, renderer, zoom)
        renderer:setDoAdditive(was)
    end
    for slot = 1, s.flashCapacity do
        local flash = Tracer.flashes[slot]
        if flash ~= nil and flash.alive then
            if flash.show and not (flash.layers and flash.look.core) then Tracer.drawCore(renderer, tile, flash) end
            flash.shown = true
        end
    end
end

function Tracer.viewPlayer()
    local player
    if type(IsoPlayer) == "table" and type(IsoPlayer.getInstance) == "function" then player = IsoPlayer.getInstance() end
    if player == nil and type(getPlayer) == "function" then player = getPlayer() end
    return player
end

function Tracer.viewIndex()
    local player = Tracer.viewPlayer()
    if player ~= nil and type(player.getPlayerNum) == "function" then return player:getPlayerNum() end
    return 0
end

function Tracer.viewZoom()
    return getCore():getZoom(Tracer.viewIndex())
end

function Tracer.tileScale()
    if type(Core) == "table" and type(Core.getTileScale) == "function" then
        return math.max(1, tonumber(Core.getTileScale()) or 1)
    end
    return 1
end

function Tracer.frameView(index, zoom)
    local core = getCore()
    local left, top, width, height = 0, 0, 0, 0
    local split = type(getNumActivePlayers) == "function" and (tonumber(getNumActivePlayers()) or 1) > 1
    if split and type(getPlayerScreenLeft) == "function" then
        left, top = getPlayerScreenLeft(index), getPlayerScreenTop(index)
        width, height = getPlayerScreenWidth(index), getPlayerScreenHeight(index)
    elseif type(core.getScreenWidth) == "function" then
        width, height = core:getScreenWidth(), core:getScreenHeight()
    end
    if split then
        Tracer.originX, Tracer.originY = left, top
    else
        Tracer.originX, Tracer.originY = 0, 0
    end
    local view, margin = Tracer.viewRect, Tracer.settings.cullMargin
    if width > 0 and height > 0 then
        view[1], view[2], view[3], view[4] = left - margin, top - margin, left + width + margin, top + height + margin
    else
        view[1], view[2], view[3], view[4] = -1e9, -1e9, 1e9, 1e9
    end
    Tracer.px = Tracer.settings.tilePx * Tracer.tileScale() / zoom
end

function Tracer.render()
    if Tracer.head == 0 and Tracer.flashHead == 0 and Tracer.puffHead == 0 then return end
    if Tracer.suppress2D == true then return end
    if type(isServer) == "function" and isServer() then return end
    if type(isIngameState) == "function" and not isIngameState() then return end
    local tile = Tracer.whiteTile()
    if tile == nil then return end
    local renderer, now = getRenderer(), nowMs()
    local index = Tracer.viewIndex()
    local zoom = getCore():getZoom(index)
    Tracer.frameView(index, zoom)
    if Tracer.head ~= 0 then Tracer.drawRounds(renderer, tile, zoom, now) end
    if Tracer.puffHead ~= 0 then Tracer.drawPuffs(renderer, zoom, now) end
    if Tracer.flashHead ~= 0 then Tracer.drawFlashes(renderer, tile, zoom, now) end
    Tracer.originX, Tracer.originY = 0, 0
end

function Tracer.seen(x, y, z)
    local cell = getCell()
    if cell == nil then return false end
    local floor = math.floor(z)
    local square = cell:getGridSquare(math.floor(x), math.floor(y), floor)
    if square == nil then return false end
    local reach = Tracer.settings.seeRadius
    local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
    for index = 0, math.max(1, tonumber(count) or 1) - 1 do
        local player = getSpecificPlayer(index)
        if player ~= nil then
            local dx, dy = player:getX() - x, player:getY() - y
            if (dx * dx + dy * dy <= reach * reach and math.floor(player:getZ()) == floor)
                    or square:isCouldSee(index) then
                return true
            end
        end
    end
    return false
end

function Tracer.canSee(x, y, z)
    local ok, seen = pcall(Tracer.seen, x, y, z)
    return ok and seen == true
end

function Tracer.near(x, y, range)
    local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
    for index = 0, math.max(1, tonumber(count) or 1) - 1 do
        local player = getSpecificPlayer(index)
        if player ~= nil then
            local dx, dy = player:getX() - x, player:getY() - y
            if dx * dx + dy * dy <= range * range then return true end
        end
    end
    return false
end

function Tracer.nearPlayer(x, y, range)
    local ok, near = pcall(Tracer.near, x, y, range)
    return ok and near == true
end

function Tracer.lightAllowed(key, now)
    local s = Tracer.settings
    local last = Tracer.lightAt[key]
    if last ~= nil and now - last < s.lightGapMs then return false end
    if now - Tracer.lightWindow >= s.lightWindowMs then
        Tracer.lightWindow, Tracer.lightCount = now, 0
    end
    if Tracer.lightCount >= s.lightBurst then return false end
    Tracer.lightCount = Tracer.lightCount + 1
    if Tracer.lightSeen > 48 then Tracer.lightAt, Tracer.lightSeen = {}, 0 end
    Tracer.lightAt[key] = now
    Tracer.lightSeen = Tracer.lightSeen + 1
    return true
end

function Tracer.queueLight(cell, light)
    local positions = type(cell.getLamppostPositions) == "function" and cell:getLamppostPositions() or nil
    if positions ~= nil then
        positions:add(light)
        return
    end
    cell:addLamppost(light)
end

function Tracer.placeLight(lx, ly, lz, radius)
    local s = Tracer.settings
    local cell = getCell()
    local square = cell:getGridSquare(lx, ly, lz)
    if square ~= nil and square:isOutside() and getClimateManager():getDayLightStrength() > s.daylight then
        return
    end
    Tracer.queueLight(cell, IsoLightSource.new(lx, ly, lz, 1.0, 0.78, 0.46, radius, s.lightLife))
end

function Tracer.light(x, y, z, bearing, radius, muzzle)
    if IsoLightSource == nil or type(getCell) ~= "function" then return false end
    radius = math.floor(tonumber(radius) or 0)
    if radius < 1 then return false end
    local s = Tracer.settings
    if not Tracer.nearPlayer(x, y, s.lightRange) then return false end
    local mx, my = Tracer.muzzlePoint(x, y, bearing, muzzle)
    local lx, ly = math.floor(mx), math.floor(my)
    local lz = math.floor(z)
    if not Tracer.lightAllowed(lx .. ":" .. ly .. ":" .. lz, nowMs()) then return false end
    return pcall(Tracer.placeLight, lx, ly, lz, radius) == true
end

function Tracer.soundParameters(x, y, z)
    local player = getPlayer()
    if player == nil then return nil end
    local dx, dy = player:getX() - x, player:getY() - y
    local dz = (player:getZ() - z) * 3.0
    local inside, area = 0, 0
    local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    local room = square ~= nil and square:getRoom() or nil
    if room ~= nil then
        local here = player:getCurrentSquare()
        inside = (here ~= nil and here:getRoom() == room) and 1 or -1
        local definition = room:getRoomDef()
        if definition ~= nil then area = definition:getArea() end
    end
    return {
        FirearmDistance = math.max(0, math.min(1000, math.sqrt(dx * dx + dy * dy + dz * dz))),
        FirearmInside = inside,
        FirearmRoomSize = math.max(0, math.min(1000, tonumber(area) or 0)),
        LocalPlayer = 0,
    }
end

function Tracer.playAt(x, y, z, name, gain)
    if type(name) ~= "string" or name == "" or type(getWorld) ~= "function" then return false end
    return pcall(function()
        local emitter = getWorld():getFreeEmitter(x, y, z)
        local handle = emitter:playSound(name)
        local gainValue = tonumber(gain) or 1
        if gainValue ~= 1 and handle ~= nil then emitter:setVolume(handle, gainValue) end
        local parameters = Tracer.soundParameters(x, y, z)
        if parameters ~= nil and handle ~= nil then
            for key, value in pairs(parameters) do emitter:setParameterValueByName(handle, key, value) end
        end
    end) == true
end

function Tracer.later(delayMs, x, y, z, name, gain)
    if type(name) ~= "string" or name == "" then return false end
    local queue = Tracer.pending
    if #queue >= Tracer.settings.pendingCap then table.remove(queue, 1) end
    queue[#queue + 1] = { at = nowMs() + delayMs, x = x, y = y, z = z, name = name, gain = gain }
    return true
end

function Tracer.tick()
    local queue = Tracer.pending
    if #queue == 0 then return end
    local now = nowMs()
    local index = 1
    while index <= #queue do
        local item = queue[index]
        if now >= item.at then
            table.remove(queue, index)
            Tracer.playAt(item.x, item.y, item.z, item.name, item.gain)
        else
            index = index + 1
        end
    end
end

function Tracer.subscribe(listener)
    if type(listener) ~= "function" then return false end
    Tracer.listeners[#Tracer.listeners + 1] = listener
    return true
end

function Tracer.notify(event, remote)
    for _, listener in ipairs(Tracer.listeners) do
        pcall(listener, event, remote == true)
    end
end

function Tracer.show(event, remote)
    if type(event) ~= "table" then return false end
    local x, y = tonumber(event.x), tonumber(event.y)
    local ax, ay = tonumber(event.ax), tonumber(event.ay)
    if x == nil or y == nil or ax == nil or ay == nil then return false end
    local z = tonumber(event.z) or 0
    if not Tracer.flashConfigured or not Tracer.configured then Tracer.syncFromSandbox() end
    Tracer.notify(event, remote)
    local muzzle = (tonumber(event.mz) or 60) / 100
    local scale = (tonumber(event.fl) or 10) / 10
    Tracer.add(x, y, z, ax, ay, event.pel, muzzle, event, remote)
    local bearing = Tracer.bearingTo(x, y, ax, ay)
    if Tracer.flashEnabled and event.sp ~= 1 and scale > 0 and bearing ~= nil then
        if Tracer.canSee(x, y, z) then Tracer.flash(x, y, z, bearing, scale, muzzle) end
        Tracer.light(x, y, z, bearing, event.lr, muzzle)
    end
    local gain = tonumber(event.gn) or 1
    if remote == true then Tracer.playAt(x, y, z, event.sw, gain) end
    Tracer.later(Tracer.settings.brassDelayMs, x, y, z, event.br, gain)
    return true
end

function Tracer.shot(shot)
    if type(shot) ~= "table" then return end
    Tracer.show({ x = shot.fromX, y = shot.fromY, z = shot.fromZ, ax = shot.toX, ay = shot.toY,
        pel = shot.pellets, weapon = shot.weapon, owner = shot.owner }, false)
end

function Tracer.onServerCommand(module, command, args)
    if module ~= "ProjectALife" or command ~= "shotFx" then return end
    Tracer.show(args, true)
end

if type(Events) == "table" and Events.OnPreUIDraw ~= nil then
    Events.OnPreUIDraw.Add(function() pcall(Tracer.render) end)
end
if type(Events) == "table" and Events.OnTick ~= nil then
    Events.OnTick.Add(function() Tracer.tick() end)
end
if type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(Tracer.onServerCommand)
end

return Tracer
