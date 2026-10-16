--[[
    Fletcher: flying arrows in multiplayer, the client's side (server/Fletcher/Server.lua F.serverFlight
    is the other half).

    The shooter's client flies the arrow exactly as in single player (Flight.lua / Projectile.lua: spread,
    matched arrows, arcs, glass, walls, glances, hit zones, stealth, crits, the cripple roll). When it
    lands, F.finishProjectile hands it to F.netFinish here instead of resolving it: the report goes to the
    server ("flight"), which checks it against ITS record of the nocked arrow and what it can see, and
    makes it so (XP, breakage, wear, where the arrow ends up, stuck arrows, fire, noise).

    Damage: a multiplayer zombie belongs to one client (its health is that client's: set anywhere else
    it's overwritten). If the shooter's client owns the zombie, the hit goes in here, with the bow, as
    vanilla's would (it syncs); otherwise the server relays it ("hit") and the owner applies it.

    From the server (OnServerCommand, module "Fletcher"):
      flight  { shooter, x, y, z, h, vx, vy, vh, dur, ex, ey, eh, arrow, lit }  another player's shot: replayed
      hit     { id, damage, cripple }      a hit on a zombie this client owns: applied here
      stuck   { id, loc, arrow }           an arrow stuck in zombie id at attachment location loc: shown here
      unstuck { id }                       that zombie died (its corpse carries the arrows)
      hitPlayer { id, damage, zone, shooter, bow }   (PvP) this client's player was hit: the damage goes in
                                           here (a player's health is its own client's)
    Stuck arrows are attached on every client's copy of the zombie (attachments don't sync); the list is
    kept by zombie online id and put back on a zombie that comes into view later (F.netStuckScan).
]]

require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Projectile"
require "Fletcher/Stuck"
local F = Fletcher

F.netStuck = F.netStuck or {}            -- zombie online id -> { [loc] = arrow type }
F.netStuckFl = F.netStuckFl or {}        -- ... -> { [loc] = its fletching (nil = feathers) }
F.pendingPlayerStuck = F.pendingPlayerStuck or {}   -- arrows that hit this client's player, waiting for the item
F.HEALTH_PER_DAMAGE = 1 / 1.5            -- vanilla takes this much health off a zombie per point of damage
-- F.TEST_AIM = { tx, ty, noSpread }: tests only, where the next shots fly (client/Fletcher/Arrows.lua)

local function rand() return F.PROJ_RAND and F.PROJ_RAND() or ZombRandFloat(0, 1) end

local function where(o)
    return { id = o:getOnlineID(), x = o:getX(), y = o:getY(), z = o:getZ() }
end

--- The shot is over on the shooter's client: report it (multiplayer). Returns "sent".
function F.netFinish(p, out)
    local shooter = p.shooter
    local m = { arrow = p.arrow, fl = p.fl, flown = p.flown or 0, from = p.netFrom, lit = p.lit,
                out = { kind = out.kind, x = out.x, y = out.y, z = out.z, h = out.h or 0, material = out.material } }
    if out.kind == "zombie" then
        local t = out.target
        local dmg, zone, crit
        if instanceof(t, "IsoZombie") then
            p.stealth = F.isStealthShot(shooter, t)            -- (before the Hit: it turns the zombie)
            dmg, zone, crit = F.projectileDamage(p, t, out.h)
            local cripple = zone == "legs" and rand() * 100 < F.crippleChance(shooter, p.arrow, crit)
            m.target = where(t); m.target.kind = "zombie"
            m.cripple, m.stealth = cripple, p.stealth
            if not t:isRemoteZombie() then
                -- ours: the hit goes in here, with the bow, as vanilla's would (and syncs from here)
                if cripple then F.cripple(t, true) end
                if p.bow then pcall(function() t:Hit(p.bow, shooter, dmg, false, 1.0, false) end) end
                m.applied = true
            end
        else
            dmg, zone, crit = F.projectileDamage(p, t, out.h)
            m.target = where(t)
            m.target.kind = instanceof(t, "IsoAnimal") and "animal" or "player"
            if m.target.kind == "animal" and p.bow then
                pcall(function() t:Hit(p.bow, shooter, dmg, false, 1.0, false) end)
                m.applied = true
            end
        end
        m.damage, m.zone, m.crit = dmg, zone, crit
        p.damage, p.zone, p.crit = dmg, zone, crit
    elseif out.kind == "target" then
        local sq = out.targetItem and out.targetItem:getSquare()
        m.targetAt = sq and { x = sq:getX(), y = sq:getY(), z = sq:getZ() } or nil
        m.dropAt = F.restingPlace(p, out)
    elseif out.kind == "vehicle" then
        if rand() < F.hardBreakChance(p, F.PROJ.hardBreak) then
            m.broken = "Metal"
        else
            m.dropAt = F.restingPlace(p, { kind = "ground", x = out.x, y = out.y, z = out.z, h = 0 })
            if not m.dropAt then m.lost = "vehicle" end
        end
    elseif out.kind == "broke" then
        m.broken = out.material or "hard"
    else
        m.dropAt = F.restingPlace(p, out)
        if not m.dropAt then m.lost = out.kind end
    end
    if shooter and F.SEND_FLIGHTS ~= false then sendClientCommand(shooter, "Fletcher", "flight", m) end
    F.lastReport = m
    p.result = "sent"
    F.lastShot = "sent"
    return p.result
