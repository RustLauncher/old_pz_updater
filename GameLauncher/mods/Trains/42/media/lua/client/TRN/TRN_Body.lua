if isServer() then return end

--[[ Trains -- the train a player can see (DESIGN.md 3.3).

    A train has no physics and is not a vehicle. It is a row of car models,
    and **each client draws every train near it, from the clock**: nothing
    is sent, nothing is owned, and a watcher at a crossing and a rider on a
    deck see the same train because they do the same sum.

    How a model is drawn in the world with the world's depth is the Heroes
    mod's, PLAYED there for a hand-sized flame (pz-heros POWERS.md 3.5):

      * Events.RenderOpaqueObjectsInWorld is fired in the world pass, just
        before the characters are drawn;
      * Render3DItem(item, square, x, y, z, turn) draws an item's world
        model at any point: z is a height above that square's floor, in
        levels, and the turn is about the upright, in degrees, 0 or more;
      * which model is the item's mod data `worldStaticModel`, looked up in
        module Base. So a carrier item, never put anywhere, is told which
        car to be.

    READ here, 42 as installed 2026-10-08, and not as the Heroes notes have
    it: the event is fired on every frame the world is drawn.
    FBORenderCell.renderOpaqueObjectsEvent returns early, with a mouse, only
    if UIManager.getPickedTile() is null, and that is a vector made once
    when the class loads and never set to null by the engine. **Not played
    for anything this size**: whether a model seven tiles long is drawn
    whole, lit, and sorted against a building beside it, only the game
    shows (DESIGN.md 9, spike 1).

    And one thing a player's own options decide: with *3D ground items*
    off, WorldItemModelDrawer.renderMain answers NoModel before it looks at
    anything, and the train is a row of fishing bobbers.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Models"

TRN = TRN or {}
local C, U, T, K = TRN.Config, TRN.Util, TRN.Time, TRN.Clock

local B = {}
TRN.Body = B

B.carriers = {}         -- model name -> the item that is drawn as it
B.stats = { frames = 0, cars = 0, noSquare = 0, numbers = 0, marks = 0, figures = 0, pieces = 0, plates = 0 }
B.markers = {}          -- the ground markers on this revision's stops
B.markersRev = nil
B.markersDue = 0

--- The carrier item for a model, made on first use.
function B.carrier(model)
    local item = B.carriers[model]
    if item ~= nil then return item or nil end
    item = U.try("body.carrier", function()
        local it = instanceItem(C.Carrier)
        it:getModData().worldStaticModel = model
        return it
    end)
    B.carriers[model] = item or false
    U.log("body: carrier for %s %s", model, item and "ready" or "FAILED")
    return item
end

local draw = U.batch("body.draw")

--- A model, drawn: every piece of it, at the one place. The engine swaps a
--- model's texture for a smaller copy when it is bigger than the player's
--- Max texture size, which goes down to 256 pixels, so a model painted on
--- a bigger sheet is cut into pieces of a 256 sheet each (TRN_Models.lua,
--- tools/meshpage.py; PLAYED 2026-10-10: "processed and blurred"). A
--- model that was not cut is drawn as itself. Returns whether all of it
--- was handed to the engine.
local function show_(model, sq, x, y, level, yaw)
    local pieces = TRN.Pages and TRN.Pages[model]
    if not pieces then
        local item = B.carrier(model)
        if not item then return false end
        Render3DItem(item, sq, x, y, level, yaw)
        return true
    end
    local all = true
    for _, piece in ipairs(pieces) do
        local item = B.carrier(piece)
        if item then
            Render3DItem(item, sq, x, y, level, yaw)
            B.stats.pieces = B.stats.pieces + 1
        else
            all = false
        end
    end
    return all
end

--- One piece of train, drawn. The square is the one its middle is over; a
--- model is lit by its square, and Render3DItem draws nothing without one.
local function put(model, x, y, z, yaw, home)
    local sq = U.square(x, y, z) or home
    if not sq then
        B.stats.noSquare = B.stats.noSquare + 1
        return false
    end
    return show_(model, sq, x, y, 0, yaw)
end

--- How a plate lying on a car's top is turned: along the car, and whichever
--- way round has its picture's top away from the camera, which looks from
--- the south-east. The top of a plate turned with a car going (ux, uy) is
--- toward (uy, -ux).
function B.topYaw(ux, uy)
    return T.yaw(ux, uy, (ux - uy) < 0)
end

--- A car's number: a small plate lying at each end of its top, along the
--- car, and one on each of its ends, over the door. One digit: a train has
--- under ten cars.
function B.number(route, car, n, x, y, ux, uy, home)
    local N = C.Numbers
    local kind = C.Cars[car.kind]
    -- One plate, whatever the number: there is a picture for each up to C.Numbers.most.
    local digit = tostring(U.mod(n, N.most + 1)) .. (N.mirror and "m" or "")
    local item = B.carrier(N.top .. digit)
    local sq = U.square(x, y, route.z) or home
    if item and sq then
        local d = kind.len / 2 - N.fromEnd
        for _, s in ipairs({ 1, -1 }) do
            Render3DItem(item, sq, x + ux * d * s, y + uy * d * s, kind.top + N.lift, B.topYaw(ux, uy))
        end
        B.stats.numbers = B.stats.numbers + 1
    end
    item = B.carrier(N.ends .. digit)
    if item and sq then Render3DItem(item, sq, x, y, kind.top - N.drop, T.yaw(ux, uy, false)) end
end

--- One green mark, `level` levels up.
local function mark(model, x, y, z, level, yaw, home)
    local item = B.carrier(model)
    local sq = U.square(x, y, z) or home
    if not (item and sq) then return end
    Render3DItem(item, sq, x, y, level, yaw)
    B.stats.marks = B.stats.marks + 1
end

--- A green square on the ground: a point of a line an admin is laying
--- (TRN_Admin).
function B.spot(x, y, z, home)
    mark(C.Marks.flat, x, y, z, C.Marks.lift, 0, home)
end

--- Whether this player is within a tile or so of a point (`slack` more for
--- a thing that has a width of its own).
local function close(player, x, y, slack)
    local dx, dy = player:getX() - x, player:getY() - y
    local reach = C.Marks.near + (slack or 0)
    return dx * dx + dy * dy <= reach * reach
end

--- Where this player can go from where she is, in green (C.Marks): each
--- only while she is next to it.
function B.marks(player, home)
    local M = C.Marks
    local r = TRN.Deck and TRN.Deck.record and TRN.Deck.record(player) or nil
    local inside = TRN.Inside and TRN.Inside.record and TRN.Inside.record(player) or nil
    if inside and inside.room then
        -- Inside a car: the floor before each of its three doors. Two of
        -- them are in walls the camera looks through.
        for _, door in ipairs({ "front", "rear", "side" }) do
            local x, y = TRN.Rooms.spot(inside.room, door)
            if close(player, x, y) then mark(M.flat, x, y, inside.room.z, M.lift, 0, home) end
        end
        return
    end
    if not r then
        -- On the ground, beside a parked train: the platform she would board.
        local near = TRN.Menu and TRN.Menu.nearestDeck and TRN.Menu.nearestDeck(player) or nil
        if near and not near.w.moving then
            local x, y, ux, uy = T.deckAt(near.route, near.train, near.w, near.deck)
            if close(player, x, y, C.Deck.halfWid) then
                mark(M.flat, x, y, near.route.z, M.lift, T.yaw(ux, uy, false), home)
            end
        end
        return
    end
    local route, train = T.find(K.routes(), r.train)
    local w = route and K.where(route, train)
    if not w then return end
    local layout = T.layout(train.consist)
    if r.top then
        -- On a top: the platform at an end of the car she is at the end of.
        local car = layout.cars[r.top]
        local cx, cy, cux, cuy = T.carAt(route, w.c, car)
        local half = C.Cars[car.kind].topLen
        for _, e in ipairs({ { deck = r.top - 1, s = 1 }, { deck = r.top, s = -1 } }) do
            if layout.decks[e.deck] and close(player, cx + cux * half * e.s, cy + cuy * half * e.s) then
                local x, y, ux, uy = T.deckAt(route, train, w, e.deck)
                mark(M.flat, x, y, route.z, M.lift, T.yaw(ux, uy, false), home)
            end
        end
        return
    end
    -- On a platform: the car ahead shows it its rear end, the car behind its front.
    for _, e in ipairs({ { car = r.deck, rear = true }, { car = r.deck + 1, rear = false } }) do
        local car = layout.cars[e.car]
        if car then
            local kind = C.Cars[car.kind]
            local x, y, ux, uy = T.carAt(route, w.c, car)
            local s = e.rear and -1 or 1
            -- The car's end: where its door and its ladder are.
            if close(player, x + ux * kind.len / 2 * s, y + uy * kind.len / 2 * s) then
                if kind.inside then mark(M.door, x, y, route.z, 0, T.yaw(ux, uy, e.rear), home) end
                local d = (kind.len / 2 - M.fromEnd) * s
                mark(M.flat, x + ux * d, y + uy * d, route.z, kind.top + M.lift, T.yaw(ux, uy, false), home)
            end
        end
    end
end

--- Five figures of the sign: "HH:MM", at a place on the north wall.
local function figures(text, x, y, z, level, home)
    local S = C.Signs
    for i = 1, #text do
        local ch = text:sub(i, i)
        local item = B.carrier(S.led .. (ch == ":" and "C" or ch))
        local sq = U.square(x, y, z) or home
        if item and sq then
            Render3DItem(item, sq, x + S.first + (i - 1) * S.pitch, y, level, 0)
            B.stats.figures = B.stats.figures + 1
        end
    end
end

local function two(n)
    n = math.floor(n)
    return (n < 10 and "0" or "") .. tostring(n)
end

--- What a car's sign says: the world's clock, and how long by that clock
--- until the train is at its next stop, or leaves the one it is at; and
--- which of the two the second is. A train's own clock is seconds of play
--- at normal speed, and a day of the world lasts minutesPerDay minutes of
--- those (TRN_Clock), so a second of the train's is 24 / minutesPerDay
--- minutes on the wall.
function B.signText(w)
    local g = U.try("body.gameTime", function()
        local t = getGameTime()
        return { h = t:getHour(), m = t:getMinutes(), perDay = t:getMinutesPerDay() }
    end)
    if not g then return nil end
    local now = two(U.mod(g.h, 24)) .. ":" .. two(U.mod(g.m, 60))
    if not w then return now, nil, false end
    local secs = w.moving and w.arrive or w.depart or 0
    local mins = math.min(99 * 60 + 59, math.ceil(secs * 24 / math.max(1, g.perDay)))
    return now, two(math.floor(mins / 60)) .. ":" .. two(U.mod(mins, 60)), not w.moving
end

--- Inside a car, for whoever is in it: its number over its front door, and
--- the sign on its north wall.
function B.inside(player, home)
    local rec = TRN.Inside and TRN.Inside.record and TRN.Inside.record(player) or nil
    if not rec or not rec.room or rec.arriving then return end
    local S, room = C.Signs, rec.room
    local function show(model, x, y, level)
        local sq = U.square(x, y, room.z) or home
        if sq then show_(model, sq, x, y, level, 0) end
    end
    if rec.car <= C.Numbers.most then
        show(S.plate .. rec.car, room.x0 + S.out, room.y0 + C.Rooms.wid / 2, S.plateUp)
    end
    local route, train = T.find(K.routes(), rec.train)
    local w = route and K.where(route, train) or nil
    local now, left, standing = B.signText(w)
    if not now then return end
    local x, y = room.x0 + S.dx, room.y0 + S.out
    show(standing and S.dep or S.arr, x, y, S.up)
    -- The figures a hair nearer the room than the box they are on.
    figures(now, x, y + 0.02, room.z, S.up + S.row, home)
    if left then figures(left, x, y + 0.02, room.z, S.up - S.row, home) end
end

--- The model a car wears: one of its kind's outsides, the one its train
--- was rolled with, or the kind's own where it was rolled with none.
function B.modelOf(car)
    local kind = C.Cars[car.kind]
    if car.skin and kind.skins and #kind.skins > 0 then
        return kind.skins[math.min(#kind.skins, math.floor(car.skin * #kind.skins) + 1)]
    end
    return kind.model
end

--- The engine is about to draw the characters: every car near this player
--- goes into the world first.
function B.render(playerIndex)
    local routes = K.routes()
    if #routes == 0 then return end
    local t = K.now()
    if not t then return end
    local player = U.try("body.who", function() return getSpecificPlayer(playerIndex) end)
    if not player then return end
    draw(function()
        local px, py = player:getX(), player:getY()
        local home = U.square(px, py, player:getZ())
        local tm, td = K.moveTime(), K.dwell()
        local far = C.DrawRange * C.DrawRange
        B.stats.frames = B.stats.frames + 1
        for _, route in ipairs(routes) do
            for _, train in ipairs(route.trains) do
                local w = T.where(route, train, t, tm, td, K.state and K.state.halts)
                local layout = T.layout(train.consist)
                -- A train whose middle is further off than half its length and
                -- what a player sees has no car in sight: the map's routes have
                -- a score of trains, and all but one or two are a long way away.
                local mx, my = T.at(route, w.c)
                local reach = C.DrawRange + layout.len / 2 + 20
                local close = (mx - px) * (mx - px) + (my - py) * (my - py) <= reach * reach
                for i, car in ipairs(close and layout.cars or {}) do
                    local x, y, ux, uy = T.carAt(route, w.c, car)
                    local dx, dy = x - px, y - py
                    if dx * dx + dy * dy <= far then
                        B.number(route, car, i, x, y, ux, uy, home)
                        -- What it is, on both its sides: turned with the car, flipped or not.
                        local plate = TRN.Setup.on("Plates") and C.Plates[car.kind] or nil
                        if plate and put(plate, x, y, route.z, T.yaw(ux, uy, car.flip), home) then
                            B.stats.plates = B.stats.plates + 1
                        end
                        if put(B.modelOf(car), x, y, route.z, T.yaw(ux, uy, car.flip), home) then
                            B.stats.cars = B.stats.cars + 1
                            if B.stats.cars == 1 then
                                U.log("body: the first car was handed to the engine: %s at %.1f,%.1f turned %.0f",
                                      B.modelOf(car), x, y, T.yaw(ux, uy, car.flip))
                            end
                        end
                    end
                end
                for _, deck in ipairs(close and layout.decks or {}) do
                    local x, y, ux, uy = T.pose(route, w.c + deck.rel, C.Gap / 2)
                    local dx, dy = x - px, y - py
                    if dx * dx + dy * dy <= far then
                        put(C.DeckModel, x, y, route.z, T.yaw(ux, uy, false), home)
                    end
                end
            end
        end
        B.marks(player, home)
        B.inside(player, home)
        if TRN.Admin then TRN.Admin.draw(player, home) end
    end)
end

Events.RenderOpaqueObjectsInWorld.Add(B.render)

---------------------------------------------------------------------------
-- The stops, marked on the ground
---------------------------------------------------------------------------
-- Until a stop is a station (DESIGN.md 4.2), it is a ring on the ground:
-- vanilla's ground markers, PLAYED in the Shuttlecraft and the Heroes mod
-- for a shadow. Each client's own; nothing is put in the world.

local function unmark()
    for _, m in ipairs(B.markers) do
        if m.marker then U.try("body.unmark", function() m.marker:remove() end) end
    end
    B.markers = {}
end

--- The routes changed: the rings are owed again. B.mark takes the old ones
--- up when it sees the revision is not the one it marked (one place, so
--- that a mutation of it is caught: tests/mutate.py).
function B.changed()
    B.markersRev = nil
    B.markersDue = 0
end

--- Puts a ring on every stop whose ground is loaded. A stop out of sight
--- gets its ring when its ground streams in.
function B.mark()
    local s = K.state
    if not s then return end
    if B.markersRev ~= s.rev then
        unmark()
        B.markersRev = s.rev
        for _, route in ipairs(K.routes()) do
            for i, stop in ipairs(route.stops) do
                local x, y = T.at(route, stop.d)
                B.markers[#B.markers + 1] = { x = x, y = y, z = route.z, index = i }
            end
        end
    end
    local M = C.StopMarker
    for _, m in ipairs(B.markers) do
        if not m.marker then
            local sq = U.square(m.x, m.y, m.z)
            if sq then
                m.marker = U.try("body.mark", function()
                    local mk = getWorldMarkers():addGridSquareMarker(M.texture, M.texture, sq,
                                                                     M.r, M.g, M.b, false, M.size)
                    if mk then mk:setAlpha(M.alpha) end
                    return mk
                end)
            end
        end
    end
end

Events.OnTick.Add(function()
    local now = U.nowMs()
    if now < B.markersDue then return end
    B.markersDue = now + 1000
    U.try("body.markTick", B.mark)
end)

Events.OnCreatePlayer.Add(function()
    -- A new character is a new cell: the markers went with the old one.
    B.markers = {}
    B.markersRev = nil
end)

function B.status()
    local marked = 0
    for _, m in ipairs(B.markers) do
        if m.marker then marked = marked + 1 end
    end
    U.log("status: body drew %d car(s) over %d frame(s), in %d piece(s) drawn, and %d plate(s), %d with no square; "
          .. "%d of %d stop(s) marked", B.stats.cars, B.stats.frames, B.stats.pieces, B.stats.plates, B.stats.noSquare,
          marked, #B.markers)
end

return B
