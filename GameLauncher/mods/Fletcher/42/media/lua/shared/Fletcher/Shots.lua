--[[
    Fletcher: what happens to a shot arrow (placeholder until the projectile system, phase 2).
    Shared: singleplayer resolves on the client, multiplayer on the server (server/Fletcher/Server.lua).
      hit   -> into the target: a living zombie keeps it (md.fl_arrows) until it dies, then it goes
               into the corpse (F.onZombieDead: the game replaces a zombie's inventory at death);
               a dead one / a player: straight into its inventory
      miss  -> it lands on the ground along the shot line, FLIGHT tiles out (or short of a wall)
    It breaks instead with a chance set by Archery and the arrow type. Each shot pays Archery XP
    (more for a hit, more again for a kill).
    A shot: { shooter, arrow, x, y, z, dx, dy, target?, corpse?, hit?, killed?, dropAt? }
      target  a living character hit (the arrow goes into its inventory)
      corpse  an IsoDeadBody: the target died before the shot was resolved (multiplayer: the kill
              reaches the server first), the arrow goes into it
      hit / killed  what happened when there's no target object to ask
      dropAt  { x, y, z }: a hit whose target is gone: the arrow drops where it was; with
              { h, yaw, kind } (true projectiles): exactly there, at height h (floors), turned to yaw
      hitH    the height (metres) it struck a target at (which body point it sticks in)
      broken  it shattered on impact (true projectiles: the material, e.g. "Brick"): nothing left
      lit     a fire arrow that was lit on release (F.lightFire): sets alight what it hits / the spot, burns away
      lost    it came to rest out of reach (a roof with nothing to lie on)
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Gear"
local F = Fletcher

-- breakage: F.breakChance (Archery level x arrow type), or F.BREAK_CHANCE_OVERRIDE in tests
F.FLIGHT = 8                 -- tiles, for a miss

function F.landingSquare(shot)
    local sq = nil
    for d = 1, F.FLIGHT do
        local s = getCell():getGridSquare(math.floor(shot.x + shot.dx * d), math.floor(shot.y + shot.dy * d), shot.z)
        if not s then break end
        if sq and (s:isBlockedTo(sq) or sq:isBlockedTo(s)) then break end    -- stops short of a wall
        sq = s
    end
    return sq
end

--- Percent of a shooter's arrows (of a type; nil = no type modifier) that break: Archery level x
--- the arrow's breakage x its fletching's (fl), or a fixed test override.
function F.breakChance(shooter, arrowType, fl)
    if F.BREAK_CHANCE_OVERRIDE then return F.BREAK_CHANCE_OVERRIDE end
    local def = F.ARROW_DEFS[arrowType or ""]
    local fb = F.fletchDef and F.fletchDef(fl).breakage or 1
    return math.max(F.BREAK_FLOOR or 0, F.stat("breakChance", F.level(shooter)) * (def and def.breakage or 1) * fb)
end

function F.shotXp(shot)
    local xp = 0                       -- a miss teaches nothing (shooting a wall all day did)
    local t = shot.target
    if t or shot.hit or shot.corpse then
        xp = F.XP.shot + F.XP.hit
        local dead = shot.killed or shot.corpse ~= nil or (t and t.isDead and (t:isDead() or t:getHealth() <= 0))
        if dead then xp = xp + F.XP.kill end
    end
    return xp
end

local function addTo(container, arrow, fl)
    local item = container:AddItem(arrow)
    if item and fl then F.setFletch(item, fl) end         -- (before it's sent: the client gets it with it)
    if isServer() and item then sendAddItemToContainer(container, item) end
    return item
end

--- A noisemaker landed at (x, y, z): pulses of noise there (zombies go to the noise, not the shooter),
--- with vanilla's noise maker sound. def.noise = { radius, volume, pulses, every (s) }.
F.NOISE_SOUND = "NoiseMakerActivate"
F.noises = F.noises or {}
function F.arrowNoise(arrowType, x, y, z)
    local def = F.ARROW_DEFS[arrowType or ""]
    local n = def and def.noise
    if not (n and x and y) then return false end
    z = math.floor(z or 0)
    local now = getTimestampMs()
    table.insert(F.noises, { x = x, y = y, z = z, n = n, left = n.pulses, next = now })
    if not isServer() then
        pcall(function()
            local e = getWorld():getFreeEmitter(x, y, z)
            if e then e:playSound(F.NOISE_SOUND) end
        end)
    end
    F.lastNoise = { x = x, y = y, z = z, radius = n.radius }
    F.onNoiseTick()
    return true
end

function F.onNoiseTick()
    if #F.noises == 0 then return end
    local now = getTimestampMs()
    for i = #F.noises, 1, -1 do
        local s = F.noises[i]
        if now >= s.next then
            addSound(nil, math.floor(s.x), math.floor(s.y), s.z, s.n.radius, s.n.volume)
            s.left = s.left - 1
            s.next = now + s.n.every * 1000
            if s.left <= 0 then table.remove(F.noises, i) end
        end
    end
end
Events.OnTick.Add(function() F.onNoiseTick() end)     -- by name: reloads apply

--- Where a shot's arrow ends up, for its noise: where it rests or what it hit (true projectiles set
--- shot.noiseAt; the vanilla-hit path: the target, else where a miss lands)
local function noisePoint(shot)
    if shot.noiseAt then return shot.noiseAt.x, shot.noiseAt.y, shot.noiseAt.z end
    if shot.dropAt then return shot.dropAt.x, shot.dropAt.y, shot.dropAt.z end
    local t = shot.target or shot.corpse
    if t and t.getX then return t:getX(), t:getY(), t:getZ() end
    local sq = F.landingSquare and F.landingSquare(shot)
    if sq then return sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ() end
    return shot.x, shot.y, shot.z
end

--- A fire starter the character carries with a use left (a lighter, matches, or anything tagged
--- base:startfire), or nil
function F.fireSource(character)
    local inv = character and character:getInventory()
    if not inv then return nil end
    local function usable(it) return it and (not it.getCurrentUses or it:getCurrentUses() > 0) end
    local it = ItemTag and ItemTag.START_FIRE and inv:getFirstTagRecurse(ItemTag.START_FIRE)
    if usable(it) then return it end
    for _, t in ipairs({ "Lighter", "Matches" }) do
        it = inv:getFirstTypeRecurse(t)
        if usable(it) then return it end
    end
    return nil
end

--- Light a fire arrow as it is loosed: uses up one use of the fire starter. True if lit. On a
--- server the use is synced to the shooter's client (UseAndSync, as vanilla's server code does).
function F.lightFire(character)
    local src = F.fireSource(character)
    if not src then return false end
    if isServer() and src.UseAndSync then src:UseAndSync() else src:Use() end
    return true
end

--- A lit fire arrow arrived: what it hit catches fire, else a fire starts where it rests
function F.arrowFire(shot, x, y, z)
    local def = F.ARROW_DEFS[shot.arrow or ""]
    local t = shot.target
    if t and t.SetOnFire and not (t.isDead and t:isDead()) then
        pcall(function() t:SetOnFire() end)
        -- multiplayer: a zombie's state belongs to the client that owns it (a player's to its own
        -- client); a fire set here is overwritten. Every client gets "ignite" and the owner sets it
        -- (client/Fletcher/Arrows.lua F.onServerCommand); it syncs to everyone from there.
        if isServer() and t.getOnlineID then
            local kind = instanceof(t, "IsoZombie") and "zombie" or (F.isPerson(t) and "player" or (instanceof(t, "IsoAnimal") and "animal" or nil))
            if kind then sendServerCommand("Fletcher", "ignite", { id = t:getOnlineID(), kind = kind }) end
        end
        F.lastFire = { target = t }
        return true
    end
    local sq = x and getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not sq then return false end
    pcall(function() IsoFireManager.StartFire(getCell(), sq, true, def.fire.energy) end)
    F.lastFire = { square = sq }
    return true
end

function F.resolveShot(shot)
    if F.fishingResolve and F.fishingResolve(shot) then return "on its line" end   -- (bowfishing: Bowfishing.lua)
    local def = F.ARROW_DEFS[shot.arrow or ""]
    if def and def.noise then pcall(function() F.arrowNoise(shot.arrow, noisePoint(shot)) end) end
    if def and def.fire and shot.lit then
        pcall(function() F.arrowFire(shot, noisePoint(shot)) end)
        shot.burned = true
    end
    return F.resolveShotArrow(shot)
end

-- Practice on an archery target: XP for a hit only while Archery is under this level (like vanilla's
-- practice caps); the arrow neither breaks nor wears in the straw
F.TARGET_MAX_LEVEL = 3

function F.resolveShotArrow(shot)
    if shot.practice then
        local lvl = shot.shooter and F.level(shot.shooter) or 0
        if shot.shooter and not shot.noXp and lvl < F.TARGET_MAX_LEVEL then F.awardXp(shot.shooter, F.XP.shot + F.XP.hit) end
        F.lastPracticeXp = lvl < F.TARGET_MAX_LEVEL
        local d = shot.dropAt
        local sq = d and getCell():getGridSquare(math.floor(d.x), math.floor(d.y), math.floor(d.z or 0))
        if sq then
            local it = F.setFletch(instanceItem(shot.arrow or F.DEFAULT_ARROW), shot.fl)
            if it and d.yaw then it:setWorldZRotation(d.yaw) end
            if it then sq:AddWorldInventoryItem(it, d.x - sq:getX(), d.y - sq:getY(), d.h or 0) end
        end
        return "in archery target"
    end
    if shot.shooter and not shot.noXp then F.awardXp(shot.shooter, F.shotXp(shot)) end   -- (noXp: a trap's shot)
    local arrow = shot.arrow or F.DEFAULT_ARROW     -- (shots always carry their arrow / bolt type)
    local fl = shot.fl                              -- (and their fletching, nil = feathers: Fletching.lua)
    if shot.broken then return type(shot.broken) == "string" and ("broke on " .. shot.broken:lower()) or "broke" end
    if shot.burned then return "burned" end            -- a lit fire arrow burns away
    if shot.lost then return "lost on " .. tostring(shot.lost) end
    if ZombRand(100) < F.breakChance(shot.shooter, arrow, fl) then return "broke" end
    -- wear: a surviving arrow may come back damaged (re-fletch it: Fletcher_Damaged.txt); a damaged
    -- arrow has lost its fletching
    local worn = F.damagedOf(arrow)
    if worn and ZombRandFloat(0, 100) < F.wearChance(shot.shooter, arrow, fl) then
        arrow = worn
        fl = nil
        shot.worn = true
    end
    local t = shot.target
    -- stuck in the zombie where it hit, visibly (shared/Fletcher/Stuck.lua): the arrow item itself,
    -- looted from the corpse later; no free point (or multiplayer) -> the record below
    if t and instanceof(t, "IsoZombie") and F.stickInZombie
            and F.stickInZombie(t, arrow, shot.hitH, shot.dx or 0, shot.dy or 0, shot.shooter, fl) then
        return (t:isDead() or t:getHealth() <= 0) and "in target" or "stuck in target"
    end
    if t and instanceof(t, "IsoZombie") and not t:isDead() and t:getHealth() > 0 then
        -- stuck in a living zombie: kept on the zombie, not in its inventory (the game replaces a
        -- zombie's inventory when it dies, which lost every non-lethal hit); F.onZombieDead puts
        -- them in the corpse
        local md = t:getModData()
        md.fl_arrows = md.fl_arrows or {}
        table.insert(md.fl_arrows, arrow)
        md.fl_arrowsFletch = md.fl_arrowsFletch or {}        -- (same index: each one's fletching, "" = feathers)
        md.fl_arrowsFletch[#md.fl_arrows] = fl or ""
        return "stuck in target"
    end
    if t and t.getInventory then
        local item = addTo(t:getInventory(), arrow, fl)
        -- a player shows it stuck where it hit (single player here; multiplayer: the player's own
        -- client, told by "hitPlayer", once the item has arrived: client/Fletcher/NetFlight.lua)
        if item and F.isPerson(t) and not isServer() and F.stickInPlayer then
            F.stickInPlayer(t, item, shot.hitH, shot.dx or 0, shot.dy or 0)
        end
        return "in target"
    end
    if shot.corpse then
        addTo(shot.corpse:getContainer(), arrow, fl)
        return "in corpse"
    end
    if shot.dropAt then
        local d = shot.dropAt
        local sq = getCell():getGridSquare(math.floor(d.x), math.floor(d.y), math.floor(d.z or 0))
        if sq and d.yaw then
            -- where it stopped (true projectiles): in a wall or tree at the height it hit, or on the
            -- ground where it landed, lying along its flight (offsets are in floors; pivot = the nock)
            -- turned BEFORE it goes down: a server sends the item as it is when added
            local item = F.setFletch(instanceItem(arrow), fl)
            if item then
                item:setWorldZRotation(d.yaw)
                sq:AddWorldInventoryItem(item, d.x - sq:getX(), d.y - sq:getY(), d.h or 0)
            end
            return d.kind and ("in " .. d.kind) or "at target"
        elseif sq then
            sq:AddWorldInventoryItem(F.setFletch(instanceItem(arrow), fl), ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
            return "at target"
        end
    end
    local sq = F.landingSquare(shot)
    if sq then
        sq:AddWorldInventoryItem(F.setFletch(instanceItem(arrow), fl), ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
        return "on ground"
    end
    return "lost"
end

--- A zombie dies: the arrows stuck in it go into its inventory, which becomes the corpse's (added
--- here they stay; added while it lived they were wiped). Server / singleplayer only.
function F.onZombieDead(zombie)
    if isClient() or not zombie then return end
    local md = zombie:getModData()
    local stuck, fls = md.fl_arrows, md.fl_arrowsFletch or {}
    if not stuck or #stuck == 0 then return end
    md.fl_arrows, md.fl_arrowsFletch = nil, nil
    for i, arrow in ipairs(stuck) do
        local fl = fls[i]
        addTo(zombie:getInventory(), arrow, (fl ~= nil and fl ~= "") and fl or nil)
    end
end

Events.OnZombieDead.Add(function(z) F.onZombieDead(z) end)     -- by name: reloads apply

return F
