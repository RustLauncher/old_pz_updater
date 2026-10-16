--[[
    Fletcher: true projectiles (single player; multiplayer keeps the vanilla hit, see F.projectileMode).

    The bow still fires through the game's ranged attack (animation, sound, noise, the arrow leaving
    the bow), but its range is cut to F.PROJ.suppressRange so vanilla never finds a target
    (shared/Fletcher/Gear.lua). Vanilla picks its target WHILE AIMING, so nothing later works: a tiny
    range only for the attack, setHitChance(0), emptying the hit list (clearHitInfo) all still let
    vanilla hit a zombie under the cursor; a zero-damage hit still staggers and knocks down; a
    WeaponHitCharacter hook cancels EVERY hit in the game (any handler counts as "cancel"). The red
    reticle vanilla shows on a target in range is drawn by client/Fletcher/AimMark.lua instead,
    from the same F.cursorTarget the shot uses.
    The arrow then flies here: aimed at the cursor point (or straight ahead
    on a controller) with a spread from the shot's hit chance (wider past the effective range), on the
    ballistic arc that crosses the aim height at the aim point (lobbed up to 45 degrees, out to
    F.PROJ.maxRangeMul x the bow's range), then pulled down by gravity. Each step it can:
      - smash a closed window's glass and fly on, slower (F.edgeAt; boarded windows stop it)
      - stick in a soft wall (plaster, wood) or a closed door; on a hard one (brick, concrete, stone,
        metal: F.HARD_MATERIALS, read from the tile's MaterialType / Material) break, or glance off
        once and end up lying on the ground; slip through chain-link now and then
      - clear a hoppable fence when high enough, and walls / trees on a high lob (which may come down
        on a roof)
      - stop in a tree (F.PROJ.treeChance per tree square)
      - hit a zombie whose body it passes through (height bands: head / body / legs; a zombie on the
        ground is only low), or an animal (its size; vital top quarter), through the game's own Hit
        (stagger, knockdown, death, an animal bolting, all vanilla)
      - land on the ground (hard ground: skid on, or break)
    What becomes of the arrow (stuck in the zombie, into the corpse, on the ground, broken) and the XP
    go through F.resolveShot (shared/Fletcher/Shots.lua), like the vanilla-hit path.
    Units: tiles across (about metres), metres up (h), seconds. client/Fletcher/Flight.lua flies the
    arrow you see; F.simulate runs a whole flight at once (tests).
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Gear"
require "Fletcher/Shots"
local F = Fletcher

F.PROJ = {
    speed = { bow = 40, crossbow = 50 },   -- tiles per second (def.speed overrides)
    gravity = 9.8,
    releaseH = 1.45,          -- arrow height at release
    aimH = 1.15,              -- the archer aims to cross this height at the aim point
    maxPitch = 45,            -- degrees up, at most (a lob: the farthest an arrow goes)
    maxRangeMul = 2,          -- a lob reaches up to this times the bow's (effective) range
    longSpread = 1.5,         -- extra spread per bow-range of distance past the effective range
    step = 0.2,               -- tiles per simulation step
    maxTime = 8.0,            -- (a long lob is in the air a few seconds)
    radius = 0.3,             -- a body, around its centre
    bodyTop = 1.85, proneTop = 0.45,
    headH = 1.55, legsH = 0.55,   -- (head band 0.3 m: a headshot has to be earned)
    pitchSpread = 0.7,            -- vertical spread, as a share of the sideways spread
    vital = 2.0,              -- an animal's head / heart-lung zone (its top quarter)
    head = 3.0, legs = 0.6,   -- damage multipliers (a headshot should usually drop a zombie)
    treeChance = 0.35,
    treeTop = 6.0,            -- a lob above this flies over trees
    wallTop = 2.6,            -- ... above this, over walls and fences (and lands on a roof)
    sillH = 0.8, windowTop = 2.1,   -- a window's glass, metres up
    glassKeep = 0.8,          -- speed kept through a pane
    glassDeflect = 4,         -- degrees, either way
    hardBreak = 0.4,          -- chance (x the arrow's breakage) of breaking on brick / stone / metal
    groundBreak = 0.2,        -- ... on concrete / asphalt / gravel ground
    glanceKeep = 0.3, glanceKeepUp = 0.4, glanceDeflect = 20,   -- a glancing arrow: much slower, off-line
    meshPass = 0.35,          -- chance an arrow goes through chain-link mesh
    skidMin = 0.3, skidMax = 1.0,   -- tiles an arrow skids on hard ground
    fenceClear = 1.0,         -- an arrow higher than this flies over a hoppable fence
    spreadPerMiss = 0.035,    -- degrees of spread per point of hit chance under 100 (0.05 felt like
                              -- missing with the reticle on the target: 39 percent at 10 tiles, Archery 0)
    minSpread = 0.75,         -- even a master archer's arrows wander a little (headshots at range stay earned)
    movingSpread = 1.6,
    suppressRange = 0.5,      -- the bow's vanilla range while projectiles are on
    bury = 0.08,              -- how far a head goes into a wall
    floorM = 3.0,             -- metres per floor on screen (a 1.8 m body is about 0.6 of one)
    pickWidth = 0.35,         -- a body's half-width for the cursor, in tiles
}

--- True projectiles run in single player with the sandbox option on (default).
function F.projectileMode()
    -- multiplayer too (2026-10-08): the shooter's client flies the arrow and reports the outcome; the
    -- server checks it and makes it so (client/Fletcher/NetFlight.lua, server/Fletcher/Server.lua)
    local sv = SandboxVars and SandboxVars.Fletcher
    return not (sv and sv.TrueProjectiles == false)
end

F.ARROW_LEN = { arrow = 0.42, bolt = 0.21 }    -- model lengths (animation/build/models/*.json)

-- What an arrow struck. Walls carry MaterialType (Brick, Concrete, Cinderblock, Plaster, Wood...),
-- fences and bars Material / Material2 (MetalWire, MetalBars...), floors FootstepMaterial (Grass,
-- Gravel, Concrete, Wood, Carpet...); streets and boulders have none (named by their tile sheet).
-- Hard ones: the arrow breaks or glances off; soft ones: it sticks.
F.HARD_MATERIALS = {
    Brick = true, Concrete = true, Cinderblock = true, Stone = true, Rock = true, Asphalt = true,
    Gravel = true, Tile = true, Marble = true, Metal = true, MetalWire = true, MetalBars = true,
    MetalSheet = true, MetalPlate = true, Steel = true,
}
F.MATERIAL_BY_SHEET = {        -- tile sheet name fragments, for tiles without a material
    { "street", "Asphalt" }, { "boulder", "Stone" }, { "rocks", "Stone" }, { "metal", "Metal" },
    { "brick", "Brick" }, { "concrete", "Concrete" }, { "garage", "Concrete" },
}

local function spriteMaterial(obj, keys)
    local sp = obj and obj:getSprite()
    if not sp then return nil end
    local pr = sp:getProperties()
    for _, k in ipairs(keys) do
        local v = pr:get(k)
        if v and v ~= "" then return v end
    end
    local name = (sp:getName() or ""):lower()
    for _, m in ipairs(F.MATERIAL_BY_SHEET) do
        if name:find(m[1], 1, true) then return m[2] end
    end
    return nil
end

local WALL_FLAGS = { "collideW", "collideN", "WallW", "WallN", "WallNW", "HoppableN", "HoppableW", "WallSE" }
local function isWallish(obj)
    local sp = obj:getSprite()
    if not sp then return false end
    local pr = sp:getProperties()
    for _, f in ipairs(WALL_FLAGS) do
        local flag = IsoFlagType[f]
        if flag and pr:has(flag) then return true end
    end
    return false
end

--- The material of whatever stands between two neighbouring squares (wall, fence, bars), or nil
function F.edgeMaterial(a, b)
    for _, sq in ipairs({ b, a }) do
        local objs = sq and sq:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
            local o = objs:get(i)
            if isWallish(o) then
                local m = spriteMaterial(o, { "MaterialType", "Material", "Material2" })
                if m then return m end
            end
        end
    end
    return nil
end

--- The material of a square's floor, or nil
function F.floorMaterial(sq)
    return sq and sq:getFloor() and spriteMaterial(sq:getFloor(), { "FootstepMaterial", "MaterialType", "Material" }) or nil
end

function F.isHard(material) return material ~= nil and F.HARD_MATERIALS[material] == true end

-- tests: F.PROJ_NO_SPREAD = true aims exactly; F.PROJ_RAND = function() return 0..1 end
local function rand() return F.PROJ_RAND and F.PROJ_RAND() or ZombRandFloat(0, 1) end
local function gauss()
    if F.PROJ_NO_SPREAD then return 0 end
    local u = math.max(1e-6, rand())
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rand())
end

--- The sandbox "Arrow Spread" multiplier (Fletcher.ArrowSpread; 1 if unset)
function F.spreadSetting()
    local v = SandboxVars and SandboxVars.Fletcher and tonumber(SandboxVars.Fletcher.ArrowSpread)
    return v and math.max(0.25, math.min(3, v)) or 1
end

--- Spread (degrees, one sigma) of a shot
function F.shotSpread(shooter, stats)
    local s = math.max(F.PROJ.minSpread, (100 - (stats.hitChance or 50)) * F.PROJ.spreadPerMiss)
    if shooter and shooter.isPlayerMoving and shooter:isPlayerMoving() then s = s * F.PROJ.movingSpread end
    if shooter and shooter.getVariableBoolean and shooter:getVariableBoolean("FletcherBowTired") then s = s * 1.3 end
    if shooter and F.aimSteadiness then s = s * F.aimSteadiness(shooter) end   -- (client: AimMark.lua)
    return s * F.moodleSpread(shooter) * F.spreadSetting() * (stats.spreadMul or 1)
end

-- Moodles widen the spread, like vanilla's to-hit penalties for guns (CombatManager.getMoodlesPenalty
-- and getPainPenalty: panic, stress, tired, endurance, drunk, pain): + this much per moodle level (0-4)
F.MOODLE_SPREAD = { PANIC = 0.15, STRESS = 0.05, TIRED = 0.08, ENDURANCE = 0.12, DRUNK = 0.15, PAIN = 0.10 }

--- How much the shooter's moodles widen the spread (1 = not at all)
function F.moodleSpread(shooter)
    local m = shooter and shooter.getMoodles and shooter:getMoodles()
    if not m then return 1 end
    local k = 1
    for name, per in pairs(F.MOODLE_SPREAD) do
        local t = MoodleType and MoodleType[name]
        if t then
            local ok, lvl = pcall(function() return m:getMoodleLevel(t) end)
            if ok and lvl then k = k + per * lvl end
        end
    end
    return k
end

local function onGround(z)
    local ok, v = pcall(function() return z:isOnFloor() end)
    if ok and v then return true end
    return z:isProne() or z:isCrawling() or z:isKnockedDown()
end

--- Where something we can aim at stands: a character, or an archery target (a world item)
function F.targetXY(o)
    if instanceof(o, "IsoWorldInventoryObject") then
        local sq = o:getSquare()
        return sq:getX() + o:getOffX(), sq:getY() + o:getOffY(), sq:getZ()
    end
    return o:getX(), o:getY(), o:getZ()
end

--- A player (a person: animals are IsoPlayers too, which instanceof "IsoPlayer" doesn't tell apart)
function F.isPerson(o)
    return o ~= nil and instanceof(o, "IsoPlayer") and not instanceof(o, "IsoAnimal")
end

--- May this shooter's arrow hurt that player? Vanilla's rule: in multiplayer the server's PVP
--- option, both players' PvP safety off and neither in a non-PvP zone (CombatManager.checkPVP isn't
--- exposed to Lua on a dedicated server or its clients); in a local game, split-screen co-op PvP.
--- (No call that can throw: Kahlua logs an error for every exception, even one pcall catches.)
function F.canShootPlayer(shooter, target)
    if not (target and instanceof(target, "IsoPlayer")) or target == shooter then return false end
    if instanceof(target, "IsoAnimal") then return true end
    if CombatManager and CombatManager.checkPVP then
        local ok, v = pcall(function() return CombatManager.checkPVP(shooter, target, false) end)
        if ok and v ~= nil then return v == true end
    end
    if isClient() or isServer() then
        local so = getServerOptions and getServerOptions()
        if not (so and so:getBoolean("PVP")) then return false end
        for _, p in ipairs({ shooter, target }) do
            local safety = p and p.getSafety and p:getSafety()
            if safety and safety:isEnabled() then return false end
            if NonPvpZone and NonPvpZone.getNonPvpZone and p
                    and NonPvpZone.getNonPvpZone(math.floor(p:getX()), math.floor(p:getY())) then
                return false
            end
        end
        return true
    end
    return IsoPlayer.getCoopPVP and IsoPlayer.getCoopPVP() == true
end

--- The other players a shooter can see here (split-screen players; online players in multiplayer)
local function otherPlayers(shooter)
    local out = {}
    local ok, online = pcall(function() return getOnlinePlayers and getOnlinePlayers() end)
    if ok and online and online:size() > 0 then
        for i = 0, online:size() - 1 do local p = online:get(i); if p ~= shooter then table.insert(out, p) end end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and p ~= shooter then table.insert(out, p) end
        end
    end
    return out
end
F.otherPlayers = otherPlayers

--- What's under the mouse and the height on it (metres) the mouse points at, or nil: a zombie, an
--- animal, another player, or an archery target. In the isometric view the ground point under the
--- cursor is well BEHIND a body whose head it is on (or behind the top of a bale), so aiming at that
--- point flew over them: the shot goes at what the player sees instead.
function F.cursorTarget(shooter, range)
    if not (shooter:isLocalPlayer() and getMouseX) then return nil end
    if F.viewpointAim then          -- ViewPoint's 3D view: aim assist (client/Fletcher/Viewpoint.lua)
        local inView, t, h = F.viewpointAim(shooter, range)
        if inView then return t, h end
    end
    if shooter.getJoypadBind and shooter:getJoypadBind() ~= -1 then return nil end
    local pn, z = shooter:getPlayerNum(), math.floor(shooter:getZ())
    local mx, my = getMouseX(), getMouseY()
    local sx, sy = shooter:getX(), shooter:getY()
    local floorPx = isoToScreenY(pn, sx, sy, z + 1) - isoToScreenY(pn, sx, sy, z)       -- negative: up
    local best, bestH, bestFy
    -- top: height (m); widthK: a wider pick on screen (a prone zombie, a long animal, a bale)
    local function consider(o, ox, oy, oz, top, widthK)
        if math.floor(oz) == z and IsoUtils.DistanceTo(ox, oy, sx, sy) <= range + 3 then
            local fx, fy = isoToScreenX(pn, ox, oy, z), isoToScreenY(pn, ox, oy, z)
            local halfW = math.abs(isoToScreenX(pn, ox + F.PROJ.pickWidth, oy - F.PROJ.pickWidth, z) - fx) * widthK
            local headY = fy + floorPx * (top / F.PROJ.floorM)
            local pad = math.abs(floorPx) * 0.06
            if math.abs(mx - fx) <= halfW and my >= headY - pad and my <= fy + pad then
                -- overlapping: the one in front (lower on screen) is the one the player sees
                if not bestFy or fy > bestFy then
                    best, bestFy = o, fy
                    bestH = math.max(0.05, math.min(top, (fy - my) / (fy - headY) * top))
                end
            end
        end
    end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        if not o:isDead() then
            local low = onGround(o)
            consider(o, o:getX(), o:getY(), o:getZ(), low and F.PROJ.proneTop or F.PROJ.bodyTop, low and 2.5 or 1)
        end
    end
    local animals = getCell().getAnimals and getCell():getAnimals()
    for i = 0, (animals and animals:size() or 0) - 1 do
        local a = animals:get(i)
        if not a:isDead() then
            local r, top = F.animalShape(a)
            consider(a, a:getX(), a:getY(), a:getZ(), top, math.max(1, r / F.PROJ.pickWidth * 1.6))
        end
    end
    for _, p in ipairs(otherPlayers(shooter)) do
        if not p:isDead() then consider(p, p:getX(), p:getY(), p:getZ(), F.PROJ.bodyTop, 1) end
    end
    -- archery targets: world items on the squares around the ground point under the cursor (a bale
    -- is low, so that point is never more than a couple of tiles off)
    if F.TARGET then
        local gx, gy = screenToIsoX(pn, mx, my, z), screenToIsoY(pn, mx, my, z)
        if gx and gy then
            local cell = getCell()
            for dx = -2, 2 do for dy = -2, 2 do
                local sq = cell:getGridSquare(math.floor(gx) + dx, math.floor(gy) + dy, z)
                local w = sq and sq:getWorldObjects()
                for i = 0, (w and w:size() or 0) - 1 do
                    local wo = w:get(i)
                    local it = wo:getItem()
                    if it and it:getFullType() == F.TARGET_ITEM then
                        consider(wo, sq:getX() + wo:getOffX(), sq:getY() + wo:getOffY(), z, F.TARGET.top,
                            math.max(F.TARGET.w, F.TARGET.d) / 2 / F.PROJ.pickWidth)
                    end
                end
            end end
        end
    end
    return best, bestH
end

--- Where a shooter aims: the world point under the mouse, or ahead on a controller
function F.aimPoint(shooter, range)
    local z = math.floor(shooter:getZ())
    local usingPad = shooter.getJoypadBind and shooter:getJoypadBind() ~= -1
    if F.viewpointAimPoint and shooter:isLocalPlayer() then      -- (ViewPoint: mouse or controller)
        local vx, vy = F.viewpointAimPoint(shooter, range)
        if vx then return vx, vy end
    end
    if not usingPad and shooter:isLocalPlayer() and getMouseX then
        local mx, my = getMouseX(), getMouseY()
        local wx, wy = screenToIsoX(shooter:getPlayerNum(), mx, my, z), screenToIsoY(shooter:getPlayerNum(), mx, my, z)
        if wx and wy then return wx, wy end
    end
    local d = shooter:getForwardDirection()
    return shooter:getX() + d:getX() * range * 0.6, shooter:getY() + d:getY() * range * 0.6
end

--- A new arrow in flight. opt: { shooter, bow, arrow, fl, tx, ty, aimH, from } (fl: its fletching; target point and height;
--- default: the zombie under the cursor at the height pointed at (F.cursorTarget), else F.aimPoint;
--- from = { x, y, z }: shoot from there instead of the shooter's spot, tests)
function F.newProjectile(opt)
    local shooter, bow = opt.shooter, opt.bow
    local def = F.bowDef(bow) or { kind = "bow", range = 18, damage = { 1, 1.5 }, hit = 50, crit = 10 }
    local stats = F.shotStats(def, opt.level or F.level(shooter), opt.arrow, bow, opt.fl)
    def = stats.seasoned and setmetatable({ range = stats.range }, { __index = def }) or def   -- (seasoned: farther)
    local speed = def.speed or F.PROJ.speed[def.kind] or 40
    local tx, ty, aimH = opt.tx, opt.ty, opt.aimH or F.PROJ.aimH
    if not tx then
        local target, h = F.cursorTarget(shooter, def.range * F.PROJ.maxRangeMul)
        if target then
            tx, ty = F.targetXY(target)
            aimH = h
        else
            tx, ty = F.aimPoint(shooter, def.range)
            -- ViewPoint's view with its camera bridge: the shot crosses the line of sight there
            local vh = F.viewpointAimHeight and F.viewpointAimHeight(shooter, tx, ty)
            if vh then aimH = vh end
            -- a bowfishing arrow pointed at water goes into the water there (Bowfishing.lua)
            if F.isFishingArrow and F.isFishingArrow(opt.arrow) and F.isFishWater(tx, ty) then aimH = 0 end
        end
        F.lastAim = { target = target, h = aimH }
    end
    -- (a trap's shot on a server has no shooter: its launch point is opt.from)
    local x0, y0 = shooter and shooter:getX() or 0, shooter and shooter:getY() or 0
    if opt.from then x0, y0 = opt.from.x, opt.from.y end
    local dx, dy = tx - x0, ty - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then
        local f = shooter:getForwardDirection(); dx, dy, dist = f:getX(), f:getY(), 1
    end
    local yaw = math.atan2(dy, dx)
    -- past the effective range the archer lobs it: harder to place
    local spread = opt.noSpread and 0 or math.rad(F.shotSpread(shooter, stats)) * (1 + math.max(0, dist - def.range) / def.range * F.PROJ.longSpread)
    local releaseH = opt.releaseH or F.PROJ.releaseH
    yaw = yaw + gauss() * spread
    -- the angle that lands it at aimH on the aim point (the low arc of the ballistic solution), out
    -- to maxRangeMul x the bow's range; farther, the 45 degree lob falls short
    local d = math.max(1, math.min(dist, def.range * F.PROJ.maxRangeMul))
    local g, v2 = F.PROJ.gravity, speed * speed
    local disc = v2 * v2 - g * (g * d * d + 2 * (aimH - releaseH) * v2)
    local tanP = disc >= 0 and (v2 - math.sqrt(disc)) / (g * d) or 1
    local pitch = math.min(math.rad(F.PROJ.maxPitch), math.atan(tanP)) + gauss() * spread * F.PROJ.pitchSpread
    local ch = math.cos(pitch)
    local p = {
        shooter = shooter, bow = bow, arrow = opt.arrow, fl = opt.fl, stats = stats, def = def,
        x = x0 + math.cos(yaw) * 0.4, y = y0 + math.sin(yaw) * 0.4,
        z = opt.from and opt.from.z or math.floor(shooter:getZ()),
        h = releaseH, noXp = opt.noXp, trap = opt.trap,
        vx = math.cos(yaw) * speed * ch, vy = math.sin(yaw) * speed * ch, vh = math.sin(pitch) * speed,
        t = 0, hit = {},
        x0 = x0, y0 = y0,                       -- (where it was loosed from: bowfishing's strike test)
    }
    p.sq = getCell():getGridSquare(math.floor(p.x), math.floor(p.y), p.z)
    return p
end

-- distance from point (px, py) to segment (ax, ay)-(bx, by), and how far along it (0..1)
local function segDist(px, py, ax, ay, bx, by)
    local sx, sy = bx - ax, by - ay
    local l2 = sx * sx + sy * sy
    local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * sx + (py - ay) * sy) / l2)) or 0
    local cx, cy = ax + sx * t, ay + sy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), t
end


-- Animals (B42 hunting): radius from vanilla's AnimalDefinitions collisionSize (0 for chicks, rats and
-- mice: F.ANIMAL_MIN_R), body height per type (metres, a grown one). The top quarter is the vital
-- zone (head / heart-lung shot: F.PROJ.vital); no legs zone.
F.ANIMAL_TOP = {
    buck = 1.3, doe = 1.2, fawn = 0.85, cow = 1.5, bull = 1.6, cowcalf = 1.0, sow = 0.9, boar = 0.95,
    piglet = 0.45, ewe = 0.9, ram = 0.95, lamb = 0.6, rabbuck = 0.3, rabdoe = 0.3, rabkitten = 0.18,
    hen = 0.45, cockerel = 0.5, chick = 0.15, turkeyhen = 0.8, gobblers = 0.9, turkeypoult = 0.35,
    raccoonboar = 0.4, raccoonsow = 0.4, raccoonkit = 0.25, rat = 0.12, ratfemale = 0.12, ratbaby = 0.08,
    mouse = 0.08, mousefemale = 0.08, mousepups = 0.05,
}
F.ANIMAL_MIN_R = 0.12

--- An animal's hit shape: radius, body top (metres)
function F.animalShape(a)
    local t = a.getAnimalType and a:getAnimalType() or ""
    local def = AnimalDefinitions and AnimalDefinitions.animals and AnimalDefinitions.animals[t]
    local r = def and tonumber(def.collisionSize) or 0.3
    return math.max(F.ANIMAL_MIN_R, r), F.ANIMAL_TOP[t] or 0.8
end

--- The first zombie or animal the segment passes through (at the heights h0 -> h1), or nil. The
--- cell's lists, not squares: a character's square can lag a tile behind where it is.
local function targetOnPath(p, x1, y1, h1)
    local best, bestT
    local minX, maxX = math.min(p.x, x1) - 1, math.max(p.x, x1) + 1
    local minY, maxY = math.min(p.y, y1) - 1, math.max(p.y, y1) + 1
    local function try(o, radius, top)
        local ox, oy = o:getX(), o:getY()
        if ox >= minX and ox <= maxX and oy >= minY and oy <= maxY and math.floor(o:getZ()) == p.z
                and not o:isDead() and not p.hit[o] then
            local d, t = segDist(ox, oy, p.x, p.y, x1, y1)
            if d <= radius then
                local h = p.h + (h1 - p.h) * t
                if h >= 0 and h <= top and (not bestT or t < bestT) then best, bestT = o, t end
            end
        end
    end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        try(o, F.PROJ.radius, onGround(o) and F.PROJ.proneTop or F.PROJ.bodyTop)
    end
    local animals = getCell().getAnimals and getCell():getAnimals()
    for i = 0, (animals and animals:size() or 0) - 1 do
        local a = animals:get(i)
        local r, top = F.animalShape(a)
        try(a, r, top)
    end
    if p.shooter then
        for _, o in ipairs(otherPlayers(p.shooter)) do
            if F.canShootPlayer(p.shooter, o) then try(o, F.PROJ.radius, F.PROJ.bodyTop) end
        end
    end
    return best, bestT
end

--- What stands between neighbouring squares a and b for an arrow at height h: nil (clear) or
--- { what = "wall" | "glass" | "boards", material, window }
local function edgeAt(a, b, h)
    if a == b then return nil end
    if h > F.PROJ.wallTop then return nil end                -- a lob, above the walls
    local win = a:getWindowTo(b) or b:getWindowTo(a)
    if win then
        if h < F.PROJ.sillH or h > F.PROJ.windowTop then return { what = "wall", material = F.edgeMaterial(a, b) } end
        if win:isBarricaded() then return { what = "boards", material = "Wood" } end
        if win:isSmashed() or win:isDestroyed() or win:IsOpen() then return nil end
        return { what = "glass", window = win }
    end
    if a:getWindowThumpableTo(b) or b:getWindowThumpableTo(a) then return { what = "boards", material = "Wood" } end
    if a:isBlockedTo(b) or b:isBlockedTo(a) then
        if (a:isHoppableTo(b) or b:isHoppableTo(a)) and h > F.PROJ.fenceClear then return nil end
        local m = F.edgeMaterial(a, b)
        if m == "MetalWire" and rand() < F.PROJ.meshPass then return nil end     -- through the mesh
        return { what = "wall", material = m }
    end
    return nil
end
F.edgeAt = edgeAt

-- Archery targets (Fletcher.ArcheryTarget lying in the world): a straw bale as drawn. The model
-- (bow_models.py target_model, 0.9 x 0.45 x 0.6 high) x its block's scale 0.7 (Fletcher_Items.txt):
-- across the faces w and face to face d in tiles; its top in shot heights (zombie-sized metres), where
-- a model unit stands ~1.8 high (measured against the character). The model's +Z (a face) points
-- along world angle (rotation - 90), like the arrows' (Flight.lua yawOffset).
F.TARGET_ITEM = "Fletcher.ArcheryTarget"
F.TARGET = { w = 0.63, d = 0.32, top = 0.75 }

--- Where the segment (x0, y0) -> (x1, y1) enters the target's footprint: t in [0, 1], or nil
function F.targetEntry(cx, cy, rotDeg, x0, y0, x1, y1)
    local a = math.rad(rotDeg - 90)
    local ez, ex = { math.cos(a), math.sin(a) }, { -math.sin(a), math.cos(a) }
    local function frame(x, y) local dx, dy = x - cx, y - cy; return dx * ex[1] + dy * ex[2], dx * ez[1] + dy * ez[2] end
    local u0, v0 = frame(x0, y0)
    local u1, v1 = frame(x1, y1)
    local lo, hi = 0, 1
    for _, s in ipairs({ { u0, u1 - u0, F.TARGET.w / 2 }, { v0, v1 - v0, F.TARGET.d / 2 } }) do
        local o, dd, half = s[1], s[2], s[3]
        if math.abs(dd) < 1e-9 then
            if math.abs(o) > half then return nil end
        else
            local ta, tb = (-half - o) / dd, (half - o) / dd
            if ta > tb then ta, tb = tb, ta end
            lo, hi = math.max(lo, ta), math.min(hi, tb)
            if lo > hi then return nil end
        end
    end
    return lo
end

--- The nearest archery target the step from p to (x1, y1, h1) runs into, or nil: (worldObject, t).
--- A bale is about a tile across, so it can stand over the squares next to its own: those are searched.
local function targetItemOnPath(p, x1, y1, h1)
    local cell = getCell()
    local seen, best, bestT = {}, nil, nil
    local function scan(sq)
        if not sq or seen[sq] then return end
        seen[sq] = true
        local w = sq:getWorldObjects()
        for i = 0, (w and w:size() or 0) - 1 do
            local wo = w:get(i)
            local it = wo:getItem()
            if it and it:getFullType() == F.TARGET_ITEM then
                local t = F.targetEntry(sq:getX() + wo:getOffX(), sq:getY() + wo:getOffY(), it:getWorldZRotation(), p.x, p.y, x1, y1)
                local h = t and p.h + (h1 - p.h) * t
                if h and h >= 0 and h <= F.TARGET.top and (not bestT or t < bestT) then best, bestT = wo, t end
            end
        end
    end
    scan(p.sq)
    local bx, by = math.floor(x1), math.floor(y1)
    for dx = -1, 1 do for dy = -1, 1 do scan(cell:getGridSquare(bx + dx, by + dy, p.z)) end end
    return best, bestT
end

local function turnBy(p, deg, keep, keepUp)
    local a = math.rad(deg)
    local c, sn = math.cos(a), math.sin(a)
    p.vx, p.vy = (p.vx * c - p.vy * sn) * keep, (p.vx * sn + p.vy * c) * keep
    p.vh = p.vh * (keepUp or keep)
end

--- How likely this arrow breaks on a hard surface (base x the arrow type's and its fletching's breakage)
function F.hardBreakChance(p, base)
    local def = F.ARROW_DEFS[p.arrow or ""]
    local fb = F.fletchDef and F.fletchDef(p.fl).breakage or 1
    return base * (def and def.breakage or 1) * fb
end

--- One step of flight (dt seconds). Returns nil while flying, else the outcome table:
--- { kind = "zombie" | "wall" | "tree" | "ground" | "roof" | "broke" | "vehicle" | "lost", x, y, z, h,
---   target?, material?, hard?, skid? }. On the way it may smash a window (p.glass) or glance off
--- a hard wall once (p.glanced: the next stop doesn't stick).
function F.stepProjectile(p, dt)
    local cell = getCell()
    local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local n = math.max(1, math.ceil(speed * dt / F.PROJ.step))
    local sdt = dt / n
    for _ = 1, n do
        local x1, y1 = p.x + p.vx * sdt, p.y + p.vy * sdt
        local vh1 = p.vh - F.PROJ.gravity * sdt
        local h1 = p.h + (p.vh + vh1) / 2 * sdt
        local z, t = targetOnPath(p, x1, y1, h1)
        if z then
            local hx, hy, hh = p.x + (x1 - p.x) * t, p.y + (y1 - p.y) * t, p.h + (h1 - p.h) * t
            return { kind = "zombie", target = z, x = hx, y = hy, z = p.z, h = hh }
        end
        local moved = true
        local tw, tt = targetItemOnPath(p, x1, y1, h1)
        if tw then
            return { kind = "target", targetItem = tw, x = p.x + (x1 - p.x) * tt, y = p.y + (y1 - p.y) * tt,
                     z = p.z, h = p.h + (h1 - p.h) * tt }
        end
        if h1 <= 0 then
            local f = p.h / math.max(1e-6, p.h - h1)
            local gx, gy = p.x + (x1 - p.x) * f, p.y + (y1 - p.y) * f
            local m = F.floorMaterial(cell:getGridSquare(math.floor(gx), math.floor(gy), p.z))
            if F.isHard(m) and not p.glanced and rand() < F.hardBreakChance(p, F.PROJ.groundBreak) then
                return { kind = "broke", material = m, x = gx, y = gy, z = p.z, h = 0 }
            end
            return { kind = "ground", x = gx, y = gy, z = p.z, h = 0, material = m, skid = F.isHard(m) }
        end
        local sq1 = cell:getGridSquare(math.floor(x1), math.floor(y1), p.z)
        if not sq1 then return { kind = "lost", x = p.x, y = p.y, z = p.z, h = p.h } end
        -- a lob coming down onto a building: it lands on the roof
        if p.h > F.PROJ.wallTop and h1 <= F.PROJ.wallTop and not sq1:isOutside() then
            return { kind = "roof", x = x1, y = y1, z = p.z, h = h1, square = sq1 }
        end
        -- a vehicle on the square it's flying into, below its roof: it stops there (metal: it breaks
        -- or drops at the near side; finishProjectile)
        local veh = sq1 ~= p.sq and sq1:getVehicleContainer() or nil
        if veh and h1 <= F.vehicleTop(veh) then
            return { kind = "vehicle", vehicle = veh, x = p.x, y = p.y, z = p.z, h = p.h }
        end
        if sq1 ~= p.sq and p.sq then
            -- a diagonal move crosses two edges: through the x neighbour, then on
            local via = cell:getGridSquare(math.floor(x1), math.floor(p.y), p.z)
            local edges
            if via and via ~= p.sq and via ~= sq1 then
                edges = { { p.sq, via, "x" }, { via, sq1, "y" } }
            else
                edges = { { p.sq, sq1, math.floor(x1) ~= math.floor(p.x) and "x" or "y" } }
            end
            for _, e in ipairs(edges) do
                local hit = moved and edgeAt(e[1], e[2], h1)
                if hit and hit.what == "glass" then
                    -- through the pane: it breaks (the game's own smash: glass, sound), the arrow slows
                    pcall(function() hit.window:smashWindow() end)
                    p.glass = (p.glass or 0) + 1
                    turnBy(p, (rand() * 2 - 1) * F.PROJ.glassDeflect, F.PROJ.glassKeep)
                elseif hit and hit.what == "wall" and F.isHard(hit.material) and not p.glanced then
                    if rand() < F.hardBreakChance(p, F.PROJ.hardBreak) then
                        return { kind = "broke", material = hit.material, x = p.x, y = p.y, z = p.z, h = p.h }
                    end
                    -- glances off: bounced back across the face it struck, much slower
                    p.impact = p.impact or { x = p.x, y = p.y, h = p.h }      -- (the trail ends here)
                    if e[3] == "x" then p.vx = -p.vx else p.vy = -p.vy end
                    turnBy(p, (rand() * 2 - 1) * F.PROJ.glanceDeflect, F.PROJ.glanceKeep, F.PROJ.glanceKeepUp)
                    p.glanced, p.glancedOn = true, hit.material
                    moved = false
                elseif hit then
                    return { kind = "wall", x = p.x, y = p.y, z = p.z, h = p.h, square = sq1,
                             material = hit.material, hard = F.isHard(hit.material) }
                end
            end
            if moved and sq1:getTree() and h1 < F.PROJ.treeTop and rand() < F.PROJ.treeChance then
                return { kind = "tree", x = x1, y = y1, z = p.z, h = h1, square = sq1 }
            end
            if moved then p.sq = sq1 end
        end
        if moved then
            p.x, p.y, p.h, p.vh = x1, y1, h1, vh1
        else
            p.vh = p.vh - F.PROJ.gravity * sdt
        end
        p.t = p.t + sdt
        if p.t > F.PROJ.maxTime then return { kind = "ground", x = p.x, y = p.y, z = p.z, h = 0 } end
    end
    return nil
end

--- How high an arrow has to be to clear a vehicle (metres): its script's height, else a car's
F.VEHICLE_TOP = 1.5
function F.vehicleTop(veh)
    local ok, h = pcall(function() return veh:getScript():getExtents():y() end)
    return (ok and h and h > 0.5 and h < 5) and h or F.VEHICLE_TOP
end

-- Stealth shots: a sneaking archer's arrow into a zombie that hasn't noticed them (it isn't targeting
-- them) hits harder and crits more, scaling with Sneaking. Sandbox Fletcher.StealthShots (on).
F.STEALTH = {
    crit = { 10, 1.0 },      -- + crit chance (percent): at Sneaking 0, per level (20 at 10)
    damage = 1.2,            -- damage x this (measured: 25 / 1.5 per level made a Sneaking 10 headshot
                             -- opener 37 percent cheaper in arrows per kill; aim 15-25)
}

--- Does this shot count as a stealth shot? (true / false)
function F.isStealthShot(shooter, target)
    if not (shooter and target and instanceof(target, "IsoZombie")) then return false end
    if SandboxVars and SandboxVars.Fletcher and SandboxVars.Fletcher.StealthShots == false then return false end
    if not (shooter.isSneaking and shooter:isSneaking()) then return false end
    local ok, t = pcall(function() return target:getTarget() end)
    return ok and t ~= shooter
end

--- Extra crit chance a stealth shot gets (percent)
function F.stealthCrit(shooter)
    local L = 0
    pcall(function() L = shooter:getPerkLevel(Perks.Sneak) end)
    return F.STEALTH.crit[1] + F.STEALTH.crit[2] * math.max(0, math.min(10, L))
end

--- Damage of a hit at height h: the bow's damage roll x head / legs x a critical (x a stealth shot's
--- bonus when p.stealth)
function F.projectileDamage(p, target, h)
    local s = p.stats
    local dmg = s.minDamage + (s.maxDamage - s.minDamage) * rand()
    if p.stealth then dmg = dmg * F.STEALTH.damage end
    local zone = "body"
    if instanceof(target, "IsoAnimal") then
        local _, top = F.animalShape(target)
        if h >= top * 0.75 then zone = "vital" end
    elseif onGround(target) then zone = "body"
    elseif h >= F.PROJ.headH then zone = "head"
    elseif h < F.PROJ.legsH then zone = "legs" end
    if zone == "vital" then dmg = dmg * F.PROJ.vital
    elseif zone == "head" then dmg = dmg * F.PROJ.head
    elseif zone == "legs" then dmg = dmg * F.PROJ.legs end
    local crit = rand() * 100 < (s.critChance or 0) + (p.stealth and F.stealthCrit(p.shooter) or 0)
    if crit then
        local m = 2
        if p.bow and p.bow.getCriticalDamageMultiplier then m = math.max(1, p.bow:getCriticalDamageMultiplier()) end
        dmg = dmg * m
    end
    return dmg, zone, crit
end

--- Where a missed arrow comes to rest, as a dropAt (shared/Fletcher/Shots.lua): its nock (the model's
--- pivot) placed so the head is in the wall / tree, or at the landing point on the ground; at the
--- height it struck (floors), turned along its flight
function F.restingPlace(p, out)
    local flat = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local ux, uy = p.vx / math.max(1e-6, flat), p.vy / math.max(1e-6, flat)
    local len = F.ARROW_LEN[(F.ARROW_DEFS[p.arrow or ""] or {}).family or "arrow"] or 0.42
    local tipX, tipY, h, kind, z = out.x, out.y, out.h or 0, nil, out.z
    local sticks = not p.glanced and ((out.kind == "wall" and not out.hard) or out.kind == "tree" or out.kind == "target")
    if sticks and (out.kind == "wall" or out.kind == "target") then
        local bury = out.kind == "target" and 0.06 or (F.PROJ.step * 0.5 + F.PROJ.bury)
        tipX, tipY, kind = out.x + ux * bury, out.y + uy * bury, out.kind
    elseif sticks then
        local sq = out.square or getCell():getGridSquare(math.floor(out.x), math.floor(out.y), out.z)
        if sq then tipX, tipY = sq:getX() + 0.5, sq:getY() + 0.5 end
        kind = "tree"
    elseif out.kind == "roof" then
        -- on the roof: the square above, if there is one to lie on
        h, z = 0, out.z + 1
        local above = getCell():getGridSquare(math.floor(out.x), math.floor(out.y), z)
        if not (above and above:getFloor()) then return nil end
        kind = "roof"
    else
        h = 0
        if out.skid then
            -- hard ground: it skids on a little way (not past anything that blocks)
            local from = getCell():getGridSquare(math.floor(tipX), math.floor(tipY), out.z)
            local d = F.PROJ.skidMin + rand() * (F.PROJ.skidMax - F.PROJ.skidMin)
            local sx, sy = tipX + ux * d, tipY + uy * d
            local to = getCell():getGridSquare(math.floor(sx), math.floor(sy), out.z)
            if from and to and (from == to or not (F.edgeAt(from, to, 0.1))) then tipX, tipY = sx, sy end
        end
    end
    local x, y = tipX - ux * len, tipY - uy * len
    -- the nock's square: an arrow in a wall stays on this side of it; one lying on the ground in its own
    if kind == "wall" or not sticks then
        local sq = getCell():getGridSquare(math.floor(sticks and out.x or tipX), math.floor(sticks and out.y or tipY), z)
        if sq then
            x = math.max(sq:getX() + 0.02, math.min(sq:getX() + 0.98, x))
            y = math.max(sq:getY() + 0.02, math.min(sq:getY() + 0.98, y))
        end
    end
    return { x = x, y = y, z = z, h = math.max(0, h) / F.PROJ.floorM,
             yaw = math.deg(math.atan2(uy, ux)) + 90, kind = kind }
end

--- A zombie the arrow takes in the legs: on `roll`, a crawler (setBecomeCrawler + a knockdown, as a car
--- does; called before the Hit). Not one that is dead or already crawling, or an animal. True when crippled.
function F.cripple(z, roll)
    if not roll or not instanceof(z, "IsoZombie") or z:isDead() or z:isCrawling() or z:isBecomeCrawler() then return false end
    z:setBecomeCrawler(true)
    z:setKnockedDown(true)
    return true
end

--- The arrow's flight is over: apply the hit and settle the arrow. Returns the result string.
function F.finishProjectile(p, out)
    p.outcome = out
    if F.fishingLanded then pcall(F.fishingLanded, p, out) end     -- (bowfishing: the shooter's reel)
    if isClient() and F.netFinish then return F.netFinish(p, out) end     -- (multiplayer: report it)
    if isServer() and F.serverFinish then return F.serverFinish(p, out) end   -- (a server's own shot: a trap)
    local shot = { shooter = p.shooter, arrow = p.arrow, fl = p.fl, x = out.x, y = out.y, z = out.z, dx = p.vx, dy = p.vy, hitH = out.h, lit = p.lit, noXp = p.noXp,
                   noiseAt = { x = out.x, y = out.y, z = out.z } }
    if out.kind == "zombie" then
        local z = out.target
        p.stealth = F.isStealthShot(p.shooter, z)       -- (before the Hit: it turns the zombie)
        local dmg, zone, crit = F.projectileDamage(p, z, out.h)
        p.damage, p.zone, p.crit = dmg, zone, crit
        -- (crippled BEFORE the Hit: flagged after it, the hit's own reaction clears the flag and it gets up)
        if zone == "legs" and F.cripple(z, rand() * 100 < F.crippleChance(p.shooter, p.arrow, crit)) then p.crippled = true end
        if p.bow then pcall(function() z:Hit(p.bow, p.shooter, dmg, false, 1.0, false) end) end
        shot.target = z
    elseif out.kind == "target" then
        shot.practice = true                                   -- in the straw: practice (Shots.lua)
        shot.dropAt = F.restingPlace(p, out)
    elseif out.kind == "vehicle" then
        -- metal: a hard surface's chance to break, else it drops on the near side of the vehicle
        p.impact = p.impact or { x = out.x, y = out.y, h = out.h }
        if rand() < F.hardBreakChance(p, F.PROJ.hardBreak) then
            shot.broken = "Metal"
        else
            shot.dropAt = F.restingPlace(p, { kind = "ground", x = out.x, y = out.y, z = out.z, h = 0 })
            if not shot.dropAt then shot.lost = "vehicle" end
        end
    elseif out.kind == "broke" then
        shot.broken = out.material or true                    -- shattered on stone / metal
    else
        shot.dropAt = F.restingPlace(p, out)
        if not shot.dropAt then shot.lost = out.kind end     -- (on a roof with nothing to lie on)
    end
    local ok, res = pcall(F.resolveShot, shot)
    p.result = ok and res or ("error: " .. tostring(res))
    F.lastShot = p.result
    return p.result
end

--- Fly a whole shot at once (tests; nothing drawn). Returns the projectile with .outcome / .result.
function F.simulate(opt)
    local p = F.newProjectile(opt)
    local out
    for _ = 1, 400 do
        out = F.stepProjectile(p, 1 / 60)
        if out then break end
    end
    out = out or { kind = "lost", x = p.x, y = p.y, z = p.z, h = p.h }
    F.finishProjectile(p, out)
    return p
end

return F
