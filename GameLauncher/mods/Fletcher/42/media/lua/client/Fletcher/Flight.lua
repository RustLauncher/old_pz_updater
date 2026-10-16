--[[
    Fletcher: arrows in flight (single player, F.projectileMode). client/Fletcher/Arrows.lua hands
    each shot to F.launchProjectile; every tick each flight advances (shared/Fletcher/Projectile.lua)
    and its arrow is drawn: a copy of the arrow item on the ground layer of the square it is over,
    moved with offsets (height in floors) and turned along its path, with a slim fading streak
    behind it (an arrow is a few pixels: alone it vanishes at 40 tiles a second), and a thin trail
    laid along its path that fades away piece by piece (FLIGHT_VIS.trailLife), so the whole shot shows
    for a moment; a lit fire arrow leaves smoke. Models: animation/scripts/flight_streak.py. Never
    synced; removed when it lands (the trail a moment later); any left in a save go when they load. (World items can't take a highlight colour: it's always the cyan outline.)
    The real arrow (stuck, dropped, broken) comes from F.finishProjectile.
]]

require "Fletcher/Core"
require "Fletcher/Projectile"
local F = Fletcher

F.flights = F.flights or {}
F.FLIGHT_VIS = {
    levelH = 3.0,       -- metres per floor (world item height offsets are in floors; a 1.8 m body is
                        -- about 0.6 of one on screen)
    yawOffset = 90,     -- the ground model runs along +z from its nock: +90 turns it onto the heading
    pitchSign = 1,
    arrowLen = 0.42,    -- the model's pivot is the nock: drawn this far behind the simulated tip (F.ARROW_LEN)
    streak = "Fletcher.FlightStreak",    -- a slim fading streak behind it (alone, an arrow is a few pixels)
    streakYaw = 180,    -- its model runs forward from the pivot like the arrow's: turned round to trail
    streakScale = 1.5,  -- 3.6 m long, 2 cm thick at the arrow, solid for its first quarter then fading
    trail = true,       -- a thin line along the arrow's true path, drawn on screen (F.drawTrails)
    trailColor = { 0.95, 0.95, 0.93 },       -- (a lit fire arrow: trailSmoke)
    trailSmoke = { 0.42, 0.40, 0.37 },
    trailAlpha = 0.55,
    trailWidth = 1.6,   -- pixels at zoom 1 (thinner zoomed out)
    trailStart = 0.6,   -- tiles from the bow before it shows
    trailLife = 700,    -- ms each stretch shows after the arrow passed it (it fades out from the bow end)
    show = true,
    -- highlight = true: outline the arrow (finding it in stills)
}

-- one drawn piece (the arrow or its streak): { item, wo, sq }
local function visRemove(v)
    if v.pooled then if F.viewpointPoolRelease then F.viewpointPoolRelease(v) end return end   -- (Viewpoint.lua)
    if v.wo and v.sq then pcall(function() v.sq:removeWorldObject(v.wo); v.sq:invalidateRenderChunkLevel(8) end) end
    v.wo, v.sq = nil, nil
end

local function visPlace(v, x, y, z, h, yaw, pitch)
    if v.turn then yaw, pitch = yaw + v.turn, -pitch end
    if v.pooled then F.viewpointPoolPlace(v, x, y, z, h, yaw, pitch) return end   -- ViewPoint's pool: moved in place
    local maxH = F.viewpointDrawMaxH and F.viewpointDrawMaxH()
    if maxH and h > maxH then h, pitch = maxH, 0 end    -- (ViewPoint's view draws nothing higher: level at it)
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), z)
    if not sq then visRemove(v) return end
    -- world items are drawn into the chunk's cached image, which a moved or turned item doesn't
    -- refresh (setOffset + invalidateRenderChunkLevel left it undrawn): take it off and put it back
    -- every tick, which draws like any dropped item
    visRemove(v)
    v.item:setWorldZRotation(yaw)
    v.item:setWorldYRotation(pitch)
    sq:AddWorldInventoryItem(v.item, x - sq:getX(), y - sq:getY(), math.max(0, h / F.FLIGHT_VIS.levelH), false)
    v.wo, v.sq = v.item:getWorldItem(), sq
    if v.wo and F.FLIGHT_VIS.highlight then v.wo:setHighlighted(0, true, false) end
