--[[
    Fletcher 0.7: bowfishing on the shooter's client (shared/Fletcher/Bowfishing.lua has the rest).

    While a local player aims a bow with a Bowfishing Arrow nocked and the aim is on fishable water,
    fish break the surface every few seconds (sooner where fish are plentiful): a splash on a water
    square in reach, picked in proportion to vanilla's fish count there (its fish points, where it
    draws its ripples), a little more likely near the aim (F.fishField). A rising fish stays
    catchable for F.FISHING.riseShowMs. When a bowfishing arrow comes
    down (Projectile.lua F.finishProjectile calls F.fishingLanded), it's a strike if its flight passed
    within F.FISHING.strikeRadius of a fish that was up (a flat shot flies on past its aim point): the
    arrow stops at the fish. In water either way, the shooter reels the line in once the bow comes
    down (F.pendingReel: an action queued mid-aim is dropped).
]]

require "Fletcher/Bowfishing"
local F = Fletcher

F.fishRises = F.fishRises or {}       -- player -> list of { x, y, t }
F.nextRise = F.nextRise or {}         -- player -> ms

--- Is this player aiming a bow with a bowfishing arrow on it at fishable water? The aim point if so.
function F.bowfishingAim(player)
    if not (player and player:isAiming()) then return nil end
    local bow = player:getPrimaryHandItem()
    if not (bow and F.isHandBow and F.isHandBow(bow) and bow:isRoundChambered()) then return nil end
    if not F.isFishingArrow(bow:getModData().fl_nocked or F.bowArrow(bow)) then return nil end
    local ok, ax, ay
    if F.viewpointView and F.viewpointView(player) then
        -- ViewPoint's 3D view: vanilla's aim is the iso point under the mouse; use the shot's own aim point
        local def = F.bowDef(bow)
        ok, ax, ay = pcall(F.viewpointAimPoint, player, def and def.range or F.FISHING.riseRange)
    else
        ok, ax, ay = pcall(Fishing.Utils.getAimCoords, player)
    end
    if not (ok and ax and F.isFishWater(ax, ay)) then return nil end
    return ax, ay
end

local function splash(x, y)
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), 0)
    if not sq then return end
    pcall(function() sq:startWaterSplash(true, ZombRandFloat(-0.2, 0.2), ZombRandFloat(-0.2, 0.2)) end)
    if isClient() then pcall(transmitBigWaterSplash, math.floor(x), math.floor(y), 0, 0) end
end

-- Where fish could rise: water tiles in reach, sampled (uniformly across the reach, and some more
-- round the aim), each weighted by vanilla's fish count there x the aim's pull, over the density it
-- was sampled at (so the extra samples round the aim are just coverage, not more pull). Returns the
-- list { x, y, w } and the best fish count found (for the pace: most open water holds none).
function F.fishField(player, ax, ay)
    local C = F.FISHING
    local bow = player:getPrimaryHandItem()
    local def = bow and F.bowDef(bow)
    local R = math.min(C.riseRange, def and def.range or C.riseRange)
    local px, py = player:getX(), player:getY()
    local areaR, areaA = math.pi * R * R, math.pi * C.aimNear * C.aimNear
    local out, best = {}, 0
    local function consider(x, y)
        if IsoUtils.DistanceTo(x, y, px, py) > R or not F.isFishWater(x, y) then return end
        local fish = F.fishAbundance(x, y)
        if fish > best then best = fish end
        if fish <= 0 then return end
        local da = IsoUtils.DistanceTo(x, y, ax, ay)
        local pull = 1 + C.aimPull * math.max(0, 1 - da / C.aimNear)
        local density = C.riseSamples / areaR + (da <= C.aimNear and C.riseAimSamples / areaA or 0)
        out[#out + 1] = { x = math.floor(x) + 0.5, y = math.floor(y) + 0.5, w = fish * pull / density }
    end
    for _ = 1, C.riseSamples do
        local a, r = ZombRandFloat(0, 2 * math.pi), R * math.sqrt(ZombRandFloat(0, 1))
        consider(px + math.cos(a) * r, py + math.sin(a) * r)
    end
    for _ = 1, C.riseAimSamples do
        local a, r = ZombRandFloat(0, 2 * math.pi), C.aimNear * math.sqrt(ZombRandFloat(0, 1))
        consider(ax + math.cos(a) * r, ay + math.sin(a) * r)
    end
    return out, best
end

--- A fish rises somewhere in reach where the fish are (if any). Returns the rise or nil.
function F.riseFish(player, ax, ay)
    local field = F.fishField(player, ax, ay)
    local total = 0
    for _, c in ipairs(field) do total = total + c.w end
    if total <= 0 then return nil end
    local pick, acc = ZombRandFloat(0, total), 0
    local c = field[#field]
    for _, f in ipairs(field) do
        acc = acc + f.w
        if acc >= pick then c = f; break end
    end
    local r = { x = c.x, y = c.y, t = getTimestampMs() }
    local list = F.fishRises[player] or {}
    list[#list + 1] = r
    F.fishRises[player] = list
    splash(r.x, r.y)
    return r
end

local function pace(n)
    -- a rich spot in reach (25+ fish): the base gap; fewer: up to three times longer
    local k = n >= 25 and 1 or (n >= 10 and 1.6 or 3)
    return math.floor(ZombRandFloat(F.FISHING.riseMinMs, F.FISHING.riseMaxMs) * k)
end

function F.updateFishRises(player)
    local now = getTimestampMs()
    local list = F.fishRises[player]
    if list then                                         -- forget old rises
        for i = #list, 1, -1 do
            if now - list[i].t > F.FISHING.riseShowMs + F.FISHING.riseLateMs + 2000 then table.remove(list, i) end
        end
    end
    local ax, ay = F.bowfishingAim(player)
    if not ax then F.nextRise[player] = nil; return end
    if not F.nextRise[player] then
        local _, best = F.fishField(player, ax, ay)
        F.nextRise[player] = now + pace(best)
    end
    if now >= F.nextRise[player] then
        F.riseFish(player, ax, ay)
        local _, best = F.fishField(player, ax, ay)
        F.nextRise[player] = now + pace(best)
    end
end

-- distance from (px, py) to the segment (ax, ay)-(bx, by)
local function segDist(px, py, ax, ay, bx, by)
    local sx, sy = bx - ax, by - ay
    local l2 = sx * sx + sy * sy
    local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * sx + (py - ay) * sy) / l2)) or 0
    return math.sqrt((px - ax - sx * t) ^ 2 + (py - ay - sy * t) ^ 2)
