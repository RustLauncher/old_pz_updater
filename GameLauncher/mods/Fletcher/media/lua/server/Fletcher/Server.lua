--[[
    Fletcher: the server side of multiplayer (a dedicated or hosted server; singleplayer resolves
    everything on the client and never sends these commands).

    Client -> server commands (module "Fletcher"):
      prefer { arrow, family }   the player's arrow / bolt choice (player mod data, read by F.arrowFor when the
                         reload runs here: shared/Fletcher/Reload.lua)
      shot { x, y, z, dx, dy, target? { id, kind, x, y, z } }
                         a bow shot the client saw. The arrow is the SERVER's record of what was
                         nocked (md.fl_nocked on its copy of the bow, set by the reload), spent
                         here: no record, no arrow, so a client can't conjure or upgrade arrows.
                         Resolved after RESOLVE_MS (the hit's damage lands first, so a kill counts):
                         XP (addXp works here), breakage, the arrow into the target or onto the ground.
    Every SYNC_MS: each online player's bow gets its stats (bow + Archery + arrow) and its AmmoType
    on this side too, in case the server's copy is what combat reads.
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Gear"
require "Fletcher/Shots"
require "Fletcher/Reload"
require "Fletcher/FireLight"
local F = Fletcher

if not isServer() then return F end

F.SERVER_RESOLVE_MS = 300
F.SYNC_MS = 1000
F.MAX_SHOT_OFFSET = 3          -- tiles between where the client says it shot from and the player
F.serverShots = F.serverShots or {}
F.shotLog = F.shotLog or {}    -- recent results, newest last (tests read it through the bridge)

local function log(entry)
    entry.t = getTimestampMs()
    table.insert(F.shotLog, entry)
    if #F.shotLog > 50 then table.remove(F.shotLog, 1) end
end

--- The character the client hit, found again here: a zombie by online id near where the client
--- saw it, or a player by online id.
function F.findTarget(t)
    if type(t) ~= "table" or not t.id then return nil end
    if t.kind == "player" then return getPlayerByOnlineID(t.id) end
    local cell = getCell()
    local cx, cy, cz = math.floor(t.x or 0), math.floor(t.y or 0), math.floor(t.z or 0)
    for dx = -2, 2 do
        for dy = -2, 2 do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            local objs = sq and sq:getMovingObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoZombie") and o:getOnlineID() == t.id then return o end
            end
        end
    end
    return nil
end

--- The corpse nearest where the client saw its target (within 1.5 tiles), or nil.
function F.findCorpse(t)
    if type(t) ~= "table" or not t.x then return nil end
    local cell = getCell()
    local best, bestD = nil, 1.5 * 1.5
    local cx, cy, cz = math.floor(t.x), math.floor(t.y), math.floor(t.z or 0)
    for dx = -2, 2 do
        for dy = -2, 2 do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            local bodies = sq and sq:getDeadBodys()
            for i = 0, (bodies and bodies:size() or 0) - 1 do
                local b = bodies:get(i)
                local d = (b:getX() - t.x) ^ 2 + (b:getY() - t.y) ^ 2
                if d <= bestD then best, bestD = b, d end
            end
        end
    end
    return best
end

F.TARGET_WAIT_MS = 1500     -- how long a reported hit may wait for its target (or its corpse) to show up

--- Fill in what the shot hit, as the server sees it now. Returns false to try again later.
function F.settleTarget(s, now)
    local t = s.targetInfo
    if not t then return true end
    local target = F.findTarget(t)
    if target and t.kind == "player" and not F.canShootPlayer(s.shot.shooter, target) then
        s.shot.passedPlayer = true                      -- PvP off (or a safe zone): it flies past them
        return true                                     -- and lands as a miss
    end
    if target and not (target.isDead and target:isDead()) then
        s.shot.target = target
        return true
    end
    if t.kind ~= "player" then
        local body = F.findCorpse(t)
        if body then s.shot.corpse = body; return true end
    end
    if now - s.at < F.TARGET_WAIT_MS then return false end
    s.shot.hit = true                                   -- hit, but its target is gone
    s.shot.dropAt = { x = t.x, y = t.y, z = t.z }
    return true
end

function F.serverShot(player, args)
    local bow = player:getPrimaryHandItem()
    if not F.isBow(bow) then return log({ player = player:getUsername(), result = "rejected: no bow in hand" }) end
    local md = bow:getModData()
    local arrow, fl = md.fl_nocked, md.fl_nockedFletch
    if not arrow then return log({ player = player:getUsername(), result = "rejected: nothing nocked" }) end
    md.fl_nocked, md.fl_nockedFletch = nil, nil
    local x, y = tonumber(args.x) or player:getX(), tonumber(args.y) or player:getY()
    if math.abs(x - player:getX()) > F.MAX_SHOT_OFFSET or math.abs(y - player:getY()) > F.MAX_SHOT_OFFSET then
        x, y = player:getX(), player:getY()
    end
    local dx, dy = tonumber(args.dx) or 0, tonumber(args.dy) or 0
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then dx, dy = dx / len, dy / len end
    local shot = { shooter = player, arrow = arrow, fl = fl, x = x, y = y, z = math.floor(player:getZ()), dx = dx, dy = dy }
    -- a fire arrow is lit here, from the shooter's own lighter / matches (the server's inventory;
    -- the client never lights it in multiplayer): what it hits catches fire, or the spot it lands
    local def = F.ARROW_DEFS[arrow]
    if def and def.fire then
        if F.handLighting and F.handLighting() then shot.lit = F.takeLit(bow) else shot.lit = F.lightFire(player) end
    end
    table.insert(F.serverShots, { at = getTimestampMs(), targetInfo = args.target, shot = shot })
end

-- ---------------------------------------------------------------------------------------------
-- Flying arrows in multiplayer (F.projectileMode): the shooter's client flies the arrow and reports
-- how it ended ("flight", client/Fletcher/NetFlight.lua F.netFinish); this side checks the report and
-- makes it so. Checks: the arrow is the one THIS side recorded as nocked (spent here: no record, no
-- shot); the shot starts at the shooter; it ends within the bow's reach; a hit names a target that
-- is alive here near where the client saw it, or (killed by the shooter's own hit, which can arrive
-- first) one THIS side saw die in the last F.DEATH_KEEP_MS (F.recentDeaths): a report about any
-- other corpse is a miss, so no XP can be made out of corpses. Then: fire, noise, breakage and wear
-- (this side's dice), where the arrow ends up (a wall / tree / the ground at the height and angle it
-- stopped, the straw of an archery target, stuck in the zombie: F.stickInZombie, shown on every
-- client), damage relayed to the client that owns the zombie when the shooter's doesn't ("hit"),
-- the shot replayed on every other client ("flight"). XP: a hit's after F.KILL_WAIT_MS, with the
-- kill's when the zombie died meanwhile.
-- ---------------------------------------------------------------------------------------------
F.FLIGHT_SLACK = 2.5          -- tiles past the bow's farthest lob a report may end
F.TARGET_NEAR = 2.0           -- tiles between where the client hit its target and where it is here
F.DROP_NEAR = 1.5             -- tiles between where it stopped and where the client rests the arrow
F.KILL_WAIT_MS = 1500
F.DEATH_KEEP_MS = 4000
F.recentDeaths = F.recentDeaths or {}    -- zombie online id -> { t, x, y, z }
F.pendingXp = F.pendingXp or {}

local function num(v, default) v = tonumber(v); if v == nil or v ~= v then return default end return v end
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

--- A zombie by online id, alive, within `near` tiles of (x, y) here; or nil
function F.liveZombieNear(id, x, y, near)
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z:getOnlineID() == id then
            if not z:isDead() and dist(z:getX(), z:getY(), x, y) <= near then return z end
            return nil
        end
    end
end

--- An archery target (the placed item) on or next to (x, y, z), or nil
function F.archeryTargetNear(x, y, z)
    for dx = -1, 1 do for dy = -1, 1 do
        local sq = getCell():getGridSquare(math.floor(x) + dx, math.floor(y) + dy, z)
        local w = sq and sq:getWorldObjects()
        for i = 0, (w and w:size() or 0) - 1 do
            local it = w:get(i):getItem()
            if it and it:getFullType() == "Fletcher.ArcheryTarget" then return w:get(i) end
        end
    end end
end

local function sanitizeDrop(d, ox, oy, oz)
    if type(d) ~= "table" then return nil end
    local x, y = num(d.x), num(d.y)
    if not (x and y) or dist(x, y, ox, oy) > F.DROP_NEAR then return nil end
    local kind = (d.kind == "wall" or d.kind == "tree" or d.kind == "target" or d.kind == "roof") and d.kind or nil
    local z = math.floor(num(d.z, oz))
    if math.abs(z - oz) > 1 then z = oz end
    return { x = x, y = y, z = z, h = math.max(0, math.min(1, num(d.h, 0))), yaw = num(d.yaw, 0), kind = kind }
end

function F.serverFlight(player, m)
    local name = player:getUsername()
    local bow = player:getPrimaryHandItem()
    if not F.isBow(bow) then return log({ player = name, result = "rejected: no bow in hand" }) end
    local md = bow:getModData()
    local arrow, fl = md.fl_nocked, md.fl_nockedFletch
    if not arrow then return log({ player = name, result = "rejected: nothing nocked" }) end
    md.fl_nocked, md.fl_nockedFletch = nil, nil
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    local fr = type(m.from) == "table" and m.from or {}
    local fx, fy = num(fr.x, px), num(fr.y, py)
    if dist(fx, fy, px, py) > F.MAX_SHOT_OFFSET then fx, fy = px, py end
    local o = type(m.out) == "table" and m.out or {}
    local ox, oy, oz, oh = num(o.x), num(o.y), math.floor(num(o.z, pz)), num(o.h, 0)
    local def = F.bowDef(bow) or {}
    local stats = F.shotStats(def, F.level(player), arrow, bow, fl)
    local reach = (stats.range or def.range or 20) * F.PROJ.maxRangeMul + F.FLIGHT_SLACK
    local entry = { player = name, arrow = arrow, fl = fl, target = type(m.target) == "table" and m.target.kind or nil }
    if not (ox and oy) or dist(fx, fy, ox, oy) > reach or math.abs(oz - pz) > 2 then
        -- not a shot this bow could make: the arrow drops at the shooter's feet
        local sq = getCell():getGridSquare(math.floor(px), math.floor(py), pz)
        if sq then sq:AddWorldInventoryItem(F.setFletch(instanceItem(arrow), fl), ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0) end
        entry.result = "rejected: out of reach"
        return log(entry)
    end
    local shot = { shooter = player, arrow = arrow, fl = fl, x = ox, y = oy, z = oz, dx = num(fr.vx, 0), dy = num(fr.vy, 0), hitH = oh,
                   noiseAt = { x = ox, y = oy, z = oz } }
    local adef = F.ARROW_DEFS[arrow] or {}
    if adef.fire then
        -- lit by hand before the shot (FireLight.lua: this side's record of the bow), else lit here
        if F.handLighting and F.handLighting() then shot.lit = F.takeLit(bow) else shot.lit = F.lightFire(player) end
    end
    if m.broken then shot.broken = (type(m.broken) == "string" and m.broken ~= "hard") and m.broken or true end
    if m.lost then shot.lost = tostring(m.lost) end
    shot.dropAt = sanitizeDrop(m.dropAt, ox, oy, oz)
    local t = type(m.target) == "table" and m.target or nil
    local hitTarget, killedFirst
    if o.kind == "zombie" and t then
        local id = num(t.id, -1)
        if t.kind == "zombie" then
            local z = F.liveZombieNear(id, num(t.x, ox), num(t.y, oy), F.TARGET_NEAR)
            local death = F.recentDeaths[id]
            if z then
                hitTarget = z
                if not m.applied then
                    sendServerCommand("Fletcher", "hit", { id = id, damage = num(m.damage, 0), cripple = m.cripple == true })
                end
            elseif death and getTimestampMs() - death.t <= F.DEATH_KEEP_MS and dist(death.x, death.y, num(t.x, ox), num(t.y, oy)) <= F.TARGET_NEAR then
                killedFirst = death                                  -- the shooter's own hit killed it
                shot.corpse = F.findCorpse({ x = death.x, y = death.y, z = death.z })
                shot.killed = true
            else
                entry.refused = "no such live target"               -- (a corpse it didn't see die, or nothing)
            end
        elseif t.kind == "player" then
            local victim = getPlayerByOnlineID(id)
            if victim and F.canShootPlayer(player, victim) and dist(victim:getX(), victim:getY(), num(t.x, ox), num(t.y, oy)) <= F.TARGET_NEAR then
                hitTarget = victim
                sendServerCommand(victim, "Fletcher", "hitPlayer", { id = id, damage = num(m.damage, 0), zone = tostring(m.zone),
                    shooter = player:getOnlineID(), bow = bow:getFullType(), arrow = arrow, fl = fl, h = oh,
                    dx = num(fr.vx, 0), dy = num(fr.vy, 0) })
            else
                shot.passedPlayer = true
            end
        elseif t.kind == "animal" then
            local cell = getCell()
            local animals = cell.getAnimals and cell:getAnimals()
            for i = 0, (animals and animals:size() or 0) - 1 do
                local a = animals:get(i)
                if a:getOnlineID() == id and not a:isDead() and dist(a:getX(), a:getY(), num(t.x, ox), num(t.y, oy)) <= F.TARGET_NEAR then hitTarget = a end
            end
        end
        if hitTarget then shot.target = hitTarget end
        if not (hitTarget or killedFirst) then
            -- not a hit after all: it lies on the ground where the client said it stopped
            shot.dropAt = { x = ox, y = oy, z = oz, h = 0, yaw = math.deg(math.atan2(num(fr.vy, 0), num(fr.vx, 1))) + 90 }
        end
        if hitTarget or killedFirst then shot.noXp = true end           -- (paid after F.KILL_WAIT_MS)
    elseif o.kind == "target" then
        local ta = type(m.targetAt) == "table" and m.targetAt or {}
        if F.archeryTargetNear(num(ta.x, ox), num(ta.y, oy), math.floor(num(ta.z, oz))) and shot.dropAt then
            shot.practice = true
        end
    end
    F.lastFire, F.lastStuck = nil, nil
    local ok, res = pcall(F.resolveShot, shot)
    entry.result = ok and res or ("error: " .. tostring(res))
    entry.lit = shot.lit
    entry.found = hitTarget ~= nil or killedFirst ~= nil
    entry.passed = shot.passedPlayer
    entry.fire = F.lastFire and (F.lastFire.target and "target" or (F.lastFire.square and
        (F.lastFire.square:getX() .. "," .. F.lastFire.square:getY()))) or nil
    entry.held = F.heldArrows(shot)
    entry.xp = (not shot.noXp) and F.shotXp(shot) or 0
    entry.dropAt = shot.dropAt and { x = shot.dropAt.x, y = shot.dropAt.y, z = shot.dropAt.z, h = shot.dropAt.h, kind = shot.dropAt.kind } or nil
    entry.stuck = shot.target and F.lastStuck and F.lastStuck.loc or nil
    log(entry)
    if shot.noXp and not shot.noTrapXp then
        table.insert(F.pendingXp, { at = getTimestampMs(), shooter = player, entry = entry, target = hitTarget,
                                    id = t and num(t.id, -1), killed = killedFirst ~= nil })
    end
    -- every other client sees it fly
    sendServerCommand("Fletcher", "flight", { shooter = player:getOnlineID(), x = fx, y = fy, z = pz, h = num(fr.h, F.PROJ.releaseH),
        vx = num(fr.vx, 0), vy = num(fr.vy, 0), vh = num(fr.vh, 0), dur = math.max(0, math.min(10, num(m.flown, 0))),
        ex = ox, ey = oy, eh = oh, arrow = arrow, fl = fl, lit = shot.lit == true })
    return entry
end

--- Hit XP (and the kill's, if it died meanwhile), F.KILL_WAIT_MS after the report
function F.payPendingXp(now)
    for i = #F.pendingXp, 1, -1 do
        local q = F.pendingXp[i]
        if now - q.at >= F.KILL_WAIT_MS then
            table.remove(F.pendingXp, i)
            local killed = q.killed
            if not killed and q.target and instanceof(q.target, "IsoZombie") then
                local d = F.recentDeaths[q.id]
                killed = q.target:isDead() or (d ~= nil and d.t >= q.at)
            end
            local xp = F.XP.shot + F.XP.hit + (killed and F.XP.kill or 0)
            if q.shooter then F.awardXp(q.shooter, xp) end
            q.entry.xp, q.entry.killed = xp, killed
        end
    end
end

--- A zombie died here: remembered (a report of its killing hit may arrive after), and every client
--- drops its stuck-arrow list (the corpse carries the arrows)
function F.onServerZombieDead(z)
    if not z then return end
    local id = z:getOnlineID()
    F.recentDeaths[id] = { t = getTimestampMs(), x = z:getX(), y = z:getY(), z = math.floor(z:getZ()) }
    sendServerCommand("Fletcher", "unstuck", { id = id })
end

-- ---------------------------------------------------------------------------------------------
-- The server's own shots (a tripwire trap, shared/Fletcher/Trap.lua): flown at once here (the same
-- physics), then like a client's report: damage relayed to the zombie's owner, the bolt placed /
-- stuck (shown everywhere), the flight replayed on every client.
-- ---------------------------------------------------------------------------------------------
function F.serverLaunch(opt)
    local p = F.newProjectile(opt)
    local from = { x = p.x, y = p.y, z = p.z, h = p.h, vx = p.vx, vy = p.vy, vh = p.vh }
    local out, flown, dt = nil, 0, 1 / 60
    for _ = 1, 600 do
        out = F.stepProjectile(p, dt)
        flown = flown + dt
        if out then break end
    end
    out = out or { kind = "lost", x = p.x, y = p.y, z = p.z, h = p.h }
    p.netFrom, p.flown = from, flown
    F.finishProjectile(p, out)
    return p
end

function F.serverFinish(p, out)
    local shot = { shooter = p.shooter, arrow = p.arrow, fl = p.fl, x = out.x, y = out.y, z = out.z, dx = p.vx, dy = p.vy, hitH = out.h,
                   lit = p.lit, noXp = p.noXp, noiseAt = { x = out.x, y = out.y, z = out.z } }
    if out.kind == "zombie" then
        local t = out.target
        local dmg, zone, crit = F.projectileDamage(p, t, out.h)
        p.damage, p.zone, p.crit = dmg, zone, crit
        if instanceof(t, "IsoZombie") then
            local okC, chance = pcall(F.crippleChance, p.shooter, p.arrow, crit)
            local cripple = zone == "legs" and okC and ZombRandFloat(0, 100) < chance
            sendServerCommand("Fletcher", "hit", { id = t:getOnlineID(), damage = dmg, cripple = cripple })
        elseif F.isPerson(t) then
            sendServerCommand(t, "Fletcher", "hitPlayer", { id = t:getOnlineID(), damage = dmg, zone = zone,
                shooter = -1, bow = p.bow and p.bow:getFullType() or nil })
        end
        shot.target = t
    elseif out.kind == "target" then
        shot.practice = true
        shot.dropAt = F.restingPlace(p, out)
    elseif out.kind == "vehicle" then
        if ZombRandFloat(0, 1) < F.hardBreakChance(p, F.PROJ.hardBreak) then shot.broken = "Metal"
        else shot.dropAt = F.restingPlace(p, { kind = "ground", x = out.x, y = out.y, z = out.z, h = 0 }) end
    elseif out.kind == "broke" then
        shot.broken = out.material or true
    else
        shot.dropAt = F.restingPlace(p, out)
        if not shot.dropAt then shot.lost = out.kind end
    end
    F.lastFire, F.lastStuck = nil, nil
    local ok, res = pcall(F.resolveShot, shot)
    p.result = ok and res or ("error: " .. tostring(res))
    log({ player = p.trap and "trap" or "server", arrow = p.arrow, result = p.result, target = out.kind,
          found = shot.target ~= nil, stuck = shot.target and F.lastStuck and F.lastStuck.loc or nil,
          xp = 0, x = out.x, y = out.y })
    local fr = p.netFrom or {}
    sendServerCommand("Fletcher", "flight", { shooter = -1, x = fr.x, y = fr.y, z = fr.z, h = fr.h, vx = fr.vx, vy = fr.vy, vh = fr.vh,
        dur = p.flown or 0, ex = out.x, ey = out.y, eh = out.h or 0, arrow = p.arrow, fl = p.fl, lit = p.lit == true })
    F.lastShot = p.result
    return p.result
end

function F.onServerCommand(module, command, player, args)
    if module ~= "Fletcher" or not player then return end
    if command == "prefer" then
        F.setPreferredArrow(player, args and args.arrow, args and args.family)
    elseif command == "flight" then
        F.serverFlight(player, args or {})
    elseif command == "shot" then
        -- (the instant-hit report: only when flying arrows are off; with them on, a "shot" would be a
        -- hit the server can't check)
        if F.projectileMode() then return log({ player = player:getUsername(), result = "rejected: flying arrows are on" }) end
        F.serverShot(player, args or {})
    elseif command == "reel" then
        -- (bowfishing: the shooter's reel ended; the outcome is decided here: Bowfishing.lua)
        if F.reelInFor then F.reelInFor(player, args or {}) end
    end
end

--- How many of the shot's arrow its target or corpse holds: in the inventory, or (a living zombie)
--- kept on it in md.fl_arrows until it dies (Shots.lua). For the log (tests).
function F.heldArrows(shot)
    local t, n = shot.target, nil
    if t and t.getInventory then n = t:getInventory():getCountTypeRecurse(shot.arrow) end
    if t and t.getModData then
        for _, a in ipairs(t:getModData().fl_arrows or {}) do if a == shot.arrow then n = (n or 0) + 1 end end
    end
    if not n and shot.corpse then n = shot.corpse:getContainer():getCountTypeRecurse(shot.arrow) end
    return n
end

local nextSync = 0
function F.onServerTick()
    local now = getTimestampMs()
    pcall(F.payPendingXp, now)
    for id, d in pairs(F.recentDeaths) do if now - d.t > F.DEATH_KEEP_MS * 3 then F.recentDeaths[id] = nil end end
    for i = #F.serverShots, 1, -1 do
        local s = F.serverShots[i]
        if now - s.at >= F.SERVER_RESOLVE_MS then
            local okT, settled = pcall(F.settleTarget, s, now)
            if not okT or settled then
                table.remove(F.serverShots, i)
                F.lastFire = nil
                local ok, res = pcall(F.resolveShot, s.shot)
                log({ player = s.shot.shooter:getUsername(), arrow = s.shot.arrow,
                      target = s.targetInfo and s.targetInfo.kind, found = s.shot.target ~= nil or s.shot.corpse ~= nil,
                      passed = s.shot.passedPlayer, lit = s.shot.lit,
                      fire = F.lastFire and (F.lastFire.target and "target" or (F.lastFire.square and
                          (F.lastFire.square:getX() .. "," .. F.lastFire.square:getY()))) or nil,
                      xp = F.shotXp(s.shot), result = ok and res or ("error: " .. tostring(res)),
                      -- how many of this arrow the target / corpse holds now (tests)
                      held = F.heldArrows(s.shot) })
            end
        end
    end
    if now < nextSync then return end
    nextSync = now + F.SYNC_MS
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        local bow = p and p:getPrimaryHandItem()
        if F.isBow(bow) then
            pcall(function()
                F.prepareBowAmmo(p, bow)
                F.applyBowSkill(p, bow, bow:getModData().fl_nocked or F.bowArrow(bow))
            end)
        end
    end
end

-- Guarded on the server (unlike the client files): the server's own `reloadlua` removes this
-- file's handlers and drops any it adds while reloading, so only a guard keeps them (they look the
-- functions up by name, so the reloaded code still runs).
if not F.serverHooked then
    F.serverHooked = true
    Events.OnClientCommand.Add(function(...) F.onServerCommand(...) end)
    Events.OnTick.Add(function() F.onServerTick() end)
    Events.OnZombieDead.Add(function(z) F.onServerZombieDead(z) end)
end

return F
