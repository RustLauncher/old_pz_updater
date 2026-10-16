if isClient() then return end

--[[ Trains -- the authority (DESIGN.md 3.1, 5.1).

    Runs in single player and on any server; never on a client of one. It
    owns three things and nothing else:

      * **the clock** (TRN_Clock): counted here, saved here, told to clients;
      * **the routes there are**: for now, the dev test line;
      * **who is aboard what**, by username: on a deck, or inside a car. A
        client asks to board, to get off, to go through a door; this file
        checks the request against its own clock and its own copy of where
        the player is, and answers. It also has the room of anybody inside
        a car built (TRN_Build), and relaxes a server's speed anti-cheat for
        the doors.

    A refusal is always sent with its reason, and writes nothing.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Plow"
require "TRN/TRN_Rooms"
require "TRN/TRN_Claims"
require "TRN/TRN_Build"
require "TRN/TRN_Track"
require "TRN/TRN_Herd"

TRN = TRN or {}
local C, U, Net, T, K = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock
local R, B, H, Cl = TRN.Rooms, TRN.Build, TRN.Herd, TRN.Claims

local S = {}
TRN.Server = S

S.sinceSync = 0

local function refuse(player, key, arg, b)
    Net.toClient(player, "refused", { who = U.username(player), key = key, arg = arg, b = b })
end

local function tellAll()
    Net.toAll("state", K.snapshot())
end

--- This player's rider record as it stands, or nil. Never makes one.
local function riderOf(player)
    local who = U.username(player)
    if not who or not K.state then return nil end
    return K.state.riders[who]
end

--- The route, the train and where it is now, for a train id; or nil.
local function trainNow(trainId)
    local route, train = T.find(K.routes(), trainId)
    if not route then return nil end
    return route, train, K.where(route, train)
end

--- True for somebody who may do what a train's owner may: its owner, or an
--- admin, asked of the server's own copy of the player.
local function owns(player, claim)
    return claim ~= nil and (claim.who == U.username(player) or U.admin(player))
end

--- A square a player can be put down on: there, with a floor.
local function standable(x, y, z)
    local sq = U.square(x, y, z)
    if not sq then return false end
    return U.try("server.floor", function()
        if sq:getFloor() == nil then return "hole" end
        return "ok"
    end) == "ok"
end

---------------------------------------------------------------------------
-- Hello
---------------------------------------------------------------------------
--- A client has a character in the world: the state, and whether the
--- server has them aboard something (a rider who left and came back).
Net.onServer("hello", function(player)
    if not K.state then return end
    local msg = K.snapshot()
    msg.who = U.username(player)
    local r = riderOf(player)
    if r then
        local route = T.find(K.routes(), r.train)
        if route then
            msg.train, msg.deck, msg.car, msg.top = r.train, r.deck, r.car, r.top
            r.told = nil
        else
            K.state.riders[msg.who] = nil
        end
    end
    Net.toClient(player, "state", msg)
end)

---------------------------------------------------------------------------
-- Boarding, getting off, changing deck
---------------------------------------------------------------------------
Net.onServer("board", function(player, args)
    local route, train, w = trainNow(args.train)
    if not route or not w then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    if w.moving then return refuse(player, "IGUI_TRN_RefuseMoving", math.ceil(w.arrive)) end
    local index = tonumber(args.deck)
    local px, py = nil, nil
    if index then px, py = T.deckAt(route, train, w, index) end
    if not px then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    -- Against the server's own copy of where they are, and on the track's level.
    local near = pcall(function()
        if math.floor(player:getZ()) ~= route.z then error("level") end
        local boxes = TRN.Plow.boxes(route, train, w, C.Deck.reach + 1.0)
        if not TRN.Plow.within(boxes, player:getX(), player:getY()) then error("far") end
    end)
    if not near then return refuse(player, "IGUI_TRN_RefuseFar") end
    -- A train its owner has closed carries its owner, and an admin.
    local claim = Cl.of(train.id)
    if claim and claim.closed and not owns(player, claim) then
        return refuse(player, "IGUI_TRN_RefuseClosed", train.name or train.id, claim.who)
    end
    local who = U.username(player)
    -- Where they stood on the ground: the way back for somebody the train
    -- is taken from under while they are inside it.
    K.state.ground = K.state.ground or {}
    K.state.ground[who] = { x = player:getX(), y = player:getY(), z = route.z }
    K.state.riders[who] = { train = train.id, deck = index }
    Net.toClient(player, "boarded", { who = who, train = train.id, deck = index })
    U.log("%s boarded %s at deck %d", tostring(who), train.id, index)
end)

Net.onServer("alight", function(player)
    local r = riderOf(player)
    if not r or not r.deck then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local who = U.username(player)
    local route, train, w = trainNow(r.train)
    if not route or not w then
        -- The train is gone from under them: they are where they stand.
        K.state.riders[who] = nil
        Net.toClient(player, "dropped", { who = who })
        return
    end
    if w.moving then return refuse(player, "IGUI_TRN_RefuseMovingOff", math.ceil(w.arrive)) end
    local px, py, ux, uy = T.deckAt(route, train, w, r.deck)
    local spot = nil
    for _, side in ipairs({ 1, -1 }) do
        local x, y = T.toWorld(px, py, ux, uy, 0, side * C.Deck.offside)
        if standable(x, y, route.z) then
            spot = { x = x, y = y }
            break
        end
    end
    if not spot then return refuse(player, "IGUI_TRN_RefuseNoRoom") end
    K.state.riders[who] = nil
    Net.toClient(player, "alighted", { who = who, x = spot.x, y = spot.y, z = route.z })
    U.log("%s got off %s", tostring(who), train.id)
end)

---------------------------------------------------------------------------
-- The cars' doors (DESIGN.md 5.1, 5.3)
---------------------------------------------------------------------------
--- The room of the car a rider is in, and the car's kind. A car's room is
--- its slot's: its place in the train, for every car but the empties
--- coupled on behind and the locomotive after them (TRN_Time.roll).
local function roomOf(r)
    local route, train = T.find(K.routes(), r.train)
    local index = route and R.indexOf(K.routes(), r.train)
    local car = train and T.layout(train.consist).cars[r.car]
    if not index or not car then return nil end
    return R.room(index, car.slot), car.kind
end

---------------------------------------------------------------------------
-- Animals on a rope (TRN_Herd; DESIGN.md 12)
---------------------------------------------------------------------------
--- Into a car, from a platform: the animals a rider leads go in with her
--- while the train stands, and are set down along the aisle from the door
--- she came in by, once the room is there. From a moving train's platform
--- there is nothing to bring: whatever is still on her rope is let go.
local function herdIn(player, who, route, train, slot, door)
    if not TRN.Setup.on("Lead") or H.led(player) == 0 then return end
    local w = K.where(route, train)
    local index = R.indexOf(K.routes(), train.id)
    if not w or w.moving or not index then
        local n = H.loose(player)
        if n > 0 then Net.toClient(player, "said", { who = who, key = "IGUI_TRN_HerdLeft", arg = n }) end
        return
    end
    local room = R.room(index, slot)
    local animals = H.take(player)
    if #animals == 0 then return end
    local x, y = R.spot(room, door)
    local dir = (door == "front") and 1 or -1
    H.hold(who, animals, x + dir, y, room.z, dir, 0)
    Net.toClient(player, "said", { who = who, key = "IGUI_TRN_HerdIn", arg = #animals })
    U.log("%s led %d animal(s) into %s car slot %d", tostring(who), #animals, train.id, slot)
end

--- Out of a car by its side door, at a stop: they come out beside her,
--- along the train.
local function herdOut(player, who, x, y, z, ux, uy)
    if not TRN.Setup.on("Lead") or H.led(player) == 0 then return end
    local animals = H.take(player)
    if #animals == 0 then return end
    H.hold(who, animals, x + ux, y + uy, z, ux, uy)
    Net.toClient(player, "said", { who = who, key = "IGUI_TRN_HerdOut", arg = #animals })
    U.log("%s led %d animal(s) out by a side door", tostring(who), #animals)
end

--- Out of a car by an end door, onto a platform: nothing with four legs
--- rides outside. The rope is let go and they stay in the car.
local function herdStay(player, who)
    if not TRN.Setup.on("Lead") or H.led(player) == 0 then return end
    local n = H.loose(player)
    if n > 0 then Net.toClient(player, "said", { who = who, key = "IGUI_TRN_HerdStay", arg = n }) end
end

--- Builds the room a rider is in if its ground is loaded, and tells them
--- once when it stands.
local function serveRoom(player, r)
    local room, kind = roomOf(r)
    if not room then return false end
    if not B.ensure(room, kind) then return false end
    -- Where the map under the rooms is not loaded, not until the ground
    -- round the room has been cleared to black.
    -- And what grows is taken from much further out, before and after: a
    -- tree anywhere the rider's machine draws breaks the drawing of the room.
    B.ungrow(room)
    -- The black round the room is laid once, a part at a time, whatever
    -- the map; only where there is wilderness to hide is the rider held
    -- for it.
    if not B.blackened(room) then B.blacken(room) end
    if not B.cleared(room) then return false end
    -- Running water, and power where the car has it: now and then, for as
    -- long as somebody is in the car.
    r.served = (r.served or 0) + 1
    if r.served == 1 or U.mod(r.served, C.Rooms.serviceEvery) == 0 then B.service(room, kind) end
    if not r.told then
        r.told = true
        Net.toClient(player, "roomReady", { who = U.username(player) })
    end
    return true
end

--- Which of the two cars a deck joins a request names, or nil. Deck n is
--- between car n and car n + 1.
local function carOffDeck(r, args)
    local car = tonumber(args.car)
    if car ~= r.deck and car ~= r.deck + 1 then return nil end
    return car
end

--- From a deck, through the end door of one of the two cars it joins, by the
--- car's number. Moving or parked: an end door leads to the deck, never to
--- the ground. Some cars have no way in.
Net.onServer("enter", function(player, args)
    local r = riderOf(player)
    if not r or not r.deck then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train = T.find(K.routes(), r.train)
    if not route then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    local car = carOffDeck(r, args)
    if not car then return refuse(player, "IGUI_TRN_RefuseNotHere") end
    if not C.Cars[T.layout(train.consist).cars[car].kind].inside then
        return refuse(player, "IGUI_TRN_RefuseNoInside", car)
    end
    local who = U.username(player)
    -- Into the car ahead of the deck by its rear door, into the one behind by its front.
    local door = (car == r.deck) and "rear" or "front"
    local slot = T.slotOf(train.consist, car)
    -- A car its train's owner has locked: the owner goes in, and an admin.
    local claim = Cl.of(train.id)
    if claim and Cl.locked(train.id, slot) and not owns(player, claim) then
        return refuse(player, "IGUI_TRN_RefuseLocked", car, claim.who)
    end
    -- Which room she went into is kept with her: if the train is made of other cars when she is
    -- next looked at, she is in a room that is not this car's any more (S.unman).
    K.state.riders[who] = { train = train.id, car = car, slot = slot }
    herdIn(player, who, route, train, slot, door)
    Net.toClient(player, "entered", { who = who, train = train.id, car = car, door = door })
    U.log("%s went into %s car %d", tostring(who), train.id, car)
end)

--- From a deck, up onto the top of one of the two cars it joins. Any car:
--- a tank and a flatcar have no inside, and every car has a top.
Net.onServer("climb", function(player, args)
    local r = riderOf(player)
    if not r or not r.deck then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train = T.find(K.routes(), r.train)
    if not route then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    local car = carOffDeck(r, args)
    if not car then return refuse(player, "IGUI_TRN_RefuseNotHere") end
    local kind = C.Cars[T.layout(train.consist).cars[car].kind]
    local who = U.username(player)
    K.state.riders[who] = { train = train.id, top = car }
    -- She comes up at the end she climbed: the car ahead's rear, the car behind's front.
    local along = (kind.topLen - 0.5) * ((car == r.deck) and -1 or 1)
    Net.toClient(player, "boarded", { who = who, train = train.id, top = car, a = along })
    U.log("%s climbed onto %s car %d", tostring(who), train.id, car)
end)

--- Down off the top of a car, onto the deck at one end of it.
Net.onServer("descend", function(player, args)
    local r = riderOf(player)
    if not r or not r.top then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train = T.find(K.routes(), r.train)
    if not route then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    local deck = tonumber(args.deck)
    if (deck ~= r.top - 1 and deck ~= r.top) or not T.layout(train.consist).decks[deck] then
        return refuse(player, "IGUI_TRN_RefuseEnd")
    end
    local who = U.username(player)
    K.state.riders[who] = { train = train.id, deck = deck }
    -- She comes down at the end of the platform she came to it by: off the
    -- car ahead of it at its front, off the car behind it at its rear.
    local along = C.Deck.halfLen * ((deck == r.top) and 1 or -1)
    Net.toClient(player, "boarded", { who = who, train = train.id, deck = deck, a = along })
end)

--- A rider inside asks whether the room stands (an arrival asks again now
--- and then: TRN_Inside).
Net.onServer("room", function(player)
    local r = riderOf(player)
    if not r or not r.car then return end
    r.told = nil
    serveRoom(player, r)
end)

--- Out of a car by an end door, onto the deck beyond it.
Net.onServer("exitTo", function(player, args)
    local r = riderOf(player)
    if not r or not r.car then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train = T.find(K.routes(), r.train)
    if not route then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    local deck = (args.door == "front") and (r.car - 1) or r.car
    if not T.layout(train.consist).decks[deck] then return refuse(player, "IGUI_TRN_RefuseEnd") end
    local who = U.username(player)
    herdStay(player, who)
    K.state.riders[who] = { train = train.id, deck = deck }
    Net.toClient(player, "boarded", { who = who, train = train.id, deck = deck })
end)

--- Out of a car by its side door, onto the ground beside it. Only at a stop.
Net.onServer("leave", function(player)
    local r = riderOf(player)
    if not r or not r.car then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train, w = trainNow(r.train)
    if not route or not w then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    if w.moving then return refuse(player, "IGUI_TRN_RefuseMovingOff", math.ceil(w.arrive)) end
    local car = T.layout(train.consist).cars[r.car]
    local px, py, ux, uy = T.carAt(route, w.c, car)
    -- The ground there has not been loaded by anybody: it cannot be looked
    -- at from here. Beside the track, on the side the test line's maker
    -- stood; the client is put there and the ground streams in round it.
    local x, y = T.toWorld(px, py, ux, uy, 0, C.Deck.offside)
    local who = U.username(player)
    herdOut(player, who, x, y, route.z, ux, uy)
    K.state.riders[who] = nil
    Net.toClient(player, "alighted", { who = who, x = x, y = y, z = route.z })
    U.log("%s left %s by car %d's side door", tostring(who), train.id, r.car)
end)

--- An arrival that never got its room: back onto a deck of the same car.
Net.onServer("bail", function(player)
    local r = riderOf(player)
    if not r or not r.car then return end
    local route, train = T.find(K.routes(), r.train)
    if not route then return end
    local decks = T.layout(train.consist).decks
    local deck = decks[r.car] and r.car or (r.car - 1)
    local who = U.username(player)
    K.state.riders[who] = { train = train.id, deck = deck }
    Net.toClient(player, "boarded", { who = who, train = train.id, deck = deck })
    U.log("WARN %s never got the inside of %s car %d and was put back on deck %d", tostring(who),
          train.id, r.car, deck)
end)

--- Somebody is standing in the rooms' ground and is aboard nothing: put
--- them back where they last boarded from, checked against the server's
--- own copy of where they are.
Net.onServer("stranded", function(player)
    if riderOf(player) then return end
    local who = U.username(player)
    local there = U.try("server.strandedAt", function() return R.ground(player:getX(), player:getY()) end)
    if there ~= true then return end
    local g = K.state and K.state.ground and K.state.ground[who]
    if not g then
        U.warnOnce("stranded:" .. tostring(who), "%s is in the rooms' ground with nowhere recorded to go back to",
                   tostring(who))
        return
    end
    Net.toClient(player, "alighted", { who = who, x = g.x, y = g.y, z = g.z })
    U.log("%s was stranded in the rooms' ground and was put back at %.1f,%.1f", tostring(who), g.x, g.y)
end)

--- The line is going: nobody is left inside a car of it. Each is set down
--- beside where their car is now. (Riders on a deck are let go where they
--- stand, by their own clients.)
local function emptyCars(only)
    if not K.state then return end
    for who, r in pairs(K.state.riders) do
        if r.car and (not only or only(r)) then
            local player = nil
            for _, p in ipairs(U.players()) do
                if U.username(p) == who then player = p end
            end
            local route, train, w = trainNow(r.train)
            local car = train and T.layout(train.consist).cars[r.car]
            if player and w and car then
                local px, py, ux, uy = T.carAt(route, w.c, car)
                local x, y = T.toWorld(px, py, ux, uy, 0, C.Deck.offside)
                Net.toClient(player, "alighted", { who = who, x = x, y = y, z = route.z })
            end
        end
    end
end

---------------------------------------------------------------------------
-- A stop out on the line (DESIGN.md 4.1b)
---------------------------------------------------------------------------
--- Stops asked for on beats that are over are forgotten.
local function oldHalts()
    local s = K.state
    if not s or not s.halts then return end
    local beat = math.floor(s.t / (K.dwell() + K.moveTime()))
    for id, h in pairs(s.halts) do
        if h.beat < beat then s.halts[id] = nil end
    end
end

--- Anybody aboard can pull the cord: the train comes quickly to a stand,
--- waits, and makes the time up before the next station. Where there is
--- not the time left for that, it says so, and how long to the station.
Net.onServer("pull", function(player)
    if not TRN.Setup.on("Cord") then return refuse(player, "IGUI_TRN_RefuseNoCord") end
    local r = riderOf(player)
    if not r then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local route, train, w = trainNow(r.train)
    if not route or not w then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    if not w.moving then return refuse(player, "IGUI_TRN_RefuseStanding") end
    oldHalts()
    K.state.halts = K.state.halts or {}
    if K.state.halts[train.id] and K.state.halts[train.id].beat == w.beat then
        return refuse(player, "IGUI_TRN_RefuseStopping")
    end
    local S_ = C.Stop
    -- An even braking: in `brake` seconds it covers half what it would have.
    local ps = w.part + w.rate * S_.brake / 2
    local halt = (ps < 1) and T.halt(w.leg, w.beat, w.tau, w.part, w.rate, ps, S_.brake, S_.hold, K.moveTime(), S_.fastest)
    if not halt then return refuse(player, "IGUI_TRN_NoTimeToStop", math.ceil(w.arrive)) end
    K.state.halts[train.id] = halt
    tellAll()
    Net.toClient(player, "said", { who = U.username(player), key = "IGUI_TRN_Pulled", arg = S_.hold })
    U.log("%s pulled the cord on %s, %.0f%% of the way to its next stop: it stands %d s and makes the time up",
          tostring(U.username(player)), train.id, ps * 100, S_.hold)
end)

--- Anybody beside the track, aboard nothing, can ask the next train along
--- to stop for them there. It is told when that will be. **Or one train by
--- name** (`args.train`: TRN_Trip, somebody waiting for a train of her
--- choosing): then it is that train or none, the next time it runs this
--- stretch, which on the circle is within a lap.
Net.onServer("flag", function(player, args)
    if not TRN.Setup.on("Flag") then return refuse(player, "IGUI_TRN_RefuseNoFlag") end
    if riderOf(player) or not K.state then return refuse(player, "IGUI_TRN_RefuseInside") end
    local at = U.try("server.flagFrom", function()
        return { x = player:getX(), y = player:getY(), z = math.floor(player:getZ()) }
    end)
    if not at then return end
    local S_ = C.Stop
    local only = args and args.train or nil
    local route, d = nil, nil
    for _, r in ipairs(K.routes()) do
        if r.z == at.z and (only == nil or T.find({ r }, only) ~= nil) then
            local dd, far = T.nearest(r, at.x, at.y)
            if dd and far <= S_.reach then route, d = r, dd end
        end
    end
    if not route then return refuse(player, "IGUI_TRN_RefuseNoTrack") end
    oldHalts()
    K.state.halts = K.state.halts or {}
    local tm, td = K.moveTime(), K.dwell()
    local cycle = td + tm
    local now = K.state.t
    local beat = math.floor(now / cycle)
    local phase = now - beat * cycle
    local legs = T.legs(route)
    local best = nil
    -- The train on this stretch now, if it has yet to pass; else whichever
    -- runs it on the next beat or the one after, from standing.
    for _, at_ in ipairs(T.legsAt(route, d)) do
        if at_.part > S_.clear and at_.part < 1 - S_.clear then
            for ahead = 0, #legs do
                local b = beat + ahead
                for _, train in ipairs(route.trains) do
                    if U.mod(b + (train.offset or 0), #legs) + 1 == at_.index
                       and (only == nil or train.id == only)
                       and not (K.state.halts[train.id] and K.state.halts[train.id].beat >= beat) then
                        local halt = nil
                        if ahead == 0 and phase >= td then
                            local w = T.where(route, train, now, tm, td, K.state.halts)
                            local gap = at_.part - w.part
                            if w.moving and gap > 0.002 then
                                halt = T.halt(w.leg, b, w.tau, w.part, w.rate, at_.part, gap * tm, S_.hold, tm, S_.fastest)
                            end
                        else
                            halt = T.halt(legs[at_.index], b, 0, 0, 0, at_.part, at_.part * tm, S_.hold, tm, S_.fastest)
                        end
                        if halt then
                            local when = b * cycle + td + halt.t0 + halt.ta - now
                            if not best or when < best.when then best = { train = train, halt = halt, when = when } end
                        end
                    end
                end
                if best then break end
            end
        end
    end
    if not best and only then
        -- The one train asked for is too far into this leg to stand here and
        -- still keep its time, or is stopping somewhere already.
        return refuse(player, "IGUI_TRN_RefuseNoTime")
    end
    if not best then
        -- On a stretch, and too near a station for a train to stop twice.
        return refuse(player, #T.legsAt(route, d) > 0 and "IGUI_TRN_RefuseNearStop" or "IGUI_TRN_RefuseNoTrack")
    end
    K.state.halts[best.train.id] = best.halt
    tellAll()
    Net.toClient(player, "said", { who = U.username(player), key = "IGUI_TRN_Flagged", arg = math.ceil(best.when) })
    U.log("%s flagged down %s at %.0f along %s: it stands there in %.0f s", tostring(U.username(player)),
          best.train.id, d, route.id, best.when)
end)

--- A rider's client says they are no longer aboard: dead, or let go.
Net.onServer("gone", function(player)
    local who = U.username(player)
    if who and K.state then K.state.riders[who] = nil end
end)

---------------------------------------------------------------------------
-- A host's own lines (SERVERS.md)
---------------------------------------------------------------------------
-- An admin lays a line in the game: a row of points where they stood, some
-- of them stops. The server takes it, rounds its corners, gives it track
-- beyond its end stops for a train to stand on, numbers its trains after
-- the map's, and saves it with the world. It is a route like the map's
-- from then on: on the one beat, on every player's map, boarded and
-- flagged down like any other. **It has no rails**: a train is a picture
-- of the timetable and runs where the line says, over anything.

local function admin(player)
    if U.admin(player) then return true end
    U.log("refused %s: admin", tostring(U.username(player)))
    refuse(player, "IGUI_TRN_RefuseAdmin")
    return false
end

local function say(player, key, a, b, c, d)
    Net.toClient(player, "said", { who = U.username(player), key = key, arg = a, b = b, c = c, d = d })
end

--- A line of points with every corner made an arc (tools/gen_rails.py
--- `rounded`, in Lua): a car is twelve squares and rigid, and on a square
--- corner a train looks derailed.
local function rounded(pts, closed)
    local n, out = #pts, {}
    for i = 1, n do
        local b = pts[i]
        if not closed and (i == 1 or i == n) then
            out[#out + 1] = { b[1], b[2] }
        else
            local a, c = pts[(i > 1) and (i - 1) or n], pts[(i < n) and (i + 1) or 1]
            local v1x, v1y, v2x, v2y = b[1] - a[1], b[2] - a[2], c[1] - b[1], c[2] - b[2]
            local l1, l2 = math.sqrt(v1x * v1x + v1y * v1y), math.sqrt(v2x * v2x + v2y * v2y)
            local u1x, u1y, u2x, u2y = v1x / l1, v1y / l1, v2x / l2, v2y / l2
            local cross, dot = u1x * u2y - u1y * u2x, u1x * u2x + u1y * u2y
            local turn = U.angle(dot, cross)
            if math.abs(turn) < math.rad(4) or math.abs(turn) > math.rad(170) then
                out[#out + 1] = { b[1], b[2] }
            else
                local half = math.tan(math.abs(turn) / 2)
                local back = math.min(C.Lines.bend * half, l1 * 0.45, l2 * 0.45)
                local r = back / half
                local sx, sy = b[1] - u1x * back, b[2] - u1y * back
                local side = (turn > 0) and 1 or -1
                local cx, cy = sx - u1y * r * side, sy + u1x * r * side
                local steps = math.max(2, math.floor(math.abs(turn) / math.rad(9)))
                local a0 = U.angle(sx - cx, sy - cy)
                for k = 0, steps do
                    local t = a0 + turn * k / steps
                    out[#out + 1] = { cx + r * math.cos(t), cy + r * math.sin(t) }
                end
            end
        end
    end
    return out
end

--- The trains whose ids begin so are nobody's any more: their line is gone.
local function disown(lead)
    local claims = K.state and K.state.claims
    if type(claims) ~= "table" then return end
    for id in pairs(claims) do
        if string.sub(id, 1, #lead) == lead then claims[id] = nil end
    end
end

--- Half the longest train there can be as the sandbox stands, and a little:
--- how much track a line run out and back needs beyond each end stop, so
--- that a train standing there is on the line.
local function beyond()
    local Su = TRN.Setup
    local cars = 0
    local own = Su.consist()
    if own then
        cars = #own
    else
        local L = C.Roll.lengths[Su.length()]
        cars = 2 + #C.Roll.always + L.seats[2] + L.extra[2] + Su.empties()
    end
    return math.ceil((cars * C.CarLen + (cars - 1) * C.Gap) / 2) + 6
end

--- The lowest block of `slots` train numbers no line has.
local function freeBlock(lines, slots)
    local most = C.Rooms.trains - 1 - T.mapped()
    local at = 0
    while at + slots <= most do
        local clash = false
        for _, line in ipairs(lines) do
            if at < (line.room0 or 0) + (line.slots or 0) and (line.room0 or 0) < at + slots then
                clash = true
                at = (line.room0 or 0) + (line.slots or 0)
                break
            end
        end
        if not clash then return at end
    end
    return nil
end

--- How many train numbers are free for a host's own lines.
local function freeSlots(lines)
    local used = 0
    for _, line in ipairs(lines) do used = used + (line.slots or 0) end
    return C.Rooms.trains - 1 - T.mapped() - used
end

Net.onServer("lineAdd", function(player, args)
    if not admin(player) or not K.state then return end
    local s, L = K.state, C.Lines
    if s.line then return refuse(player, "IGUI_TRN_RefuseLineTest") end
    if riderOf(player) then return refuse(player, "IGUI_TRN_RefuseInside") end
    s.lines = s.lines or {}
    if #s.lines >= L.most then return refuse(player, "IGUI_TRN_RefuseLineMany", L.most) end
    local closed = args.closed == true
    -- What was sent, as numbers and nothing else: a client is never believed.
    local raw, stops = {}, 0
    for _, p in ipairs(type(args.pts) == "table" and args.pts or {}) do
        if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and p.x == p.x and p.y == p.y then
            local name = nil
            if type(p.stop) == "string" then
                name = string.sub(p.stop:gsub("^%s+", ""):gsub("%s+$", ""), 1, L.nameMost)
                if name == "" then name = nil end
            end
            if name then stops = stops + 1 end
            raw[#raw + 1] = { math.floor(p.x) + 0.5, math.floor(p.y) + 0.5, stop = name }
        end
    end
    if #raw > L.points then return refuse(player, "IGUI_TRN_RefuseLineLong", L.points) end
    if stops < 2 then return refuse(player, "IGUI_TRN_RefuseLineStops") end
    if closed and #raw < 3 then return refuse(player, "IGUI_TRN_RefuseLineLoop") end
    if #raw < 2 then return refuse(player, "IGUI_TRN_RefuseLineStops") end
    for i = 1, closed and #raw or #raw - 1 do
        local a, b = raw[i], raw[(i < #raw) and (i + 1) or 1]
        local far = math.sqrt((b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]))
        if far < L.apart then return refuse(player, "IGUI_TRN_RefuseLineShort", L.apart) end
    end
    -- A line run out and back: straight on past each end, far enough for a
    -- train to stand at its end stop with all of itself on the line.
    local pts = {}
    for i, p in ipairs(raw) do pts[i] = { p[1], p[2] } end
    if not closed then
        local ext = beyond()
        local a, b = pts[1], pts[2]
        local len = math.sqrt((b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]))
        table.insert(pts, 1, { a[1] - (b[1] - a[1]) / len * ext, a[2] - (b[2] - a[2]) / len * ext })
        a, b = pts[#pts], pts[#pts - 1]
        len = math.sqrt((b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]))
        pts[#pts + 1] = { a[1] - (b[1] - a[1]) / len * ext, a[2] - (b[2] - a[2]) / len * ext }
    end
    local z = U.try("server.lineLevel", function() return math.floor(player:getZ()) end) or 0
    local route = { closed = closed, pts = rounded(pts, closed) }
    T.measure(route)
    -- Each stop, by how far along the line it is: in the order a train
    -- meets them from the line's first point (TRN_Time.legs counts on it).
    local named = {}
    for _, p in ipairs(raw) do
        if p.stop then
            local d = T.nearest(route, p[1], p[2])
            named[#named + 1] = { d = d, name = p.stop }
        end
    end
    table.sort(named, function(a, b) return a.d < b.d end)
    for i = 1, closed and #named or #named - 1 do
        local a, b = named[i], named[(i < #named) and (i + 1) or 1]
        local leg = b.d - a.d
        if leg < 0 then leg = leg + route.len end
        if leg < L.legLeast then return refuse(player, "IGUI_TRN_RefuseLineClose", L.legLeast) end
    end
    local slots = closed and #named or 2
    local room0 = freeBlock(s.lines, slots)
    if not room0 then return refuse(player, "IGUI_TRN_RefuseNoRooms", slots, freeSlots(s.lines)) end
    s.lineSerial = (s.lineSerial or 0) + 1
    local name = type(args.name) == "string" and string.sub(args.name:gsub("^%s+", ""):gsub("%s+$", ""), 1, L.nameMost) or ""
    if name == "" then name = "Line " .. s.lineSerial end
    local line = { id = "own" .. s.lineSerial .. "t", name = name, closed = closed, z = z, pts = route.pts,
                   stops = named, slots = slots, room0 = room0 }
    s.lines[#s.lines + 1] = line
    K.changed()
    tellAll()
    local made = nil
    for _, r in ipairs(K.routes()) do
        if r.id == line.id then made = r end
    end
    say(player, "IGUI_TRN_LineLaid", name, math.floor(route.len), #named, made and #made.trains or 0)
    U.log("%s laid the line %s (%s): %s, %.0f squares in %d points, %d stops, trains numbered %d to %d; every leg "
          .. "anywhere now takes %.0f s", tostring(U.username(player)), line.id, name,
          closed and "a loop" or "out and back", route.len, #route.pts, #named, T.mapped() + room0 + 1,
          T.mapped() + room0 + slots, K.moveTime())
end)

Net.onServer("lineDrop", function(player, args)
    if not admin(player) or not K.state then return end
    local s = K.state
    local found, line = nil, nil
    for i, l in ipairs(s.lines or {}) do
        if l.id == args.id then found, line = i, l end
    end
    if not found then return refuse(player, "IGUI_TRN_RefuseLineGone") end
    -- Nobody is left aboard a train of it: those in its cars are set down
    -- beside where their car is now.
    emptyCars(function(r) return string.sub(r.train or "", 1, #line.id) == line.id end)
    table.remove(s.lines, found)
    -- Its trains' numbers are free for the next line, and so are their
    -- cells: the rooms that stood in them are forgotten, so that the next
    -- train of that number has rooms of its own, raised afresh and emptied
    -- first (TRN_Build: a room with no record is a room never raised).
    local forgot = 0
    for number = T.mapped() + (line.room0 or 0) + 1, T.mapped() + (line.room0 or 0) + (line.slots or 0) do
        local lead = number .. ":"
        for key in pairs(s.rooms or {}) do
            if string.sub(key, 1, #lead) == lead then
                B.forget(key)
                forgot = forgot + 1
            end
        end
    end
    if s.halts then
        for id in pairs(s.halts) do
            if string.sub(id, 1, #line.id) == line.id then s.halts[id] = nil end
        end
    end
    -- And they are nobody's: the next train of that number is another train.
    disown(line.id)
    K.changed()
    tellAll()
    say(player, "IGUI_TRN_LineTaken", line.name)
    U.log("%s took up the line %s (%s); %d room(s) of its trains' cars are forgotten", tostring(U.username(player)),
          line.id, tostring(line.name), forgot)
end)

---------------------------------------------------------------------------
-- Whose train it is (TRN_Claims; DESIGN.md 5.8)
---------------------------------------------------------------------------
-- Somebody aboard a train makes it theirs, up to as many as the host allows
-- (sandbox Claims). Its owner locks its cars and closes it to everybody
-- else; an admin passes every lock and ends any claim. The claims are in
-- the state, and every client is told when one changes.

--- A claim to change, for its owner or an admin; or nil, and they are told.
local function claimFor(player, args)
    local id = type(args.train) == "string" and args.train or nil
    local claim = id and Cl.of(id) or nil
    if not owns(player, claim) then
        refuse(player, "IGUI_TRN_RefuseNotOwner")
        return nil
    end
    local _, train = T.find(K.routes(), id)
    return claim, id, train
end

--- Whoever is aboard a train may make it theirs, if it is nobody's and
--- they have not as many as a player may.
Net.onServer("claim", function(player)
    local s, most = K.state, Cl.most()
    if not s or most < 1 then return refuse(player, "IGUI_TRN_RefuseNoClaims") end
    local r = riderOf(player)
    local _, train = T.find(K.routes(), r and r.train)
    if not train then return refuse(player, "IGUI_TRN_RefuseNotAboard") end
    local who = U.username(player)
    local held = Cl.of(train.id)
    if held then return refuse(player, "IGUI_TRN_RefuseClaimed", train.name or train.id, held.who) end
    if #Cl.owned(who) >= most then return refuse(player, "IGUI_TRN_RefuseClaimMany", most) end
    s.claims = s.claims or {}
    s.claims[train.id] = { who = who, made = TRN.Setup.cars() }
    tellAll()
    say(player, "IGUI_TRN_Claimed", train.name or train.id)
    U.log("%s claimed %s: %d of the %d a player may own", tostring(who), train.id, #Cl.owned(who), most)
end)

--- Its owner gives a train up, from anywhere; or an admin ends the claim.
Net.onServer("unclaim", function(player, args)
    local claim, id, train = claimFor(player, args or {})
    if not claim then return end
    K.state.claims[id] = nil
    tellAll()
    say(player, "IGUI_TRN_ClaimDropped", train and train.name or id)
    U.log("%s ended %s's claim on %s", tostring(U.username(player)), tostring(claim.who), id)
end)

--- Its owner locks a car by its number, or unlocks it; with no number,
--- every car there is a way into.
Net.onServer("lock", function(player, args)
    local claim, id, train = claimFor(player, args or {})
    if not claim then return end
    if not train then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    local cars = T.layout(train.consist).cars
    local on = args.on == true
    -- Locks written when the trains were made of other cars are nobody's.
    if type(claim.cars) ~= "table" or claim.made ~= TRN.Setup.cars() then claim.cars = {} end
    claim.made = TRN.Setup.cars()
    if args.car == nil then
        claim.cars = {}
        if on then
            for _, car in ipairs(cars) do
                if C.Cars[car.kind].inside then claim.cars[Cl.key(car.slot)] = true end
            end
        end
        tellAll()
        say(player, on and "IGUI_TRN_ClaimAllLocked" or "IGUI_TRN_ClaimAllUnlocked")
    else
        local n = tonumber(args.car)
        local car = n and cars[n] or nil
        if not car or not C.Cars[car.kind].inside then return refuse(player, "IGUI_TRN_RefuseNoInside", n or 0) end
        claim.cars[Cl.key(car.slot)] = on or nil
        tellAll()
        say(player, on and "IGUI_TRN_ClaimLocked" or "IGUI_TRN_ClaimUnlocked", n)
    end
    U.log("%s %s %s of %s (%s's)", tostring(U.username(player)), on and "locked" or "unlocked",
          args.car == nil and "every car" or ("car " .. tostring(args.car)), id, tostring(claim.who))
end)

--- Its owner closes a train to everybody else, or opens it.
Net.onServer("close", function(player, args)
    local claim, id, train = claimFor(player, args or {})
    if not claim then return end
    claim.closed = (args.on == true) or nil
    tellAll()
    say(player, claim.closed and "IGUI_TRN_ClaimClosed" or "IGUI_TRN_ClaimOpened", train and train.name or id)
    U.log("%s %s %s (%s's)", tostring(U.username(player)), claim.closed and "closed" or "opened", id, tostring(claim.who))
end)

--- A closed train carries its owner and nobody else: anybody else aboard,
--- on a platform, on a top or in a car, is put off beside it the next time
--- it stands. Never from a moving train. (A locked car puts nobody out: a
--- lock is on the door.)
function S.putOff()
    if not K.state then return end
    for _, p in ipairs(U.players()) do
        local r = riderOf(p)
        local claim = r and Cl.of(r.train) or nil
        if claim and claim.closed and not owns(p, claim) then
            local route, train, w = trainNow(r.train)
            local px, py, ux, uy = nil, nil, nil, nil
            if w and not w.moving and r.deck then
                px, py, ux, uy = T.deckAt(route, train, w, r.deck)
            elseif w and not w.moving then
                local car = T.layout(train.consist).cars[r.car or r.top]
                if car then px, py, ux, uy = T.carAt(route, w.c, car) end
            end
            if px then
                -- Where there is a floor to be seen, on it; from inside a car
                -- the ground by the train is nobody's to look at, as at its
                -- side door.
                local x, y = T.toWorld(px, py, ux, uy, 0, C.Deck.offside)
                for _, side in ipairs({ 1, -1 }) do
                    local sx, sy = T.toWorld(px, py, ux, uy, 0, side * C.Deck.offside)
                    if standable(sx, sy, route.z) then
                        x, y = sx, sy
                        break
                    end
                end
                local who = U.username(p)
                K.state.riders[who] = nil
                Net.toClient(p, "alighted", { who = who, x = x, y = y, z = route.z })
                refuse(p, "IGUI_TRN_RefuseClosed", train.name or train.id, claim.who)
                U.log("%s was put off %s, which %s has closed", tostring(who), train.id, tostring(claim.who))
            end
        end
    end
end

--- What a host changed in the sandbox while the world ran: anybody aboard a
--- train there no longer is, is aboard nothing. (Somebody in such a train's
--- car is in the rooms' ground with no train: her own machine asks to be
--- put back where she boarded, `stranded`.)
function S.unman()
    if not K.state then return end
    -- The rooms moved (sandbox RoomsX, RoomsY): whoever is in a car is in a
    -- room that is no longer its car's. Each is set down beside their car,
    -- as when a line is taken up.
    local cell = R.where()
    if S.cell and S.cell ~= cell then
        emptyCars()
        local out = 0
        for who, r in pairs(K.state.riders) do
            if r.car then
                K.state.riders[who] = nil
                out = out + 1
            end
        end
        U.log("the sandbox moved the cars' insides from cells %s to %s: %d rider(s) inside a car were set down beside it",
              S.cell, cell, out)
    end
    S.cell = cell
    -- And whoever is in a car whose room is not the room she went into: the
    -- train is made of other cars now (the sandbox's Empties, or a build
    -- that coupled empties on), or has not that car at all. She is set down
    -- beside where the car is, or, where there is none, is found in the
    -- rooms' ground aboard nothing and put back where she boarded.
    for who, r in pairs(K.state.riders) do
        if r.car then
            local _, train = T.find(K.routes(), r.train)
            if train and T.slotOf(train.consist, r.car) ~= (r.slot or r.car) then
                emptyCars(function(other) return other == r end)
                K.state.riders[who] = nil
                U.log("%s was in car %d of %s, which is another car now: set down beside it", tostring(who), r.car,
                      tostring(r.train))
            end
        end
    end
    local stamp = TRN.Setup.stamp()
    if S.stamp == stamp then return end
    local first = S.stamp == nil
    S.stamp = stamp
    if first then return end
    local routes = K.routes()
    local gone = 0
    for who, r in pairs(K.state.riders) do
        if not T.find(routes, r.train) then
            K.state.riders[who] = nil
            gone = gone + 1
        end
    end
    U.log("the sandbox's trains changed: %d route(s) now, every leg takes %.0f s; %d rider(s) were aboard a train "
          .. "that is gone", #routes, K.moveTime(), gone)
    tellAll()
end

---------------------------------------------------------------------------
-- The dev build
---------------------------------------------------------------------------
local function dev(player)
    if C.DevTools then return true end
    refuse(player, "IGUI_TRN_RefuseDev")
    return false
end

--- Lays the test line beside whoever asked, running east or south, with
--- its middle stop level with them and the train parked at it.
Net.onServer("layLine", function(player, args)
    if not dev(player) or not K.state then return end
    local axis = (args.axis == "y") and "y" or "x"
    local D = C.Dev
    local at = U.try("server.where", function()
        return { x = math.floor(player:getX()) + 0.5, y = math.floor(player:getY()) + 0.5,
                 z = math.floor(player:getZ()) }
    end)
    if not at then return end
    -- Not from inside a car: a line laid there would run through the rooms.
    if R.ground(at.x, at.y) then return refuse(player, "IGUI_TRN_RefuseInside") end
    emptyCars()
    -- A line long enough for its train: a stop is more than half a train
    -- from the end of the line, and from the next stop.
    local half = math.ceil(T.layout(D.consist).len / 2) + 4
    local inset = math.max(D.inset, half)
    local len = math.max(D.length, 4 * inset + 110)
    local line = { z = at.z, axis = axis, len = len, inset = inset, dwell = D.dwell, consist = D.consist }
    if args.bend then
        -- East, then a turn to the right. Its middle stop, the last before
        -- the turn, is level with whoever laid it; the line is north of them.
        line.axis, line.bend = "x", true
        line.before = math.max(D.bendBefore, 2 * inset + 60)
        line.after = math.max(D.bendAfter, inset + 105)
        line.x, line.y = at.x - (line.before - inset), at.y - D.beside
    elseif axis == "x" then
        line.x, line.y = at.x - len / 2, at.y - D.beside
    else
        line.x, line.y = at.x - D.beside, at.y - len / 2
    end
    K.state.line = line
    K.state.riders = {}
    disown("dev")
    K.changed()
    -- The clock goes on to the next beat that has the train parked at the
    -- middle stop, which is beside whoever laid the line, with the whole of
    -- its wait still to run. The first play (2026-10-08) laid a line and
    -- found the train eighty tiles off and leaving.
    local route = K.routes()[1]
    local legs = T.legs(route)
    local cycle = K.dwell() + K.moveTime()
    local beat = math.floor(K.state.t / cycle) + 1
    for _ = 1, #legs do
        if legs[U.mod(beat, #legs) + 1].a == 2 then break end
        beat = beat + 1
    end
    K.state.t = beat * cycle
    tellAll()
    U.log("dev: a test line laid from %.1f,%.1f running %s for %d on level %d; every leg takes %.1f s",
          line.x, line.y, line.bend and "east and round a bend to the south" or (axis == "x" and "east" or "south"),
          K.routes()[1].len, line.z, K.moveTime())
end)

Net.onServer("clearLine", function(player)
    if not dev(player) or not K.state then return end
    emptyCars()
    K.state.line = nil
    K.state.riders = {}
    disown("dev")
    K.changed()
    tellAll()
    U.log("dev: the test line is taken up")
end)

--- Puts whoever asks beside the stop nearest them, on any route: the map's
--- stops are a long walk apart, and a test is not mostly walking. Not from
--- aboard anything.
Net.onServer("goStop", function(player)
    if not dev(player) or not K.state then return end
    if riderOf(player) then return refuse(player, "IGUI_TRN_RefuseInside") end
    local at = U.try("server.goFrom", function() return { x = player:getX(), y = player:getY() } end)
    if not at then return end
    local best, bestD = nil, nil
    for _, route in ipairs(K.routes()) do
        for _, stop in ipairs(route.stops) do
            local x, y, ux, uy = T.at(route, stop.d)
            local d = (x - at.x) * (x - at.x) + (y - at.y) * (y - at.y)
            if not bestD or d < bestD then
                local sx, sy = T.toWorld(x, y, ux, uy, 0, C.Deck.offside + 1.5)
                best, bestD = { x = sx, y = sy, z = route.z, stop = stop }, d
            end
        end
    end
    if not best then return refuse(player, "IGUI_TRN_RefuseNoTrain") end
    Net.toClient(player, "alighted", { who = U.username(player), x = best.x, y = best.y, z = best.z })
    U.log("dev: %s was taken to %s, at %.1f,%.1f", tostring(U.username(player)), U.stopName(best.stop), best.x, best.y)
end)

--- Jumps the clock to just before the next departure or arrival, so a test
--- is not mostly waiting.
Net.onServer("skip", function(player)
    if not dev(player) or not K.state then return end
    local nextAt = T.nextChange(K.state.t, K.moveTime(), K.dwell())
    local to = nextAt - C.Dev.skipTo
    if to > K.state.t then
        K.state.t = to
        tellAll()
        U.log("dev: the clock skipped to %.1f s", to)
    end
end)

---------------------------------------------------------------------------
-- Every tick
---------------------------------------------------------------------------
--- Sets a server's speed anti-cheat from kick or ban to log, in memory,
--- unless the sandbox says to leave it (pz_trekship TREK_Server.lua, PLAYED
--- there). Every door of a car is a move of thousands of squares, which is
--- two or three strikes of the four that kick (DESIGN.md 6).
function S.relaxSpeedCheck()
    if not isServer() then return false end
    local mode = U.try("server.sandboxSpeed", function()
        return SandboxVars.Trains and SandboxVars.Trains.SpeedCheck
    end)
    if tonumber(mode) == 2 then return false end
    local speed = tonumber(U.try("server.antiCheatSpeed", function()
        return getServerOptions():getOption("AntiCheatSpeed")
    end))
    if speed ~= 1 and speed ~= 2 then return false end
    U.try("server.relax", function() getServerOptions():putOption("AntiCheatSpeed", "3") end)
    U.log("speed anti-cheat set from %s to log (3) for the cars' doors; sandbox Speed anti-cheat = "
          .. "Leave it as set keeps the server's own", speed == 1 and "ban (1)" or "kick (2)")
    return true
end

S.sinceRooms, S.sinceRelax, S.sinceTrack = 0, 0, 0

--- Now and then: the room of everybody who is inside a car is built, if its
--- ground has streamed in, and mended if it has a hole.
function S.rooms()
    if not K.state then return end
    local anybody = false
    for _, p in ipairs(U.players()) do
        local r = riderOf(p)
        if r and r.car then
            anybody = true
            -- (The wood round a room, where the map is not loaded, is
            -- cleared in serveRoom, before its rider is let in. It was done
            -- here as well: each covered for the other, and a mutation of
            -- either was missed.)
            serveRoom(p, r)
        end
    end
    if anybody then B.unhaunt() end
end

--- Everybody the server has on the top of a car: its own copy of them is
--- off the floor, with nothing holding it, and banks a fall every tick.
--- Cleared here, every tick (pz-heros HERO_Server.holdFlyers).
function S.holdTops()
    if not K.state then return end
    for _, p in ipairs(U.players()) do
        local r = riderOf(p)
        if r and r.top then
            U.try("server.unfall", function()
                p:setFallTime(0)
                p:setLastFallSpeed(0)
                p:setbFalling(false)
                p:clearFallDamage()
            end)
        end
    end
end

function S.tick()
    local before = K.state and K.state.t or 0
    K.tick()
    U.try("server.holdTops", S.holdTops)
    S.sinceRooms = S.sinceRooms + 1
    if S.sinceRooms >= 5 then
        S.sinceRooms = 0
        U.try("server.rooms", S.rooms)
        -- Animals taken through a door are set down once the place they come out at is there.
        U.try("server.herd", function() H.tick(5) end)
    end
    -- The sidings round vanilla's parked cars, a stretch at a time, as
    -- their ground streams in round somebody (DESIGN.md 4.3).
    S.sinceTrack = S.sinceTrack + 1
    if S.sinceTrack >= C.Track.every then
        S.sinceTrack = 0
        U.try("server.track", TRN.Track.pass)
        U.try("server.unman", S.unman)
        U.try("server.putOff", S.putOff)
    end
    S.sinceRelax = S.sinceRelax - 1
    if S.sinceRelax <= 0 then
        S.sinceRelax = 3600
        U.try("server.relaxTick", S.relaxSpeedCheck)
    end
    if not isServer() or not K.state then return end
    S.sinceSync = S.sinceSync + (K.state.t - before)
    if S.sinceSync >= C.SyncEvery then
        S.sinceSync = 0
        Net.toAll("clock", { t = K.state.t })
    end
end

Events.OnInitGlobalModData.Add(function()
    U.try("server.load", K.load)
    U.try("server.map", B.mapLoaded)
end)
Events.OnTick.Add(function() U.try("server.tick", S.tick) end)

U.log("authority loaded, version %s", C.Version)

return S
