if isServer() then return end

--[[ Trains -- holding this player on the outside of a moving train (DESIGN.md 3.5).

    Two places on a train are outdoors, in the real world, while it moves:

      * a **deck**: the platform between two cars, at the ground's own level;
      * the **top** of a car: its roof, a tank's catwalk, a flatcar's deck.
        A rider climbs up from a deck and can walk the car's length.

    The train is a picture, so there is nothing there to stand on. **Each
    client holds its own character there, every frame:**

        world position = the perch's place at the clock's time
                         + where the player stands on it

    and "where the player stands on it" is the only part the player's
    walking changes. It is clamped to the perch's outline (TRN_Time.riderOn),
    and that clamp is the whole of "cannot fall off": the edge is the end of
    the set of places a rider can be. There is no jump and no fall off a
    car's top, because neither is offered anywhere to end.

    What makes it work, each PLAYED and each the answer to a build that did
    not (DEV_GUIDE.md, "Riding a thing that is not there"):

      * **the engine does her walking**, animation and all. Each frame this
        file asks where she is *going* (getNextX: a step is in the next
        position until after the update event, and setX writes over it),
        reads that as a place on the perch as it stood when she was last
        put down, holds it inside the edge, and puts her at the same place
        on the perch as it stands now;
      * **a long move is held on the tick.** Coming aboard from a car's
        inside she is `landing`: pinned, here and again on OnTick, until
        the ground under the perch has been seen for a few ticks. After a
        character's update the engine puts her back on her last square if
        she has none, and only a move made again on the tick is still there
        when it decides what ground to load.

    **A top is under one level up** (C.Cars[kind].top), on purpose. To the
    engine she is still on the ground's own level, on a square that exists,
    and is only drawn higher: no square has to be made in the air, as the
    Heroes mod's flight must. But she is off the floor, so the engine's
    falling runs on her every tick and banks a fall: it is cleared every
    frame, speed and all (pz-heros DEV_GUIDE.md, "Holding a character off a
    floor banks a fall": the first hero to hover died of it). **Not played.**
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"

TRN = TRN or {}
local C, U, Net, T, K = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock

local D = {}
TRN.Deck = D

-- username -> { train, deck or top (a car's number), a, b (where she stands
--   on it), px, py, ux, uy (where it stood when she was last put down),
--   landing, said (what the speaker last said) }
D.riding = {}
D.stats = { held = 0, skipped = 0, runs = 0 }

local function nameOf(player) return U.username(player) or "?" end

function D.aboard(player)
    return player ~= nil and D.riding[nameOf(player)] ~= nil
end

function D.record(player)
    return player and D.riding[nameOf(player)] or nil
end

---------------------------------------------------------------------------
-- Putting her down
---------------------------------------------------------------------------
--- Gives the engine's walking back. Nothing holds it since 0.1.3; this is
--- for a character who was aboard under 0.1.0 to 0.1.2, which did.
local function hold(player, on)
    U.try("deck.block", function() player:setBlockMovement(on) end)
end

--- The engine's fall state, cleared, speed and all (pz-heros HERO_Sky.lua).
local function unfall(player)
    U.try("deck.fall", function()
        player:setFallTime(0)
        player:setLastFallSpeed(0)
        player:setbFalling(false)
        player:clearFallDamage()
    end)
end
D.unfall = unfall

--- True while the game is running faster than normal.
---
--- **A rider on a car's top is stood on the ground's own level for as long
--- as it is** (PLAYED 2026-10-09, twice: "speeding up time on the roof of
--- the train leads to death"). On a top she is off the floor, and the
--- engine's falling runs on her in her own update: at normal speed it takes
--- a fiftieth of a level a frame and this file gives it back. At forty
--- times it takes the whole height in one update, she lands, and the
--- landing is a fall from a moving train's roof, every frame, until she is
--- dead. Nothing done after the update can undo a landing. On the floor
--- there is no fall to bank. She is drawn inside the car until the speed
--- comes back, which at forty times nobody is looking at.
local function fast()
    return U.try("deck.speed", function()
        return UIManager.getSpeedControls():getCurrentGameSpeed() > 1
    end) == true
end
D.fast = fast

--- True when there is a floor at a place: its ground has streamed in.
local function floorUnder(x, y, z)
    local sq = U.square(x, y, z)
    if not sq then return false end
    return U.try("deck.floor", function() return sq:getFloor() ~= nil end) == true
end

local function place(player, x, y, z)
    U.try("deck.move", function()
        player:setX(x) player:setY(y)
        player:setLastX(x) player:setLastY(y)
        player:setZ(z) player:setLastZ(z)
    end)
    unfall(player)
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------
--- The server has this player on a deck, or on the top of a car: the
--- middle of it, or (`a`) so far along it.
function D.board(player, trainId, deck, top, a)
    local who = nameOf(player)
    -- From one part of a train to the next (a platform to a top, a top to a
    -- platform): she is where she was, the ground under her is loaded, and
    -- she keeps her place across the train. Nothing to wait for, and a
    -- runner is not stopped at every ladder.
    local old = D.riding[who]
    local across = old ~= nil and old.train == trainId and not old.landing
    -- No remembered place: the first frame puts her where `a` says. Coming
    -- from anywhere else she is `landing`: pinned there until the ground
    -- under her is seen.
    D.riding[who] = { train = trainId, deck = deck, top = top, a = a or 0, b = across and old.b or 0,
                      said = across and old.said or "", landing = (not across) and { tries = 0, settled = 0 } or nil }
    if not top and not across then
        local _, train = T.find(K.routes(), trainId)
        U.note(player, getText("IGUI_TRN_Aboard", U.trainName(train)), 150, 220, 150)
    end
    U.log("deck: %s is aboard %s %s", who, tostring(trainId),
          top and ("on top of car " .. tostring(top)) or ("at deck " .. tostring(deck)))
end

--- The server let her off, at this spot beside the train.
function D.alight(player, x, y, z)
    D.riding[nameOf(player)] = nil
    place(player, x, y, z)
    U.log("deck: %s got off at %.1f,%.1f", nameOf(player), x, y)
end

--- She has gone inside a car: the deck lets go of her and says nothing.
function D.release(player)
    D.riding[nameOf(player)] = nil
end

--- She is no longer aboard, where she stands: the train is gone. Somebody
--- on a car's top is set on the ground under her.
function D.drop(player)
    local r = D.riding[nameOf(player)]
    if not r then return end
    D.riding[nameOf(player)] = nil
    if r.top then
        U.try("deck.down", function()
            local z = math.floor(player:getZ())
            player:setZ(z) player:setLastZ(z)
        end)
        unfall(player)
    end
    U.log("deck: %s was let go where she stood", nameOf(player))
end

--- The routes changed: anybody riding a train that is not there is let go.
function D.check()
    for who, r in pairs(D.riding) do
        if not T.find(K.routes(), r.train) then
            local p = TRN.Client and TRN.Client.player(who)
            if p then D.drop(p) else D.riding[who] = nil end
        end
    end
end

--- A character has appeared. Nothing of a ride survives a load on this
--- side: walking is ours to give back. If the server still has her aboard,
--- its answer to the hello puts her back. Called by TRN_Client **before**
--- it says hello, and not hung on the event here: see there.
function D.reset(player)
    D.riding[nameOf(player)] = nil
    hold(player, false)
end

---------------------------------------------------------------------------
-- The speaker (DESIGN.md 5.4)
---------------------------------------------------------------------------
--- Says what is coming, once each: the next stop on the way, the arrival,
--- and the doors. Words over her head; a car's speaker says the same lines
--- to somebody inside it (TRN_Inside).
function D.speak(player, r, route, w)
    local line, arg = nil, nil
    local stop = route.stops[w.moving and w.to or w.at]
    local name = U.stopName(stop)
    if w.halted then
        line, arg = "IGUI_TRN_SayHalted", name
    elseif w.moving then
        if w.arrive <= C.Speaker.arriving then
            line, arg = "IGUI_TRN_SayArriving", name
        else
            line, arg = "IGUI_TRN_SayNext", name
        end
    else
        if w.depart <= C.Speaker.departing then
            line, arg = "IGUI_TRN_SayDeparting", name
        else
            line, arg = "IGUI_TRN_SayAt", name
        end
    end
    local key = line .. ":" .. tostring(w.moving and w.to or w.at) .. (w.halted and (":" .. w.beat) or "")
    if r.said == key then return end
    r.said = key
    local secs = math.ceil(w.moving and w.arrive or w.depart)
    U.note(player, getText(line, arg, tostring(secs)), 230, 230, 160)
end

---------------------------------------------------------------------------
-- Running the length of the train
---------------------------------------------------------------------------
--- Somebody running who has run off the end of what she stands on goes on
--- to the next thing: off a top, down to the platform; off a platform, up
--- onto the next car (the author, 2026-10-09: "if we are running we should
--- auto drop down / climb up so we can quickly run across the entire
--- length of the train"). `r.a` is where her step would have taken her
--- along it, before the edge holds her. Walking, the edge is the edge, as
--- it was. The server is asked, as the menu asks it, and not twice in a
--- moment.
function D.overrun(player, r, train, halfLen)
    if r.a <= halfLen + C.Deck.runPast and r.a >= -halfLen - C.Deck.runPast then return false end
    local running = U.try("deck.running", function() return player:isRunning() or player:isSprinting() end)
    if running ~= true then return false end
    local now = U.nowMs()
    if r.askedMs and now - r.askedMs < C.Deck.runAskMs then return false end
    local layout = T.layout(train.consist)
    local ahead = r.a > 0
    if r.top then
        -- Deck n - 1 is at the front of car n, deck n at its rear.
        local deck = ahead and (r.top - 1) or r.top
        if not layout.decks[deck] then return false end
        r.askedMs = now
        Net.send(player, "descend", { deck = deck })
    else
        -- Deck n is between car n, ahead of it, and car n + 1.
        local car = ahead and r.deck or (r.deck + 1)
        if not layout.cars[car] then return false end
        r.askedMs = now
        Net.send(player, "climb", { car = car })
    end
    D.stats.runs = D.stats.runs + 1
    return true
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------
--- One frame of riding for one local player.
function D.step(player, r)
    local route, train = T.find(K.routes(), r.train)
    local w = route and K.where(route, train)
    if not w then return end
    local px, py, ux, uy, halfLen = T.perch(route, train, w, r)
    if not px then return end

    -- Where the engine's walking has taken her since she was last put
    -- down, as a place on the perch where it stood then. Her *next*
    -- position, and not while the ground under the perch is not there:
    -- what the engine says of a character over ground it has not loaded is
    -- not a step, and she is pinned until it has.
    local grounded = floorUnder(px, py, route.z)
    local L = r.landing
    if L then
        L.tries = L.tries + 1
        L.settled = grounded and (L.settled + 1) or 0
        if L.tries == 1 or L.tries == 300 or L.tries == 1200 then
            U.log("deck: landing tick %d at %.1f,%.1f: ground %s; the engine has her at %s,%s going to %s,%s",
                  L.tries, px, py, grounded and "loaded" or "not loaded",
                  tostring(U.try("deck.gx", function() return player:getX() end)),
                  tostring(U.try("deck.gy", function() return player:getY() end)),
                  tostring(U.try("deck.nx", function() return player:getNextX() end)),
                  tostring(U.try("deck.ny", function() return player:getNextY() end)))
        end
        if L.settled >= C.Rooms.settle then
            r.landing = nil
            U.log("deck: %s is on the %s after %d tick(s)", nameOf(player), r.top and "top" or "deck", L.tries)
        end
    elseif r.px and grounded then
        local nx = U.try("deck.nextX", function() return player:getNextX() end)
        local ny = U.try("deck.nextY", function() return player:getNextY() end)
        -- A number, and a real one: a position that is not a number is not
        -- equal to itself, and one written back would never come right.
        if nx and ny and nx == nx and ny == ny then
            r.a, r.b = T.toLocal(r.px, r.py, r.ux, r.uy, nx, ny)
            -- In single player the answer is here before the question has
            -- returned (DEV_GUIDE.md): she may already be on the next thing,
            -- and the rest of this frame is that one's.
            if D.overrun(player, r, train, halfLen) then
                local now = D.riding[nameOf(player)]
                if now and now ~= r then return D.step(player, now) end
            end
        end
    end
    local x, y, a, b, h = T.riderOn(route, train, w, r, r.a, r.b)
    r.a, r.b = a, b
    if h ~= 0 and fast() then h = 0 end

    if not grounded then D.stats.skipped = D.stats.skipped + 1 end
    place(player, x, y, route.z + h)
    r.px, r.py, r.ux, r.uy = px, py, ux, uy
    D.stats.held = D.stats.held + 1
    D.speak(player, r, route, w)
end

Events.OnPlayerUpdate.Add(function(player)
    if not player then return end
    local r = D.riding[nameOf(player)]
    if not r then return end
    if not U.try("deck.isLocal", function() return player:isLocalPlayer() end) then return end
    U.try("deck.step", D.step, player, r)
end)

--- Riders put where they belong again at the end of the tick: one who is
--- landing, so that the move sticks (above); and one on a car's top, so
--- that what the engine's falling took off her height in its own update is
--- given back before she is drawn.
function D.pin()
    for i = 0, 3 do
        local player = U.try("deck.pinWho", function() return getSpecificPlayer(i) end)
        local r = player and D.riding[nameOf(player)]
        if r and (r.landing or r.top) then
            local route, train = T.find(K.routes(), r.train)
            local w = route and K.where(route, train)
            if w then
                local x, y, _, _, h = T.riderOn(route, train, w, r, r.a, r.b)
                if x and h ~= 0 and fast() then h = 0 end
                if x and r.landing then
                    place(player, x, y, route.z + h)
                elseif x then
                    U.try("deck.lift", function()
                        player:setZ(route.z + h) player:setLastZ(route.z + h)
                    end)
                    unfall(player)
                end
            end
        end
    end
end

Events.OnTick.Add(function() U.try("deck.pin", D.pin) end)

Events.OnPlayerDeath.Add(function(player)
    if not player or not D.riding[nameOf(player)] then return end
    D.riding[nameOf(player)] = nil
    Net.send(player, "gone", {})
end)

function D.status()
    local n = 0
    for who, r in pairs(D.riding) do
        n = n + 1
        U.log("status: %s rides %s %s at %.2f along, %.2f across", who, tostring(r.train),
              r.top and ("on top of car " .. tostring(r.top)) or ("deck " .. tostring(r.deck)), r.a, r.b)
    end
    U.log("status: %d riding here; %d frame(s) held, %d skipped for unloaded ground, %d run(s) on to the next car",
          n, D.stats.held, D.stats.skipped, D.stats.runs)
end

return D