end

--- Was a fish up near (x, y) just now (or, given a start, anywhere along the flight from (x0, y0)
--- to (x, y): a flat shot flies on past what it was aimed at)?
function F.strikeAt(player, x, y, now, x0, y0)
    now = now or getTimestampMs()
    for _, r in ipairs(F.fishRises[player] or {}) do
        local age = now - r.t
        local d = x0 and segDist(r.x, r.y, x0, y0, x, y) or IsoUtils.DistanceTo(x, y, r.x, r.y)
        if age >= 0 and age <= F.FISHING.riseShowMs + F.FISHING.riseLateMs and d <= F.FISHING.strikeRadius then
            return r
        end
    end
    return nil
end

--- (Projectile.lua F.finishProjectile) A bowfishing arrow came down: in water, the shooter reels it in
function F.fishingLanded(p, out)
    if isServer() or not (p and out and F.isFishingArrow(p.arrow)) then return end
    local shooter = p.shooter
    if not (shooter and shooter.isLocalPlayer and shooter:isLocalPlayer()) then return end
    if out.kind == "zombie" or out.kind == "target" or (out.z and out.z ~= 0) then return end
    -- a fish it passed over takes it: the arrow stops there (so it's in the water, at the fish, for
    -- the shot's record here or on the server)
    local r = F.strikeAt(shooter, out.x, out.y, nil, p.x0, p.y0)
    if r then
        for i, v in ipairs(F.fishRises[shooter] or {}) do if v == r then table.remove(F.fishRises[shooter], i) break end end
        out.kind, out.x, out.y, out.h, out.material, out.skid = "ground", r.x, r.y, 0, nil, nil
    elseif not F.isFishWater(out.x, out.y) then
        F.lastLanding = { x = out.x, y = out.y, strike = false, dry = true }
        return
    end
    p.fishStrike = r ~= nil
    F.lastLanding = { x = out.x, y = out.y, strike = r ~= nil }
    -- the reel starts once the bow comes down: an action queued while the archer is still aiming is
    -- dropped (and in multiplayer never reaches the server)
    F.pendingReel[shooter] = { x = out.x, y = out.y, strike = r ~= nil, t = getTimestampMs() }
end

F.pendingReel = F.pendingReel or {}       -- player -> { x, y, strike, t }

--- Start a waiting reel when the archer isn't aiming (or drop it once its shot has expired)
function F.startPendingReel(player)
    local r = F.pendingReel[player]
    if not r then return false end
    if getTimestampMs() - r.t > F.FISHING.shotKeepMs - 1000 then F.pendingReel[player] = nil; return false end
    if player:isAiming() then return false end
    F.pendingReel[player] = nil
    ISTimedActionQueue.add(FletcherReelFishAction:new(player, r.x, r.y, r.strike))
    return true
end

function F.onBowfishingTick()
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and p:isLocalPlayer() then
            pcall(F.updateFishRises, p)
            pcall(F.startPendingReel, p)
        end
    end
end

Events.OnTick.Add(function() F.onBowfishingTick() end)     -- by name: reloads apply

-- (multiplayer) the server's word on a reel: said by the player
function F.onBowfishingCommand(module, command, args)
    if module ~= "Fletcher" or command ~= "fishSay" then return end
    local p = getPlayer()
    if p and args and args.text then
        if args.caught then p:playSound("PickUpFish") end
        p:Say(args.text)
    end
end

Events.OnServerCommand.Add(function(...) F.onBowfishingCommand(...) end)

return F
