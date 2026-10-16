if isServer() then return end

--[[ Trains -- this machine's player, inside a car (DESIGN.md 3.4, 5.2).

    The inside of a car is a room in a cell off the edge of the map, and
    going in is a move to it. The train goes round its line as a number; the
    room sits still. This file is the client's half of that, and it is the
    Shuttlecraft's arrival (pz_trekship TREK_Core.lua, PLAYED there):

      * **the player is moved first, and held.** The room cannot be built
        until its ground has streamed in, and ground streams in only round a
        player. So she is put where the door will be and pinned there, with
        every piece of the engine's fall state cleared each frame (a player
        re-placed without that fell and died in the Shuttlecraft), until the
        server says the room is built **and** this machine can see a floor
        under her. Then she is held a few ticks more, while the engine
        settles the new floor, and let go;
      * **if the room never comes**, she is not left in the dark: the client
        asks to be put back on the deck she came from;
      * **the room's light** is this machine's own lamp post, hung while she
        is inside and taken down when she leaves;
      * **walls do not hold a player where the engine sees no building**:
        build 42 lets a player climb one, and a room raised at runtime is in
        no building. So the engine's own switch for that, ignoreAutoVault,
        is set while she is inside **and cleared when she leaves**
        (pz_trekship DEV_GUIDE.md, "A wall keeps a player in only where the
        engine thinks there is a building").

    Inside, nothing of the world is drawn and nothing needs to be. The
    speaker says where the train is (TRN_Deck.speak).

    Not played.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Rooms"

TRN = TRN or {}
local C, U, Net, T, K, R = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock, TRN.Rooms

local I = {}
TRN.Inside = I

-- username -> { train, car, room, arriving = { x, y, tries, ready, settled },
--   light, said }
I.inside = {}
I.stats = { arrivals = 0, bailed = 0, held = 0 }

local function nameOf(player) return U.username(player) or "?" end

function I.record(player)
    return player and I.inside[nameOf(player)] or nil
end

function I.aboard(player)
    return I.record(player) ~= nil
end

---------------------------------------------------------------------------
-- Holding her while the room is raised
---------------------------------------------------------------------------
--- Pins a character to a spot with nothing under them, or nothing yet.
local function pin(player, x, y, z)
    U.try("inside.pin", function()
        player:setX(x) player:setY(y) player:setZ(z)
        player:setLastX(x) player:setLastY(y) player:setLastZ(z)
        player:setbFalling(false)
        player:setFallTime(0)
        player:setLastFallSpeed(0)
        player:clearFallDamage()
    end)
end

local function floorAt(x, y, z)
    local sq = U.square(x, y, z)
    if not sq then return false end
    return U.try("inside.floor", function() return sq:getFloor() ~= nil end) == true
end

local function vault(player, held)
    U.try("inside.vault", function() player:setIgnoreAutoVault(held) end)
end

local function unlight(rec)
    if not rec.light then return end
    local lights = rec.light
    rec.light = nil
    for _, light in ipairs(lights) do
        U.try("inside.unlight", function() getCell():removeLamppost(light) end)
    end
end

--- Where a car's lamps hang: the middle of its room, or, for a car of
--- several rooms, where its style says (a wall keeps a lamp's light out of
--- the next room: pz_trekship ADIRONDACK.md, "lit room by room").
local function lampSpots(rec)
    local _, train = T.find(K.routes(), rec.train)
    local car = train and T.layout(train.consist).cars[rec.car]
    local kind = car and C.Cars[car.kind]
    local style = kind and C.Rooms.styles[kind.inside or ""]
    local spots = {}
    for _, p in ipairs(style and style.lamps or {}) do
        spots[#spots + 1] = { x = rec.room.x0 + p.dx, y = rec.room.y0 + p.dy }
    end
    if #spots == 0 then
        local x, y = R.spot(rec.room, nil)
        spots[1] = { x = math.floor(x), y = math.floor(y) }
    end
    return spots
end

local function light(rec)
    if rec.light then return end
    local L = C.Rooms.light
    rec.light = {}
    for _, p in ipairs(lampSpots(rec)) do
        rec.light[#rec.light + 1] = U.try("inside.light", function()
            return getCell():addLamppost(p.x, p.y, rec.room.z, L.r, L.g, L.b, L.radius)
        end)
    end
end

---------------------------------------------------------------------------
-- In and out
---------------------------------------------------------------------------
--- The server has this player inside a car: through `door`, or (a
--- character who saved inside) wherever in the room they already are.
function I.enter(player, trainId, car, door)
    local index = R.indexOf(K.routes(), trainId)
    if not index then return false end
    local who = nameOf(player)
    local old = I.inside[who]
    if old then unlight(old) end
    -- A car's room is its slot's, which is its place in the train for every car but the empties
    -- coupled on behind and the locomotive after them (TRN_Time.roll).
    local _, train = T.find(K.routes(), trainId)
    local slot = train and T.slotOf(train.consist, car)
    if not slot then return false end
    local room = R.room(index, slot)
    local x, y = R.spot(room, door)
    if not door then
        local px = U.try("inside.x", function() return player:getX() end)
        local py = U.try("inside.y", function() return player:getY() end)
        if px and py and R.within(room, px, py) then x, y = px, py end
    end
    I.inside[who] = { train = trainId, car = car, room = room, said = "",
                      arriving = { x = x, y = y, tries = 0 } }
    pin(player, x, y, room.z)
    vault(player, true)
    I.stats.arrivals = I.stats.arrivals + 1
    U.log("inside: %s is going into %s car %d at %.1f,%.1f", who, tostring(trainId), car, x, y)
    return true
end

--- She is no longer inside: the lamp comes down and climbing is her own
--- again. Whoever moves her next (the deck, the ground) does the moving.
function I.leave(player)
    local who = nameOf(player)
    local rec = I.inside[who]
    if not rec then return false end
    I.inside[who] = nil
    unlight(rec)
    vault(player, false)
    return true
end

--- The server says the room is built.
function I.ready(player)
    local rec = I.record(player)
    if rec and rec.arriving then rec.arriving.ready = true end
end

--- A character has appeared: nothing of a stay inside survives a load on
--- this side. Called by TRN_Client before it says hello.
function I.reset(player)
    local rec = I.inside[nameOf(player)]
    if rec then
        -- The lamp went with the old cell; its handle means nothing now.
        rec.light = nil
        I.inside[nameOf(player)] = nil
    end
    vault(player, false)
    -- 0.6.2 held the weather's fog at nothing for whoever was inside a car
    -- (a wrong guess at a black slab over the room: DEV_GUIDE.md, "A room
    -- of ours is a room to the engine, and has none"). A save made inside
    -- one may still hold it: let go.
    U.try("inside.fog", function() getClimateManager():getClimateFloat(5):setEnableOverride(false) end)
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------
local function arrive(player, rec)
    local a = rec.arriving
    a.tries = a.tries + 1
    pin(player, a.x, a.y, rec.room.z)
    I.stats.held = I.stats.held + 1
    if a.tries == 1 or a.tries == 300 then
        U.log("inside: arrival tick %d: the server says %s, a floor under her %s", a.tries,
              a.ready and "built" or "not yet", tostring(floorAt(a.x, a.y, rec.room.z)))
    end
    -- The server may have answered before it had the ground, and a request
    -- made then is simply waiting: ask again now and then.
    if a.tries == 1 or U.mod(a.tries, C.Rooms.askEvery) == 0 then
        Net.send(player, "room", {})
    end
    if a.ready and floorAt(a.x, a.y, rec.room.z) then
        a.settled = (a.settled or 0) + 1
        if a.settled < C.Rooms.settle then return end
        rec.arriving = nil
        light(rec)
        U.log("inside: %s is in the car after %d tick(s)", nameOf(player), a.tries)
        return
    end
    if a.tries > C.Rooms.timeout then
        I.stats.bailed = I.stats.bailed + 1
        rec.arriving.tries = 0
        U.log("WARN the inside of %s car %d never arrived; asking to be put back outside",
              tostring(rec.train), rec.car)
        Net.send(player, "bail", {})
    end
end

function I.step(player, rec)
    if rec.arriving then return arrive(player, rec) end
    -- Anywhere in the rooms' ground that is not her room, or with no floor
    -- under her: the same as an arrival, from the middle of her room.
    local x = U.try("inside.x", function() return player:getX() end) or 0
    local y = U.try("inside.y", function() return player:getY() end) or 0
    if not R.within(rec.room, x, y) or not floorAt(x, y, rec.room.z) then
        rec.lost = (rec.lost or 0) + 1
        if rec.lost >= C.Rooms.lostAfter then
            rec.lost = 0
            local mx, my = R.spot(rec.room, nil)
            rec.arriving = { x = mx, y = my, tries = 0 }
            U.log("inside: %s was not in her room at %.1f,%.1f; bringing her back", nameOf(player), x, y)
        end
        return
    end
    rec.lost = 0
    light(rec)
    -- The speaker (DESIGN.md 5.4).
    local route, train = T.find(K.routes(), rec.train)
    local w = route and K.where(route, train)
    if w and TRN.Deck then TRN.Deck.speak(player, rec, route, w) end
end

Events.OnPlayerUpdate.Add(function(player)
    if not player then return end
    local rec = I.inside[nameOf(player)]
    if not rec then return end
    if not U.try("inside.isLocal", function() return player:isLocalPlayer() end) then return end
    U.try("inside.step", I.step, player, rec)
end)

--- Somebody arriving, pinned again at the end of the tick, where the
--- engine's own update cannot put her back (TRN_Deck.pin has the bytecode).
function I.pin()
    for i = 0, 3 do
        local player = U.try("inside.pinWho", function() return getSpecificPlayer(i) end)
        local rec = player and I.inside[nameOf(player)]
        if rec and rec.arriving then pin(player, rec.arriving.x, rec.arriving.y, rec.room.z) end
    end
end

Events.OnTick.Add(function() U.try("inside.pinTick", I.pin) end)

Events.OnPlayerDeath.Add(function(player)
    if not player or not I.inside[nameOf(player)] then return end
    I.leave(player)
    Net.send(player, "gone", {})
end)

function I.status()
    local n = 0
    for who, rec in pairs(I.inside) do
        n = n + 1
        U.log("status: %s is inside %s car %d%s", who, tostring(rec.train), rec.car,
              rec.arriving and (", arriving for " .. rec.arriving.tries .. " tick(s)") or "")
    end
    U.log("status: %d inside here; %d arrival(s), %d frame(s) held, %d bailed", n, I.stats.arrivals,
          I.stats.held, I.stats.bailed)
end

return I