end

local function visualRemove(f)
    for _, v in ipairs(f.vis) do visRemove(v) end
end

local function visualUpdate(f)
    if not F.FLIGHT_VIS.show then return end
    local p = f.p
    local flat = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local speed = math.sqrt(flat * flat + p.vh * p.vh)
    local back = (F.ARROW_LEN and F.ARROW_LEN[f.family] or F.FLIGHT_VIS.arrowLen) / math.max(1e-6, speed)
    local x, y, h = p.x - p.vx * back, p.y - p.vy * back, p.h - p.vh * back
    local yaw = math.deg(math.atan2(p.vy, p.vx)) + F.FLIGHT_VIS.yawOffset
    local pitch = math.deg(math.atan2(p.vh, flat)) * F.FLIGHT_VIS.pitchSign
    for _, v in ipairs(f.vis) do visPlace(v, x, y, p.z, h, yaw, pitch) end
end

-- The trail: each flight records its path (f.path: { x, y, h, d = distance flown, t = ms }) and
-- F.drawTrails draws it every frame as a thin line on screen, projected from the real 3D points, so it
-- follows the true arc and ends exactly where the arrow stopped: at a wall, a car, a target, or where
-- it first struck a wall it glanced off (p.impact; the bounce isn't drawn). Each stretch fades
-- F.FLIGHT_VIS.trailLife ms after the arrow passed it, so the line erodes from the bow end. Drawn on
-- the screen layer: it can show over a wall the path ran behind (arrows stop at walls, so rarely).
-- (Up to 0.5.3 the trail was world-item pieces: flat, laid per 2 tiles, sorted per square, so near
-- walls and cars they scattered; F.sweepFlightPieces still clears any left in old saves.)
F.trails = F.trails or {}
F.TRAIL_TYPES = { ["Fletcher.FlightTrail"] = true, ["Fletcher.FlightTrailFire"] = true,
                  ["Fletcher.FlightStreak"] = true, ["Fletcher.FlightStreakFire"] = true,
                  ["Fletcher.FlightArrow"] = true }       -- (ViewPoint's flight pool, Viewpoint.lua)

local function trailRecord(f, x, y, h)
    local path = f.path
    if f.trailDone then return end
    local last = path[#path]
    local dx, dy = x - last.x, y - last.y
    table.insert(path, { x = x, y = y, h = h, d = last.d + math.sqrt(dx * dx + dy * dy), t = getTimestampMs() })
end

--- the flight is over (or glanced off a wall): its trail ends at (x, y, h)
local function trailEnd(f, x, y, h)
    if f.trailDone then return end
    trailRecord(f, x, y, h)
    f.trailDone = true
end

--- every trail gone now (tests)
function F.clearTrails() F.trails = {} end

--- Draw every trail for the local player's view; drop the ones fully faded
function F.drawTrails()
    local list = F.trails
    if #list == 0 then return end
    local V = F.FLIGHT_VIS
    local now = getTimestampMs()
    local player = getPlayer()
    -- (ViewPoint's 3D view: a line projected for the iso screen lands in the wrong place; skip it)
    local inVp = player and F.viewpointView and F.viewpointView(player)
    local pn = player and player:getPlayerNum() or 0
    local zoom = getCore():getZoom(pn)
    local width = math.max(1, V.trailWidth / math.max(0.25, zoom))
    local rr = getRenderer()
    for i = #list, 1, -1 do
        local tr = list[i]
        local path = tr.path
        local newest = path[#path].t or now
        if tr.done and now - newest > V.trailLife then
            table.remove(list, i)
        elseif V.show and V.trail and not inVp then
            local c = tr.color
            local px, py
            for j = 1, #path do
                local q = path[j]
                local sx = isoToScreenX(pn, q.x, q.y, tr.z + q.h / V.levelH)
                local sy = isoToScreenY(pn, q.x, q.y, tr.z + q.h / V.levelH)
                if px and q.d >= V.trailStart then
                    local age = now - (q.t or now)
                    local a = V.trailAlpha * (1 - age / V.trailLife)
                    if a > 0.01 then
                        rr:renderline(nil, math.floor(px), math.floor(py), math.floor(sx), math.floor(sy), c[1], c[2], c[3], a, width)
                    end
                end
                px, py = sx, sy
            end
        end
    end
end

--- A bow shot left the string: fly it (tx, ty: a target point instead of the aim; tests; fl: the arrow's
--- fletching, Fletching.lua). Returns the flight.
function F.launchProjectile(shooter, bow, arrow, tx, ty, lit, fl)
    return F.launchFrom({ shooter = shooter, bow = bow, arrow = arrow, tx = tx, ty = ty, lit = lit, fl = fl })
end

--- Fly a shot made from F.newProjectile options (from, aimH, level, noSpread, releaseH, noXp, trap:
--- a tripwire trap's shot, Trap.lua). Returns the flight.
function F.launchFrom(opt)
    local shooter, arrow = opt.shooter, opt.arrow
    local p = F.newProjectile(opt)
    local def = F.ARROW_DEFS[arrow or ""] or {}
    if def.fire and not opt.trap then
        if F.handLighting and F.handLighting() then
            p.lit = opt.lit == true                    -- (lit by hand before the shot: FireLight.lua)
        elseif isClient() then
            -- (a lighter / matches carried; in multiplayer the server spends the use: here only the look)
            p.lit = F.fireSource(shooter) ~= nil
        else
            p.lit = F.lightFire(shooter)
        end
    end
    local f = { p = p, last = getTimestampMs(), vis = { { item = F.setFletch(instanceItem(arrow or F.DEFAULT_ARROW), p.fl) } },
                family = def.family or "arrow" }
    if F.FLIGHT_VIS.streak then
        local streak = instanceItem((p.lit and def.streak) or F.FLIGHT_VIS.streak)
        streak:setWorldScale(F.FLIGHT_VIS.streakScale)
        table.insert(f.vis, { item = streak, turn = F.FLIGHT_VIS.streakYaw })
    end
    if F.viewpointPoolTake then F.viewpointPoolTake(f, arrow or F.DEFAULT_ARROW, (p.lit and def.streak) or F.FLIGHT_VIS.streak) end
    f.path = { { x = p.x, y = p.y, h = p.h, d = 0, t = getTimestampMs() } }
    f.trail = { path = f.path, z = p.z, color = p.lit and F.FLIGHT_VIS.trailSmoke or F.FLIGHT_VIS.trailColor }
    table.insert(F.trails, f.trail)
    f.flown = 0
    f.from = { x = p.x, y = p.y, z = p.z, h = p.h, vx = p.vx, vy = p.vy, vh = p.vh }   -- (multiplayer report)
    table.insert(F.flights, f)
    F.lastFlight = f
    visualUpdate(f)
    return f
end

--- Multiplayer: another player's shot, replayed for the look only (the server's broadcast of what
--- their client flew): the same arc from the same start for the same time, ending where it ended.
--- No hits, no landing: the arrow itself (in a wall, on the ground, stuck) comes from the server.
--- m: { x, y, z, h, vx, vy, vh, dur (s), ex, ey, eh, arrow, fl, lit }
function F.launchGhost(m)
    local def = F.ARROW_DEFS[m.arrow or ""] or {}
    local p = { x = m.x, y = m.y, z = m.z, h = m.h, vx = m.vx, vy = m.vy, vh = m.vh, arrow = m.arrow, fl = m.fl, lit = m.lit, hit = {} }
    local f = { p = p, last = getTimestampMs(), vis = { { item = F.setFletch(instanceItem(m.arrow or F.DEFAULT_ARROW), m.fl) } },
                family = def.family or "arrow", ghost = true, flown = 0, dur = m.dur or 0,
                stop = { x = m.ex or p.x, y = m.ey or p.y, h = m.eh or 0 } }
    if F.FLIGHT_VIS.streak then
        local streak = instanceItem((m.lit and def.streak) or F.FLIGHT_VIS.streak)
        streak:setWorldScale(F.FLIGHT_VIS.streakScale)
        table.insert(f.vis, { item = streak, turn = F.FLIGHT_VIS.streakYaw })
    end
    if F.viewpointPoolTake then F.viewpointPoolTake(f, m.arrow or F.DEFAULT_ARROW, (m.lit and def.streak) or F.FLIGHT_VIS.streak) end
    f.path = { { x = p.x, y = p.y, h = p.h, d = 0, t = getTimestampMs() } }
    f.trail = { path = f.path, z = p.z, color = m.lit and F.FLIGHT_VIS.trailSmoke or F.FLIGHT_VIS.trailColor }
    table.insert(F.trails, f.trail)
    table.insert(F.flights, f)
    F.lastGhost = f
    visualUpdate(f)
    return f
end

--- Move one flight on by dt seconds (drawn or settled). True when it has landed.
local function advanceGhost(f, dt)
    local p = f.p
    f.flown = f.flown + dt
    if f.flown >= f.dur then
        visualRemove(f)
        pcall(trailEnd, f, f.stop.x, f.stop.y, f.stop.h)
        if f.trail then f.trail.done = true end
        for i = #F.flights, 1, -1 do if F.flights[i] == f then table.remove(F.flights, i) end end
        return true
    end
    local vh1 = p.vh - F.PROJ.gravity * dt
    p.x, p.y, p.h = p.x + p.vx * dt, p.y + p.vy * dt, p.h + (p.vh + vh1) / 2 * dt
    p.vh = vh1
    pcall(trailRecord, f, p.x, p.y, p.h)
    pcall(visualUpdate, f)
    return false
end

function F.advanceFlight(f, dt)
    if f.ghost then return advanceGhost(f, dt) end
    f.flown = (f.flown or 0) + dt
    local ok, out = pcall(F.stepProjectile, f.p, dt)
    if not ok then F.lastFlightError = out; out = { kind = "lost", x = f.p.x, y = f.p.y, z = f.p.z, h = 0 } end
    local p = f.p
    if f.path then
        if p.impact then pcall(trailEnd, f, p.impact.x, p.impact.y, p.impact.h)        -- (glanced: ends at the wall)
        elseif not out then pcall(trailRecord, f, p.x, p.y, p.h) end
    end
    if out then
        visualRemove(f)
        if f.path then pcall(trailEnd, f, out.x, out.y, out.h or 0) end
        if f.trail then f.trail.done = true end
        for i = #F.flights, 1, -1 do if F.flights[i] == f then table.remove(F.flights, i) end end
        f.p.flown, f.p.netFrom = f.flown, f.from          -- (multiplayer: the report replays it)
        F.finishProjectile(f.p, out)
        return true
    end
    pcall(visualUpdate, f)
    return false
end

function F.onFlightTick()
    if #F.flights == 0 then return end
    local now = getTimestampMs()
    for i = #F.flights, 1, -1 do
        local f = F.flights[i]
        if f then
            local dt = math.min(0.05, math.max(0, (now - f.last) / 1000))   -- (paused: no time passes)
            f.last = now
            F.advanceFlight(f, dt)
        end
    end
end

Events.OnTick.Add(function() F.onFlightTick() end)     -- by name: reloads apply
Events.OnPreUIDraw.Add(function() pcall(F.drawTrails) end)

--- a streak or trail piece caught in a save (the game saved mid-flight): gone when its square loads.
--- Returns how many went.
function F.sweepFlightPieces(sq)
    local w = sq:getWorldObjects()
    local n = 0
    for i = w:size() - 1, 0, -1 do
        local it = w:get(i):getItem()
        if it and F.TRAIL_TYPES[it:getFullType()] then sq:removeWorldObject(w:get(i)); n = n + 1 end
    end
    return n
end
Events.LoadGridsquare.Add(function(sq) if sq:getWorldObjects():size() > 0 then F.sweepFlightPieces(sq) end end)

return F
