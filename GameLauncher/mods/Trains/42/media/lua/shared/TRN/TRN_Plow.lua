--[[ Trains -- the plow, and the train as a solid thing (DESIGN.md 3.6).

    A train has no physics, so whatever it does to the world this file does,
    and what it hits is owned by different machines. Three shares, each run
    only where it sticks:

      * **the authority** (single player, or a server) kills the dead on the
        killing ground in front of the leading plow, with the engine's own
        Hit, which tells every client (PLAYED in the Heroes mod for heat
        vision);
      * **the machine that simulates a zombie** throws it aside and knocks it
        down when the train's outline reaches it, and shoves it out of a
        parked train. A zombie is moved by its own client and nobody else
        (pz_trekship MULTIPLAYER.md, "Zombies");
      * **a player's own client** throws its own character clear and hurts
        it. A client moves only its own character, and a player's body is
        its own client's (pz-heros POWERS.md 7, fact 4).

    The killing ground is the plow's own width, straight ahead of it: what
    is squarely in the way dies, and what is only beside the track, inside
    the margin, is thrown aside as the train passes. It is ahead of the
    outline, so in the one process where
    all three run in the same tick a zombie is killed before it is thrown
    (pz-heros DEV_GUIDE.md, "Two halves of one effect in one tick have an
    order").

    To the dead the train is C.Plow.margin wider than it looks: a zombie
    beside the track is out of arm's reach of a rider on a deck. **While the
    train moves, nothing on it can be reached** (the author's rule).

    Not built yet, and said so: vehicles in the way are passed through, and
    so are trees, fences and anything a player built on the track.

    Not played. UNMEASURED: whether a zombie knocked down by the client
    that simulates it goes down on every machine.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"

TRN = TRN or {}
local C, U, Net, T, K = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock

local P = {}
TRN.Plow = P

P.stats = { killed = 0, thrown = 0, shoved = 0, players = 0 }
P.hitAt = {}            -- username -> when this machine's player was last hit

---------------------------------------------------------------------------
-- The pieces of a train, as boxes
---------------------------------------------------------------------------
--- Every car and deck of a train as a box in the world, `margin` wider and
--- longer than it is: { x, y, ux, uy, halfLen, halfWid }.
function P.boxes(route, train, w, margin)
    local layout = T.layout(train.consist)
    local out = {}
    for _, car in ipairs(layout.cars) do
        local x, y, ux, uy = T.carAt(route, w.c, car)
        out[#out + 1] = { x = x, y = y, ux = ux, uy = uy,
                          halfLen = car.len / 2 + margin, halfWid = C.HalfWidth + margin }
    end
    for _, deck in ipairs(layout.decks) do
        local x, y, ux, uy = T.pose(route, w.c + deck.rel, C.Gap / 2)
        out[#out + 1] = { x = x, y = y, ux = ux, uy = uy,
                          halfLen = C.Gap / 2 + margin, halfWid = C.HalfWidth + margin }
    end
    return out
end

--- The box a point is in, with how far across it is; or nil.
function P.within(boxes, x, y)
    for _, box in ipairs(boxes) do
        local inside, _, across = T.inside(box.x, box.y, box.ux, box.uy, box.halfLen, box.halfWid, x, y)
        if inside then return box, across end
    end
    return nil
end

--- Which way is out for something `across` a box: the unit vector to the
--- nearer side, and how far it is to that side.
function P.outward(box, across)
    local side = (across >= 0) and 1 or -1
    return -box.uy * side, box.ux * side, box.halfWid - math.abs(across)
end

---------------------------------------------------------------------------
-- The dead
---------------------------------------------------------------------------
local function zombies()
    local cell = U.cell()
    local list = cell and U.try("plow.list", function() return cell:getZombieList() end)
    if not list then return nil, 0 end
    return list, U.try("plow.count", function() return list:size() end) or 0
end

local weapon = nil
local function plowWeapon()
    if not weapon then
        weapon = U.try("plow.weapon", function() return instanceItem(C.Plow.weapon) end)
    end
    return weapon
end

--- The player nearest a point: who the engine is told did it.
local function nearest(x, y)
    local best, bestD = nil, nil
    for _, p in ipairs(U.players()) do
        local d = U.try("plow.near", function()
            local dx, dy = p:getX() - x, p:getY() - y
            return dx * dx + dy * dy
        end)
        if d and (not bestD or d < bestD) then best, bestD = p, d end
    end
    return best, bestD
end

--- The authority's share: the dead on the killing ground die.
function P.kill(route, train, w)
    local px, py, ux, uy, half = T.plowAt(route, train, w)
    if not px then return 0 end
    local list, n = zombies()
    if not list or n == 0 then return 0 end
    local by = nearest(px, py)
    local with = plowWeapon()
    if not by or not with then return 0 end
    local killed = 0
    local each = U.batch("plow.kill")
    for i = n - 1, 0, -1 do
        local zed = U.try("plow.at", function() return list:get(i) end)
        if zed and each(function()
            if zed:isDead() or math.floor(zed:getZ()) ~= route.z then return false end
            if not T.inside(px, py, ux, uy, half, C.Plow.wide, zed:getX(), zed:getY()) then
                return false
            end
            zed:Hit(with, by, C.Plow.damage, false, 1.0)
            if not zed:isDead() then zed:Kill(with, by) end
            return true
        end) then killed = killed + 1 end
    end
    return killed
end

--- The simulating machine's share: the dead inside the train's outline are
--- thrown aside and knocked down, or shoved out of a parked one.
function P.clear(route, train, w)
    local list, n = zombies()
    if not list or n == 0 then return 0, 0 end
    local moving = w.moving and w.speed >= C.Plow.moving
    local boxes = P.boxes(route, train, w, C.Plow.margin)
    local thrown, shoved = 0, 0
    local each = U.batch("plow.clear")
    for i = n - 1, 0, -1 do
        local zed = U.try("plow.at", function() return list:get(i) end)
        local did = zed and each(function()
            if zed:isDead() or math.floor(zed:getZ()) ~= route.z then return nil end
            if not U.simulated(zed) then return nil end
            local zx, zy = zed:getX(), zed:getY()
            local box, across = P.within(boxes, zx, zy)
            if not box then return nil end
            local ox, oy, toEdge = P.outward(box, across)
            local push = toEdge + (moving and C.Plow.throw or C.Plow.shove)
            local nx, ny = U.thrownTo(zx, zy, route.z, ox, oy, push)
            zed:setX(nx) zed:setY(ny)
            zed:setLastX(nx) zed:setLastY(ny)
            if moving then
                zed:setTarget(nil)
                zed:knockDown(false)
                return "thrown"
            end
            return "shoved"
        end)
        if did == "thrown" then thrown = thrown + 1 elseif did == "shoved" then shoved = shoved + 1 end
    end
    return thrown, shoved
end

---------------------------------------------------------------------------
-- The living
---------------------------------------------------------------------------
--- A player's own client's share: this machine's player, in the way of a
--- moving train, is thrown clear, knocked down and hurt.
function P.strike(route, train, w, player)
    if not w.moving or w.speed < C.Plow.moving then return false end
    -- A host may have the trains pass through the living (sandbox PlowPlayers).
    if not TRN.Setup.on("PlowPlayers") then return false end
    if TRN.Deck and TRN.Deck.aboard(player) then return false end
    local who = U.username(player) or "?"
    local now = U.nowMs()
    if P.hitAt[who] and now - P.hitAt[who] < C.Plow.againMs then return false end
    local hit = U.try("plow.player", function()
        if player:isDead() or math.floor(player:getZ()) ~= route.z then return false end
        if player:getVehicle() ~= nil then return false end
        local x, y = player:getX(), player:getY()
        local box, across = P.within(P.boxes(route, train, w, 0), x, y)
        if not box then
            -- Or on the killing ground in front of the plow.
            local px, py, ux, uy, half = T.plowAt(route, train, w)
            local inside, _, b = T.inside(px, py, ux, uy, half, C.Plow.wide, x, y)
            if not inside then return false end
            box, across = { ux = ux, uy = uy, halfWid = C.Plow.wide }, b
        end
        local ox, oy, toEdge = P.outward(box, across)
        local nx, ny = U.thrownTo(x, y, route.z, ox, oy, toEdge + C.Plow.throwPlayer)
        player:setX(nx) player:setY(ny)
        player:setLastX(nx) player:setLastY(ny)
        -- Down, as vanilla's own shove puts somebody down.
        player:setBumpType("stagger")
        player:setVariable("BumpDone", false)
        player:setVariable("BumpFall", true)
        player:setVariable("BumpFallType", "pushedFront")
        player:getBodyDamage():ReduceGeneralHealth(C.Plow.hurtPlayer)
        return true
    end)
    if hit ~= true then return false end
    P.hitAt[who] = now
    U.note(player, getText("IGUI_TRN_Struck"), 255, 120, 90)
    return true
end

---------------------------------------------------------------------------
-- Every tick
---------------------------------------------------------------------------
--- True when some player this process knows is within reach of the train.
local function watched(route, w)
    local x, y = T.at(route, w.c)
    local _, d = nearest(x, y)
    return d ~= nil and d <= C.Plow.range * C.Plow.range
end

function P.tick()
    local routes = K.routes()
    if #routes == 0 then return end
    for _, route in ipairs(routes) do
        for _, train in ipairs(route.trains) do
            local w = K.where(route, train)
            if w and watched(route, w) then
                local killed, thrown, shoved, struck = 0, 0, 0, 0
                -- The authority first: what it kills is measured where it
                -- stood, before anything is thrown.
                if Net.isAuthority() then killed = P.kill(route, train, w) end
                if not isServer() then
                    thrown, shoved = P.clear(route, train, w)
                    for i = 0, 3 do
                        local p = U.try("plow.local", function() return getSpecificPlayer(i) end)
                        if p and P.strike(route, train, w, p) then struck = struck + 1 end
                    end
                end
                P.stats.killed = P.stats.killed + killed
                P.stats.thrown = P.stats.thrown + thrown
                P.stats.shoved = P.stats.shoved + shoved
                P.stats.players = P.stats.players + struck
                if killed + thrown + struck > 0 then
                    U.log("plow: %s killed %d on the authority, threw %d simulated here, struck %d player(s) here",
                          train.id, killed, thrown, struck)
                end
            end
        end
    end
end

Events.OnTick.Add(function() U.try("plow.tick", P.tick) end)

function P.status()
    U.log("status: plow has killed %d, thrown %d, shoved %d and struck %d player(s) on this machine",
          P.stats.killed, P.stats.thrown, P.stats.shoved, P.stats.players)
end

return P
