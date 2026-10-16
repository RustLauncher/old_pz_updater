--[[
    Fletcher with ViewPoint (Workshop 3809306528: a first/third-person 3D view, a ZombieBuddy Java mod).
    ViewPoint draws the world from the character's eyes and holds the mouse at the screen centre while
    the camera looks around, so the iso maths the shot normally uses (the ground point under the mouse,
    a body's box on the iso screen) means nothing there: it aimed every shot at the archer's feet.

    Aiming in ViewPoint's view (0.8):
    - With the optional "Fletcher: ViewPoint Bridge" Java mod (Contents/mods/FletcherViewpoint, source in
      java/FletcherViewpoint), FletcherViewpoint.Camera hands over ViewPoint's camera yaw and pitch: the
      shot follows the line of sight from the archer's eye. It goes at the first zombie, animal, player or
      archery target the line passes through (within its width, between its feet and its top, before the
      line meets the ground; F.VP_SIGHT's small tolerance), at the height the line crosses it: a head, a
      leg, over a bale. Nothing on the line: the ground point looked at, or out along the line.
    - Without it (ViewPoint keeps the pitch in Java), aim assist: the archer faces where the camera
      looks (ViewPoint turns the character with the camera while aiming), so the shot goes along that
      facing at whatever is nearest the line (F.VP_ASSIST), at torso height.
    - With ViewPoint's cursor freed (middle mouse button) Viewpoint.Mouse.worldX/Y is the world point
      under it: the shot goes there, at whatever stands by it.

    Everything here checks for ViewPoint first and changes nothing without it.
]]

require "Fletcher/Core"
local F = Fletcher

F.VP_ASSIST = {
    angle = 6,          -- degrees either side of the facing a target may be off the line
    near = 0.15,        -- ... or this many tiles to the side, whichever is wider (very close targets)
    minAlong = 0.4,     -- tiles ahead before anything counts (not the archer's own square)
    cursorPick = 1.2,   -- freed cursor: a target this close to the point under it is the one meant
    torso = 0.62,       -- aim this far up a body (of its top height): the chest of a standing one
}

F.VP_SIGHT = {          -- the line of sight (with the bridge)
    side = 2,           -- degrees of slack sideways ...
    up = 2,             -- ... and up / down (a moving target, a twitchy hand)
    minAlong = 0.4,
    eyeH = nil,         -- metres; nil: the game's aim origin (IsoPlayer:getAimOriginPosZ, about 1.5 m)
    farH = 6,           -- nothing hit, looking up: the aim height at the bow's range is capped here (m)
    reticle = true,     -- follow ViewPoint's reticle (0.1.6+): the shot goes where its swaying dot is, not
                        -- the screen centre (View.swayRight / swayUp, radians: what its own shots use)
}

--- Is ViewPoint loaded (its Lua API exposed)?
function F.viewpointLoaded()
    return Viewpoint ~= nil and Viewpoint.Mouse ~= nil
end

local function bridge()
    return FletcherViewpoint and FletcherViewpoint.Camera
end

--- ViewPoint's camera (yaw, pitch in radians; pitch up is positive) from the bridge, or nil
function F.viewpointCamera()
    local C = bridge()
    if not C then return nil end
    local ok, yaw, pitch = pcall(function() return C.yaw(), C.pitch() end)
    if ok and yaw and pitch then return yaw, pitch end
    return nil
end

--- ViewPoint's reticle sway (right, up; radians) from the bridge, or nil (ViewPoint before 0.1.6, no bridge)
function F.viewpointSway()
    local C = bridge()
    if not (C and C.reticle) then return nil end
    local ok, r, u = pcall(function() return C.reticle("swayRight"), C.reticle("swayUp") end)
    if ok and r and u then return r, u end
    return nil
end

--- Does this ViewPoint draw world items as soon as they're added, at any height (0.1.6+, known through the
--- bridge's reticle)? Then flights need no pool (F.VP_POOL) and no height clamp.
function F.viewpointDrawsNewItems()
    return F.viewpointSway() ~= nil
end

--- The highest a flight is drawn in ViewPoint's view (metres over its floor), or nil (no limit: not its view).
--- ViewPoint 0.1.6 draws a world item up to one floor over its square, not above (checked on the Deck,
--- 2026-10-11: 3.0 m drawn, 3.5 m not); older versions use the pool and its own F.VP_POOL.maxH.
function F.viewpointDrawMaxH(player)
    if not (F.viewpointDrawsNewItems() and F.viewpointView(player or getPlayer())) then return nil end
    return F.FLIGHT_VIS.levelH * F.VP_DRAW_TOP
end
F.VP_DRAW_TOP = 0.99     -- of a floor

--- The world point under ViewPoint's freed cursor, or nil (its camera is looking, or no ViewPoint)
function F.viewpointCursorPoint()
    if not F.viewpointLoaded() then return nil end
    local ok, x, y = pcall(function() return Viewpoint.Mouse.worldX(), Viewpoint.Mouse.worldY() end)
    if ok and x and y then return x, y end
    return nil
end

--- Is this local player looking through ViewPoint's camera rather than the iso view? With the bridge,
--- ViewPoint's own "view on" flag (View.enabled), for mouse and controller alike. Without it (mouse only):
--- a freed cursor reports a world point, and its camera keeps the mouse at the screen centre. A
--- controller player without the bridge isn't recognised (nothing in ViewPoint's Lua API tells).
function F.viewpointView(player)
    if not (F.viewpointLoaded() and player and player:isLocalPlayer()) then return false end
    local pad = player.getJoypadBind and player:getJoypadBind() ~= -1
    local C = bridge()
    if C and C.viewOn then
        local ok, v = pcall(C.viewOn)
        if ok and v ~= nil then return v == true end
    end
    if pad then return false end
    if F.viewpointCursorPoint() then return true end
    if C and C.captured then
        local ok, v = pcall(C.captured)
        if ok and v ~= nil then return v == true end
    end
    local core = getCore()
    return math.abs(getMouseX() - math.floor(core:getScreenWidth() / 2)) <= 2
        and math.abs(getMouseY() - math.floor(core:getScreenHeight() / 2)) <= 2
end

local function onGround(z)
    local ok, v = pcall(function() return z:isOnFloor() end)
    if ok and v then return true end
    return z:isProne() or z:isCrawling() or z:isKnockedDown()
end

--- Everything a shot could go for near the shooter: { o, x, y, r = radius (tiles), top = height (m) }
function F.viewpointCandidates(shooter, range)
    local P = F.PROJ
    local sx, sy, z = shooter:getX(), shooter:getY(), math.floor(shooter:getZ())
    local out = {}
    local function add(o, x, y, oz, r, top)
        if math.floor(oz) == z and IsoUtils.DistanceTo(x, y, sx, sy) <= range + 3 then
            table.insert(out, { o = o, x = x, y = y, r = r, top = top })
        end
    end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        if not o:isDead() then
            add(o, o:getX(), o:getY(), o:getZ(), P.pickWidth, onGround(o) and P.proneTop or P.bodyTop)
        end
    end
    local animals = getCell().getAnimals and getCell():getAnimals()
    for i = 0, (animals and animals:size() or 0) - 1 do
        local a = animals:get(i)
        if not a:isDead() then
            local r, top = F.animalShape(a)
            add(a, a:getX(), a:getY(), a:getZ(), r, top)
        end
    end
    for _, p in ipairs(F.otherPlayers(shooter)) do
        if not p:isDead() then add(p, p:getX(), p:getY(), p:getZ(), P.pickWidth, P.bodyTop) end
    end
    if F.TARGET then
        local cell, R = getCell(), math.ceil(range) + 2
        for dx = -R, R do for dy = -R, R do
            local sq = cell:getGridSquare(math.floor(sx) + dx, math.floor(sy) + dy, z)
            local w = sq and sq:getWorldObjects()
            for i = 0, (w and w:size() or 0) - 1 do
                local wo = w:get(i)
                local it = wo:getItem()
                if it and it:getFullType() == F.TARGET_ITEM then
                    add(wo, sq:getX() + wo:getOffX(), sq:getY() + wo:getOffY(), z,
                        math.max(F.TARGET.w, F.TARGET.d) / 2, F.TARGET.top)
                end
            end
        end end
    end
    return out
end

--- Where on a candidate the assist aims (metres up)
local function aimHeight(c)
    return math.max(0.05, c.top * F.VP_ASSIST.torso)
end

--- The archer's eye height (metres over its floor)
function F.viewpointEyeH(shooter)
    if F.VP_SIGHT.eyeH then return F.VP_SIGHT.eyeH end
    local ok, z = pcall(function() return shooter:getAimOriginPosZ() end)
    if ok and z then return math.max(0.5, (z - math.floor(shooter:getZ())) * F.FLIGHT_VIS.levelH) end
    return 1.5
end

--- The line of sight from the bridge: { x, y, fx, fy (unit, flat), eyeH, tanP } or nil
function F.viewpointSight(shooter)
    local yaw, pitch = F.viewpointCamera()
    if not yaw then return nil end
    if F.VP_SIGHT.reticle then
        local r, u = F.viewpointSway()
        if r then yaw, pitch = yaw + r, pitch + u end
    end
    -- (the camera's yaw, not the character's facing: they match in first person, but over the shoulder
    -- ViewPoint turns the body a few degrees off the crosshair, and the facing missed by ~0.6 tiles at 9)
    return { x = shooter:getX(), y = shooter:getY(), fx = math.cos(yaw), fy = math.sin(yaw),
             eyeH = F.viewpointEyeH(shooter), tanP = math.tan(pitch), pitch = pitch }
end

--- How far along the line of sight it meets the ground (tiles), or nil (level or looking up)
local function groundAt(s)
    if s.tanP >= -1e-4 then return nil end
    return s.eyeH / -s.tanP
end

--- The first candidate the line of sight passes through (within F.VP_SIGHT's slack), and the height it
--- crosses it at; nil if nothing is on the line before it meets the ground
function F.viewpointSightTarget(shooter, range, s)
    local S = F.VP_SIGHT
    local tanSide, tanUp = math.tan(math.rad(S.side)), math.tan(math.rad(S.up))
    local ground = groundAt(s)
    local best, bestAlong, bestH
    for _, c in ipairs(F.viewpointCandidates(shooter, range)) do
        local vx, vy = c.x - s.x, c.y - s.y
        local along = vx * s.fx + vy * s.fy
        if along >= S.minAlong and along <= range + 3 and (not ground or along - c.r <= ground) then
            local side = math.abs(vx * s.fy - vy * s.fx)
            if side <= c.r + along * tanSide then
                -- the line's height where it reaches the body (its near face), with the slack
                local at = math.max(S.minAlong, along - c.r * 0.5)
                local h = s.eyeH + at * s.tanP
                local slack = at * tanUp
                if h >= -slack and h <= c.top + slack and (not bestAlong or along < bestAlong) then
                    best, bestAlong = c, along
                    bestH = math.max(0.05, math.min(c.top - 0.05, h))
                end
            end
        end
    end
    return best, bestH
end

--- The candidate nearest the shooter's line of sight (its facing), or nil. Anything whose body
--- touches the cone counts; the one whose centre is the fewest degrees off the line wins (so a zombie
--- just behind a wide bale is still the one picked when the crosshair is on the zombie).
function F.viewpointAssistTarget(shooter, range)
    local A = F.VP_ASSIST
    local fwd = shooter:getForwardDirection()
    local fx, fy = fwd:getX(), fwd:getY()
    local sx, sy = shooter:getX(), shooter:getY()
    local tanA = math.tan(math.rad(A.angle))
    local best, bestAng
    for _, c in ipairs(F.viewpointCandidates(shooter, range)) do
        local vx, vy = c.x - sx, c.y - sy
        local along = vx * fx + vy * fy
        if along >= A.minAlong and along <= range + 3 then
            local side = math.abs(vx * fy - vy * fx)
            if side <= math.max(A.near, along * tanA) + c.r then
                local ang = math.atan2(side, along)
                if not bestAng or ang < bestAng - 1e-4 or (math.abs(ang - bestAng) <= 1e-4 and along < best.along) then
                    best, bestAng = c, ang
                    best.along = along
                end
            end
        end
    end
    return best
end

--- F.cursorTarget in ViewPoint's view: (true, target, height) or false (not in its view: iso picking)
function F.viewpointAim(shooter, range)
    if not F.viewpointView(shooter) then return false end
    local px, py
    if shooter:getJoypadBind() == -1 then px, py = F.viewpointCursorPoint() end
    if px then
        local best, bestD
        for _, c in ipairs(F.viewpointCandidates(shooter, range)) do
            local d = IsoUtils.DistanceTo(c.x, c.y, px, py) - c.r
            if d <= F.VP_ASSIST.cursorPick and (not bestD or d < bestD) then best, bestD = c, d end
        end
        if best then return true, best.o, aimHeight(best) end
        return true, nil, nil
    end
    local s = F.viewpointSight(shooter)
    if s then
        local c, h = F.viewpointSightTarget(shooter, range, s)
        if c then return true, c.o, h end
        return true, nil, nil
    end
    local c = F.viewpointAssistTarget(shooter, range)
    if c then return true, c.o, aimHeight(c) end
    return true, nil, nil
end

--- F.aimPoint in ViewPoint's view: the point under a freed cursor; with the bridge, the ground point
--- looked at (if it is within the bow's range) or the line of sight at the bow's range; else straight
--- ahead at the bow's range. nil: not its view.
function F.viewpointAimPoint(shooter, range)
    if not F.viewpointView(shooter) then return nil end
    local px, py
    if shooter:getJoypadBind() == -1 then px, py = F.viewpointCursorPoint() end
    if px then return px, py end
    local s = F.viewpointSight(shooter)
    local d = range
    if s then
        local g = groundAt(s)
        if g and g < range * F.PROJ.maxRangeMul then d = math.max(F.VP_SIGHT.minAlong, g) end
        return s.x + s.fx * d, s.y + s.fy * d
    end
    local fwd = shooter:getForwardDirection()
    return shooter:getX() + fwd:getX() * d, shooter:getY() + fwd:getY() * d
end

--- With the bridge, the height (m) the line of sight is at over (tx, ty): the shot with nothing hit
--- crosses it there (on the ground where it looks down at it). nil: no bridge or not ViewPoint's view.
function F.viewpointAimHeight(shooter, tx, ty)
    if not F.viewpointView(shooter) then return nil end
    if shooter:getJoypadBind() == -1 and F.viewpointCursorPoint() then return nil end
    local s = F.viewpointSight(shooter)
    if not s then return nil end
    local d = IsoUtils.DistanceTo(tx, ty, s.x, s.y)
    return math.max(0, math.min(F.VP_SIGHT.farH, s.eyeH + d * s.tanP))
end

--[[
    Arrows in flight in ViewPoint's view. Fletcher draws a flight as a copy of the arrow dropped on the
    square under it and moved every tick (client/Fletcher/Flight.lua); ViewPoint only picks a new world
    item up when it next rebuilds that part of the world (1-3 s, and only if the square is in view), so
    such an arrow was never drawn. An item it already knows is drawn wherever its offsets put it, every
    frame. So a pool of display-only items (an arrow and its streak per slot) waits under the floor of
    the player's square, added there while the camera can see it; a flight takes a slot that is old
    enough to be known, moves it in place, and gives it back when it lands. No free slot (or no
    ViewPoint): the usual drawing. The pool is local: never sent, so other players never see it
    (tests/mp_vp_pool.lua: the server's changes to its square leave it alone; a chunk reload removes
    it, and it's built again). After a walk a new pool is built and takes over once it's known.
    ViewPoint 0.1.6 draws new items at once, up to one floor up (checked on the Deck, 2026-10-11): with it
    (F.viewpointDrawsNewItems) there is no pool, only the usual drawing, held under that (F.viewpointDrawMaxH).
]]

require "ISUI/ISInventoryPage"

F.VP_POOL = {
    size = 4,           -- flights at once (own, other players', traps); more use the usual drawing
    settleMs = 3500,    -- a pool this young isn't used yet (ViewPoint hasn't picked it up)
    regrid = 3,         -- tiles from the pool's square before a new one is built where the player is
    parkZ = -0.5,       -- parked under the floor (floors)
    maxH = 1.32,        -- drawn no higher than this (metres over the floor): ViewPoint 0.1.5 doesn't draw a
                        -- world item more than about 0.45 of a floor (1.35 m) up, at any distance (measured
                        -- on the Deck, 2026-10-09). Only the look: the flight keeps its real height.
    streakFrom = 5,     -- the streak shows once the arrow is this many tiles out (closer, its near end is
                        -- at the camera: a thick white beam; the arrow alone shows there)
    checkMs = 250,
    arrow = "Fletcher.FlightArrow",
}

local function slotItems(s) return { s.arrow, s.streak } end

local function clearPool(pool)
    if not pool then return end
    for _, s in ipairs(pool.slots) do
        for _, it in ipairs(slotItems(s)) do
            local wo = it:getWorldItem()
            local sq = wo and wo:getSquare()
            if sq then pcall(function() sq:removeWorldObject(wo) end) end
        end
    end
end

local function park(pool, s)
    for _, it in ipairs(slotItems(s)) do
        local wo = it:getWorldItem()
        if wo then wo:setOffX(pool.ox); wo:setOffY(pool.oy); wo:setOffZ(F.VP_POOL.parkZ) end
    end
end

local function intact(pool)
    local list = pool.sq:getWorldObjects()
    for _, s in ipairs(pool.slots) do
        for _, it in ipairs(slotItems(s)) do
            local wo = it:getWorldItem()
            if not (wo and list:contains(wo)) then return false end
        end
    end
    return true
end

local function inUse(pool)
    for _, s in ipairs(pool.slots) do if s.flight then return true end end
    return false
end

local function ready(pool, now)
    return pool ~= nil and (now or getTimestampMs()) - pool.born >= F.VP_POOL.settleMs
end

--- A new pool under the player's square (not yet in use: F.vpPoolNext until it is known)
function F.viewpointPoolBuild(player)
    local sq = player and player:getCurrentSquare()
    if not sq then return nil end
    local V, P = F.FLIGHT_VIS, F.VP_POOL
    local pool = { sq = sq, born = getTimestampMs(), slots = {},
                   ox = player:getX() - sq:getX(), oy = player:getY() - sq:getY() }
    for _ = 1, P.size do
        local s = { arrow = instanceItem(P.arrow), streak = instanceItem(V.streak or "Fletcher.FlightStreak") }
        s.streak:setWorldScale(V.streakScale)
        for _, it in ipairs(slotItems(s)) do
            it:getModData().fl_vpPool = true
            sq:AddWorldInventoryItem(it, pool.ox, pool.oy, P.parkZ, false)
        end
        table.insert(pool.slots, s)
    end
    return pool
end

--- Remove every pool (the view went back to iso; tests)
function F.viewpointPoolClear()
    clearPool(F.vpPool); clearPool(F.vpPoolNext)
    F.vpPool, F.vpPoolNext = nil, nil
end

--- Keep the pool (every F.VP_POOL.checkMs): built while ViewPoint's view is on, rebuilt after a walk or a
--- chunk reload (the new one takes over once it's known and no flight uses the old one), gone in iso.
function F.viewpointPoolTick()
    local now = getTimestampMs()
    if F.vpPoolCheckAt and now < F.vpPoolCheckAt then return end
    F.vpPoolCheckAt = now + F.VP_POOL.checkMs
    local player = getPlayer()
    local on = player and not player:isDead() and F.viewpointView(player) and not F.viewpointDrawsNewItems()
    local pool, nextPool = F.vpPool, F.vpPoolNext
    if not on then
        if not (pool and inUse(pool)) then F.viewpointPoolClear() end
        return
    end
    if pool and not intact(pool) and not inUse(pool) then clearPool(pool); F.vpPool, pool = nil, nil end
    if nextPool and not intact(nextPool) then clearPool(nextPool); F.vpPoolNext, nextPool = nil, nil end
    local far = pool and (math.floor(player:getZ()) ~= pool.sq:getZ()
        or IsoUtils.DistanceTo(player:getX(), player:getY(), pool.sq:getX() + 0.5, pool.sq:getY() + 0.5) > F.VP_POOL.regrid)
    if (not pool or far) and not nextPool then
        F.vpPoolNext = F.viewpointPoolBuild(player)
        nextPool = F.vpPoolNext
    end
    if nextPool and ready(nextPool, now) and not (pool and inUse(pool)) then
        clearPool(pool)
        F.vpPool, F.vpPoolNext = nextPool, nil
    end
end

--- A flight starting (Flight.lua): take a free slot of a known pool for its drawing. Fills f.vis with
--- the slot's pieces (the arrow's model set to `arrowType`, the streak's to `streakType`). False: no
--- ViewPoint view or no free slot (the usual drawing).
function F.viewpointPoolTake(f, arrowType, streakType)
    local pool = F.vpPool
    if F.viewpointDrawsNewItems() then return false end      -- (0.1.6+: the usual drawing shows)
    if not (ready(pool) and F.viewpointView(getPlayer())) then return false end
    for _, s in ipairs(pool.slots) do
        if not s.flight then
            local sm = getScriptManager()
            local a = arrowType and sm:FindItem(arrowType)
            local am = a and a:getWorldStaticModel()
            if am then s.arrow:setWorldStaticModel(am) end
            local st = streakType and sm:FindItem(streakType)
            local stm = st and st:getWorldStaticModel()
            if stm then s.streak:setWorldStaticModel(stm) end
            s.flight = f
            f.vpSlot = s
            f.vis = { { item = s.arrow, pooled = s, pool = pool } }
            if F.FLIGHT_VIS.streak then
                table.insert(f.vis, { item = s.streak, turn = F.FLIGHT_VIS.streakYaw, pooled = s, pool = pool })
            end
            return true
        end
    end
    return false
end

--- Draw one pooled piece at (x, y, level z, h metres up), turned to yaw / pitch (Flight.lua's visPlace)
function F.viewpointPoolPlace(v, x, y, z, h, yaw, pitch)
    local wo = v.item:getWorldItem()
    local sq = v.pool.sq
    if not wo then return end
    local f = v.pooled.flight
    local start = type(f) == "table" and f.path and f.path[1]
    if v.turn and start and IsoUtils.DistanceTo(x, y, start.x, start.y) < F.VP_POOL.streakFrom then
        wo:setOffX(v.pool.ox); wo:setOffY(v.pool.oy); wo:setOffZ(F.VP_POOL.parkZ)   -- (streak: not yet)
        return
    end
    local maxH = F.VP_POOL.maxH
    if h > maxH then h, pitch = maxH, 0 end         -- (above ViewPoint's limit: drawn level at it)
    v.item:setWorldZRotation(yaw)
    v.item:setWorldYRotation(pitch)
    wo:setOffX(x - sq:getX())
    wo:setOffY(y - sq:getY())
    wo:setOffZ((z - sq:getZ()) + math.max(0, h / F.FLIGHT_VIS.levelH))
end

--- A pooled flight is over: its slot goes back under the floor
function F.viewpointPoolRelease(v)
    local s = v.pooled
    if not s or not s.flight then return end
    s.flight = nil
    park(v.pool, s)
end

--- Pool items never show in the inventory's floor list
function F.viewpointPoolHide(page)
    local fc = ISInventoryPage.GetFloorContainer(page.player)
    if not fc then return end
    for _, pool in ipairs({ F.vpPool, F.vpPoolNext }) do
        for _, s in ipairs(pool and pool.slots or {}) do
            for _, it in ipairs(slotItems(s)) do
                if fc:contains(it) then fc:Remove(it) end
            end
        end
    end
end

if not ISInventoryPage.fl_vpPoolWrapped then
    local refresh = ISInventoryPage.refreshBackpacks
    ISInventoryPage.refreshBackpacks = function(self, ...)
        local r = refresh(self, ...)
        if F.viewpointPoolHide and (F.vpPool or F.vpPoolNext) then pcall(F.viewpointPoolHide, self) end
        return r
    end
    ISInventoryPage.fl_vpPoolWrapped = true
end

Events.OnTick.Add(function() if F.viewpointPoolTick then F.viewpointPoolTick() end end)   -- (by name: reloads apply)

return F