end

--- A zombie (by online id) on this client, or nil
function F.zombieById(id)
    local zl = getCell() and getCell():getZombieList()
    for i = 0, (zl and zl:size() or 0) - 1 do
        local z = zl:get(i)
        if z:getOnlineID() == id then return z end
    end
end

--- The server's relayed hit on a zombie this client owns: health off (it syncs from the owner), the
--- cripple, and the kill. True when applied here.
function F.netApplyHit(m)
    local z = F.zombieById(m.id)
    if not z or z:isRemoteZombie() or z:isDead() then return false end
    if m.cripple then F.cripple(z, true) end
    local hp = z:getHealth() - (tonumber(m.damage) or 0) * F.HEALTH_PER_DAMAGE
    if hp <= 0 then
        z:setHealth(0)
        local killer = getPlayer()
        pcall(function() z:Kill(killer) end)
    else
        z:setHealth(hp)
    end
    return true
end

--- (PvP) The server says this client's player was hit by another's arrow: the hit goes in here
function F.netHitPlayer(m)
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and p:isLocalPlayer() and p:getOnlineID() == m.id then
            local attacker = getPlayerByOnlineID(m.shooter)
            local weapon = instanceItem(m.bow or "Fletcher.SimpleBow")
            local ok = pcall(function() p:Hit(weapon, attacker, tonumber(m.damage) or 0, false, 1.0, false) end)
            -- the arrow is on its way into this player's inventory (the server put it there): shown
            -- stuck where it hit once it arrives (F.netStuckScan)
            if m.arrow then
                table.insert(F.pendingPlayerStuck, { player = p, arrow = m.arrow, fl = m.fl, h = tonumber(m.h) or 1.2,
                    dx = tonumber(m.dx) or 0, dy = tonumber(m.dy) or 0, untilMs = getTimestampMs() + 5000 })
            end
            return ok
        end
    end
    return false
end

--- Show the arrows the server says are stuck in a zombie (this client's copy); fls: loc -> fletching
function F.netShowStuck(z, list, fls)
    if not F.stuckRegistered then pcall(F.registerStuckPoints) end
    for loc, arrow in pairs(list) do
        if not z:getAttachedItem(loc) then
            local item = F.setFletch(instanceItem(arrow), fls and fls[loc])
            if item then z:setAttachedItem(loc, item) end
        end
    end
end

F.NET_STUCK_SCAN_MS = 500
local nextScan = 0
function F.netStuckScan()
    if not isClient() then return end
    local now = getTimestampMs()
    if now < nextScan then return end
    nextScan = now + F.NET_STUCK_SCAN_MS
    local zl = getCell() and getCell():getZombieList()
    for i = 0, (zl and zl:size() or 0) - 1 do
        local z = zl:get(i)
        local list = F.netStuck[z:getOnlineID()]
        if list and not z:isDead() then F.netShowStuck(z, list, F.netStuckFl[z:getOnlineID()]) end
    end
    -- an arrow that hit this player: stuck in them once the item is in the inventory
    for i = #F.pendingPlayerStuck, 1, -1 do
        local q = F.pendingPlayerStuck[i]
        local attached = {}
        local al = q.player:getAttachedItems()
        for j = 0, (al and al:size() or 0) - 1 do attached[al:get(j):getItem()] = true end
        local item
        local inv = q.player:getInventory():getItems()
        for j = 0, inv:size() - 1 do
            local it = inv:get(j)
            if it:getFullType() == q.arrow and F.fletchOf(it) == q.fl and not attached[it] then item = it end
        end
        if item then
            F.stickInPlayer(q.player, item, q.h, q.dx, q.dy)
            table.remove(F.pendingPlayerStuck, i)
        elseif now > q.untilMs then
            table.remove(F.pendingPlayerStuck, i)
        end
    end
end

function F.onNetFlightCommand(module, command, m)
    if module ~= "Fletcher" or type(m) ~= "table" then return end
    if command == "flight" then
        local me = getPlayer()
        if me and m.shooter == me:getOnlineID() then return end      -- (our own: we flew it)
        F.lastGhostMsg = m
        pcall(F.launchGhost, m)
    elseif command == "hit" then
        F.lastNetHit = { id = m.id, done = F.netApplyHit(m) }
    elseif command == "stuck" then
        F.netStuck[m.id] = F.netStuck[m.id] or {}
        F.netStuck[m.id][m.loc] = m.arrow
        F.netStuckFl[m.id] = F.netStuckFl[m.id] or {}
        F.netStuckFl[m.id][m.loc] = m.fl
        local z = F.zombieById(m.id)
        if z then F.netShowStuck(z, F.netStuck[m.id], F.netStuckFl[m.id]) end
    elseif command == "unstuck" then
        F.netStuck[m.id], F.netStuckFl[m.id] = nil, nil
    elseif command == "hitPlayer" then
        F.lastNetHitPlayer = { id = m.id, done = F.netHitPlayer(m) }
    end
end

Events.OnServerCommand.Add(function(...) F.onNetFlightCommand(...) end)     -- by name: reloads apply
Events.OnTick.Add(function() F.netStuckScan() end)

return F
