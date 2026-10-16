--[[ Trains -- the timetable (DESIGN.md 3.1, 3.2).

    Where every train is, is a pure function of one clock. Nothing in this
    file touches the world, the network or the engine: it is arithmetic, and
    every machine does the same sum and gets the same train.

    A **route** is a polyline with stops along it:

        { id, z, closed, pts = { {x, y}, ... }, stops = { { d, key }, ... },
          trains = { { id, consist, offset } } }

    `d` is a distance along the polyline. A closed route is a loop. One that
    is not is a line, run out and back: a train on it never turns round, it
    goes the other way, with a plow at each end.

    **The beat.** Every train on every route dwells for the same `td` and
    then moves for the same `tm`, from its stop to the next. So the speed on
    a leg is its length over tm, eased at both ends, and tm is what the
    longest leg anywhere needs to stay under the speed ceiling.

    **Never the % operator** (TRN_Util.mod): the game's is wrong for big
    numbers and for negatives. tests/test_kahlua.py runs this file in the
    game's own interpreter.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Routes"
require "TRN/TRN_Setup"

TRN = TRN or {}
local C, U = TRN.Config, TRN.Util

local T = {}
TRN.Time = T

---------------------------------------------------------------------------
-- A route's shape
---------------------------------------------------------------------------
--- Measures a route once: each segment's start distance and unit tangent.
function T.measure(route)
    if route.segs then return route end
    local segs, total = {}, 0
    local n = #route.pts
    local last = route.closed and n or n - 1
    for i = 1, last do
        local a = route.pts[i]
        local b = route.pts[(i < n) and (i + 1) or 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            segs[#segs + 1] = { d = total, len = len, x = a[1], y = a[2], ux = dx / len, uy = dy / len }
            total = total + len
        end
    end
    route.segs, route.len = segs, total
    return route
end

--- The point `d` along a route, and the way the track runs there: x, y,
--- ux, uy. A loop wraps; a line stops at its ends.
function T.at(route, d)
    T.measure(route)
    if route.closed then
        d = U.mod(d, route.len)
    else
        d = U.clamp(d, 0, route.len)
    end
    -- The last segment that begins at or before d: found by halving, for a
    -- route round the whole map is some hundreds of them and this is asked
    -- for every car of every train, every frame.
    local segs = route.segs
    local lo, hi = 1, #segs
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if segs[mid].d <= d then lo = mid else hi = mid - 1 end
    end
    local seg = segs[lo]
    local along = d - seg.d
    return seg.x + seg.ux * along, seg.y + seg.uy * along, seg.ux, seg.uy
end

--- Where a rigid thing `span` either side of the point `d` along a route
--- lies: its middle and the way it points, x, y, ux, uy. It rests on the
--- track at d - span and d + span and lies along the line between them. On
--- a straight that is T.at; on a bend it is what a car on two trucks does.
function T.pose(route, d, span)
    local ax, ay, tx, ty = T.at(route, d - span)
    local bx, by = T.at(route, d + span)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then return ax, ay, tx, ty end
    return (ax + bx) / 2, (ay + by) / 2, dx / len, dy / len
end

--- A car's place in the world, for a train whose middle is at `c`.
function T.carAt(route, c, car)
    return T.pose(route, c + car.rel, car.len * C.Trucks)
end

--- The legs a train on this route runs, in order, round and round. On a
--- line: out, stop by stop, and back.
function T.legs(route)
    if route.legs then return route.legs end
    T.measure(route)
    local legs, s = {}, route.stops
    local n = #s
    if route.closed then
        for i = 1, n do
            local j = (i < n) and (i + 1) or 1
            local to = s[j].d
            if j == 1 then to = to + route.len end
            legs[#legs + 1] = { a = i, b = j, from = s[i].d, to = to, len = to - s[i].d, dir = 1 }
        end
    else
        for i = 1, n - 1 do
            legs[#legs + 1] = { a = i, b = i + 1, from = s[i].d, to = s[i + 1].d,
                                len = s[i + 1].d - s[i].d, dir = 1 }
        end
        for i = n, 2, -1 do
            legs[#legs + 1] = { a = i, b = i - 1, from = s[i].d, to = s[i - 1].d,
                                len = s[i].d - s[i - 1].d, dir = -1 }
        end
    end
    route.legs = legs
    return legs
end

---------------------------------------------------------------------------
-- The beat
---------------------------------------------------------------------------
--- How long every train moves for: what the longest leg on any route needs
--- to stay under `top` at the peak of its ease.
function T.moveTime(routes, top)
    local tm = C.MinMove
    for _, route in ipairs(routes) do
        for _, leg in ipairs(T.legs(route)) do
            local need = C.EasePeak * leg.len / top
            if need > tm then tm = need end
        end
    end
    return tm
end

--- Eased 0..1: slow out, slow in. Its steepest is C.EasePeak.
function T.ease(u)
    if u <= 0 then return 0 end
    if u >= 1 then return 1 end
    return u * u * (3 - 2 * u)
end

function T.easeRate(u)
    if u <= 0 or u >= 1 then return 0 end
    return 6 * u * (1 - u)
end

--- Where a train is at clock `t`:
---   c         its middle, as a distance along the route
---   moving    false while it is parked
---   speed     tiles a second, never negative
---   dir       1 going up the route's distances, -1 coming back
---   at, to    the stop it is at or left, and the one it is going to
---   depart    seconds until it leaves (parked), else nil
---   arrive    seconds until it stops (moving), else nil
---
--- `halts` is the stops out on the line that have been asked for, by train
--- id (T.halt), or nil. While a train stands at one it is not `moving`,
--- `halted` is true and `depart` is how long it has left there.
function T.where(route, train, t, tm, td, halts)
    local legs = T.legs(route)
    local cycle = td + tm
    local beat = math.floor(t / cycle)
    local phase = t - beat * cycle
    local index = U.mod(beat + (train.offset or 0), #legs) + 1
    local leg = legs[index]
    local w = { at = leg.a, to = leg.b, dir = leg.dir, leg = leg, beat = beat, index = index }
    if phase < td then
        w.c, w.moving, w.speed, w.depart = leg.from, false, 0, td - phase
        w.part, w.rate, w.tau = 0, 0, 0
        return w
    end
    local tau = phase - td
    local h = halts and halts[train.id]
    local part, rate, held = nil, nil, nil
    if h and h.beat == beat and tau >= h.t0 then
        part, rate, held = T.halted(h, tau, tm)
    else
        local u = tau / tm
        part, rate = T.ease(u), T.easeRate(u) / tm
    end
    w.c = leg.from + (leg.to - leg.from) * part
    w.part, w.rate, w.tau = part, rate, tau
    if held then
        w.moving, w.speed, w.depart, w.halted = false, 0, held, true
    else
        w.moving, w.speed, w.arrive = true, leg.len * rate, cycle - phase
    end
    return w
end

--- A leg with a stop out on it. A halt is
---
---     { beat, t0, p0, v0, ps, ta, hold }
---
--- From `t0` seconds into the leg, where the train was `p0` of the way
--- along it and going `v0` of it a second, it runs on to `ps` and is
--- standing there `ta` seconds later; stands `hold` seconds; and then runs
--- the rest of the leg in what is left of `tm`, so that it reaches the
--- station when it always would have. Returns how much of the leg is done
--- `tau` seconds in, how fast (of the leg, a second), and, while it
--- stands, how many seconds it has left there.
function T.halted(h, tau, tm)
    local s = tau - h.t0
    if s < h.ta then
        -- One curve from where it was, at the speed it had, to standing
        -- at ps: no jump in place or in speed. (With ta = 2 (ps - p0) / v0
        -- it is an even braking.)
        local x, d, m = s / h.ta, h.ps - h.p0, h.v0 * h.ta
        local part = h.p0 + m * (x - 2 * x * x + x * x * x) + d * (3 * x * x - 2 * x * x * x)
        local rate = (m * (1 - 4 * x + 3 * x * x) + d * (6 * x - 6 * x * x)) / h.ta
        return part, math.max(0, rate), nil
    end
    if s < h.ta + h.hold then return h.ps, 0, h.ta + h.hold - s end
    local left = tm - h.t0 - h.ta - h.hold
    local x = (s - h.ta - h.hold) / left
    return h.ps + (1 - h.ps) * T.ease(x), (1 - h.ps) * T.easeRate(x) / left, nil
end

--- A halt for a train on leg `leg`, asked for `tau` seconds into it with
--- the train `p0` of the way along and going `v0` of it a second, to stand
--- at `ps`. Nil, and how fast it would have to go, where there is not the
--- time left to stand `hold` seconds and still be at the station when the
--- timetable says, at no more than `fastest`.
function T.halt(leg, beat, tau, p0, v0, ps, ta, hold, tm, fastest)
    local left = tm - tau - ta - hold
    if left <= 1 then return nil, nil end
    local peak = C.EasePeak * (1 - ps) * leg.len / left
    if peak > fastest then return nil, peak end
    return { beat = beat, t0 = tau, p0 = p0, v0 = v0, ps = ps, ta = ta, hold = hold }, peak
end

--- The place on a route nearest a point: how far along it, and how far
--- from the point. Every segment is looked at: for a request, not a frame.
function T.nearest(route, x, y)
    T.measure(route)
    local best, bestD = nil, nil
    for _, seg in ipairs(route.segs) do
        local a = U.clamp((x - seg.x) * seg.ux + (y - seg.y) * seg.uy, 0, seg.len)
        local dx, dy = seg.x + seg.ux * a - x, seg.y + seg.uy * a - y
        local far = dx * dx + dy * dy
        if not bestD or far < bestD then best, bestD = seg.d + a, far end
    end
    if not best then return nil end
    return best, math.sqrt(bestD)
end

--- Which leg of a route a distance along it is on, going which way, and
--- how much of that leg is done there: the legs (a line has two for every
--- stretch, out and back), each { index, part }.
function T.legsAt(route, d)
    local out = {}
    for i, leg in ipairs(T.legs(route)) do
        for _, dd in ipairs(route.closed and { d, d + route.len } or { d }) do
            local part = (dd - leg.from) / (leg.to - leg.from)
            if part > 0 and part < 1 then out[#out + 1] = { index = i, part = part } end
        end
    end
    return out
end

--- How long until a train next stands at stop number `stop` of its route,
--- in seconds from clock `t`; and true if it is standing there now, when
--- the number is how long until it leaves. Nil if it never calls there.
function T.due(route, train, t, tm, td, stop)
    local legs = T.legs(route)
    local cycle = td + tm
    local beat = math.floor(t / cycle)
    local phase = t - beat * cycle
    local offset = train.offset or 0
    if phase < td and legs[U.mod(beat + offset, #legs) + 1].a == stop then return td - phase, true end
    for k = 0, #legs do
        if legs[U.mod(beat + k + offset, #legs) + 1].b == stop then return (k + 1) * cycle - phase, false end
    end
    return nil
end

--- How far through a leg's time a train is when it is `part` of the way
--- along it: T.ease, backwards, found by halving.
function T.unease(part)
    if part <= 0 then return 0 end
    if part >= 1 then return 1 end
    local lo, hi = 0, 1
    for _ = 1, 40 do
        local mid = (lo + hi) / 2
        if T.ease(mid) < part then lo = mid else hi = mid end
    end
    return (lo + hi) / 2
end

--- When a train next comes to somebody beside its track, `d` along its
--- route: { secs, stop, here, index, part }.
---
---   * within `clear` of a leg's end she is at a station, and the train is
---     met there: `stop` is its number, `secs` is TRN.Time.due's, and `here`
---     is true while it stands there (when `secs` is how long until it
---     leaves);
---   * out between two stations `secs` is how long until its middle is
---     level with her, on leg `index`, `part` of the way along it. If it has
---     been asked to stand there (`halts`), that is when it will be standing,
---     and while it stands `here` is true and `secs` is how long it has left.
---
--- The soonest of them, where a line passes her both ways. Nil for a train
--- that never comes by.
function T.meet(route, train, t, tm, td, d, clear, halts)
    local legs = T.legs(route)
    local n, cycle = #legs, td + tm
    local beat = math.floor(t / cycle)
    local offset = train.offset or 0
    local best = nil
    local function take(m)
        if m.secs and (not best or m.secs < best.secs) then best = m end
    end
    for _, hit in ipairs(T.legsAt(route, d)) do
        local leg = legs[hit.index]
        if hit.part <= clear or hit.part >= 1 - clear then
            local stop = (hit.part <= clear) and leg.a or leg.b
            local secs, here = T.due(route, train, t, tm, td, stop)
            take({ secs = secs, stop = stop, here = here == true })
        else
            -- The first beat from this one on which it runs this leg.
            local k = U.mod(hit.index - 1 - beat - offset, n)
            local start = (beat + k) * cycle + td - t
            local when = start + tm * T.unease(hit.part)
            local h = halts and halts[train.id]
            local here = false
            if h and h.beat == beat + k and math.abs(h.ps - hit.part) < 0.005 then
                when = start + h.t0 + h.ta
                if when <= 0 and when + h.hold > 0 then when, here = when + h.hold, true end
            end
            if when <= 0 then when = when + n * cycle end
            take({ secs = when, here = here, index = hit.index, part = hit.part })
        end
    end
    if not best then
        -- On no leg: at a stop to the square, or past the last stop of a line.
        local stop, far = nil, nil
        for i, s in ipairs(route.stops) do
            local gap = math.abs(s.d - d)
            if not far or gap < far then stop, far = i, gap end
        end
        local secs, here = nil, nil
        if stop then secs, here = T.due(route, train, t, tm, td, stop) end
        if secs then best = { secs = secs, stop = stop, here = here == true } end
    end
    return best
end

--- The clock value of the next moment anything changes: the next departure
--- or arrival. (Every train's, at once: that is the beat.)
function T.nextChange(t, tm, td)
    local cycle = td + tm
    local beat = math.floor(t / cycle)
    local phase = t - beat * cycle
    if phase < td then return beat * cycle + td end
    return (beat + 1) * cycle
end

---------------------------------------------------------------------------
-- A train's cars and decks
---------------------------------------------------------------------------
local layouts = {}

-- The consists rolled for a world's trains, by name (T.roll).
T.rolled = {}

--- The next number of a sequence that looks random and is the same on every
--- machine: Park and Miller's, in whole numbers a double holds exactly and
--- with TRN.Util.mod, never the % operator (tests/test_kahlua.py).
function T.rand(x)
    return U.mod(x * 16807, 2147483647)
end

--- The cars of train number `n` of a world whose seed is `seed`, front
--- first (C.Roll): { { kind = }, ... }. The same answer for the same two
--- numbers, for ever: a train's cars are its rooms, and what is in them.
---
--- `empties` more empty boxcars are coupled on behind all of that, before
--- the rear locomotive (the author, 2026-10-11: "more default empty
--- buildable cars"; the sandbox's Empties). **They move nothing.** A car's
--- room is found by its `slot` (T.slotOf), which is its place in the train
--- unless it says otherwise: the rear locomotive keeps the slot it had when
--- there were none, and each empty has the next after it. So every car a
--- train had before 0.29.0 has the room it had, and so does every car when
--- a host has more empties or fewer.
function T.roll(seed, n, length, empties)
    local L = C.Roll.lengths[length or 1] or C.Roll.lengths[1]
    local x = U.mod(math.floor(seed) * 31 + n * 7919, 2147483646) + 1
    for _ = 1, 4 do x = T.rand(x) end
    local function pick(count)
        x = T.rand(x)
        return math.min(count, math.floor(x / 2147483647 * count) + 1)
    end
    local have, cars = {}, {}
    local function add(kind)
        if have[kind] then return false end
        have[kind] = true
        cars[#cars + 1] = { kind = kind }
        return true
    end
    for _, want in ipairs(C.Roll.always) do
        if type(want) == "table" then add(want[pick(#want)]) else add(want) end
    end
    -- The passenger cars: a few, of whatever quality comes up, and two of a kind is two coaches.
    local seats = C.Roll.seats
    for _ = 1, L.seats[1] + pick(L.seats[2] - L.seats[1] + 1) - 1 do
        cars[#cars + 1] = { kind = seats.kinds[pick(#seats.kinds)] }
    end
    local extra = L.extra[1] + pick(L.extra[2] - L.extra[1] + 1) - 1
    local tries = 0
    while extra > 0 and tries < 200 do
        tries = tries + 1
        if add(C.Roll.pool[pick(#C.Roll.pool)]) then extra = extra - 1 end
    end
    -- Shuffled, so that the cars somebody needs are not always the first five.
    for i = #cars, 2, -1 do
        local j = pick(i)
        cars[i], cars[j] = cars[j], cars[i]
    end
    local out = { { kind = "loco" } }
    for _, car in ipairs(cars) do out[#out + 1] = car end
    local rear = #out + 1          -- the rear locomotive's place in a train with no empties: its room's, for ever
    for k = 1, math.max(0, math.floor(empties or 0)) do
        out[#out + 1] = { kind = C.Roll.empty, slot = rear + k }
    end
    out[#out + 1] = { kind = "loco", flip = true, slot = rear }
    return T.wear(out, seed, n)
end

--- Which outside each car of a train wears: a number from 0 to 1 a car,
--- from dice of their own, so that what a train's cars are is what it
--- always was whatever is done to the outsides. A locomotive at each end
--- is a pair.
function T.wear(out, seed, n)
    local y = U.mod(math.floor(seed) * 17 + n * 104729, 2147483646) + 1
    for _ = 1, 3 do y = T.rand(y) end
    for _, car in ipairs(out) do
        y = T.rand(y)
        car.skin = y / 2147483647
    end
    if #out > 1 and out[#out].kind == out[1].kind then out[#out].skin = out[1].skin end
    return out
end

--- Which room of its train's a car has (TRN_Rooms.room), for the car in
--- place `car` of a consist: its place, unless the consist says otherwise.
function T.slotOf(name, car)
    local c = T.layout(name).cars[car]
    return c and c.slot or nil
end

--- A consist laid out along the train's own axis: each car's middle and each
--- deck's, as a distance from the train's middle. Car 1 is at the +end.
function T.layout(name)
    if layouts[name] then return layouts[name] end
    local consist = C.Consists[name] or T.rolled[name]
    local total = 0
    for i, car in ipairs(consist) do
        total = total + C.Cars[car.kind].len
        if i < #consist then total = total + C.Gap end
    end
    local out = { cars = {}, decks = {}, len = total }
    local pos = total / 2
    -- The train of every car there is wears its outsides in turn: each car
    -- the next of those its kind may wear, counted across the kinds that
    -- share a list, so that its eight boxcars are the eight boxcars, written
    -- on and clean (PLAYED 2026-10-10: "I don't see any graffiti anymore",
    -- on a test train that wore each kind's first). Its locomotives are a
    -- pair, in the first of theirs; and a kind there is one car of, with a
    -- list no other kind shares (the tank, the gondola), shows its first.
    local turn = {}
    for i, car in ipairs(consist) do
        local kind = C.Cars[car.kind]
        local len = kind.len
        local skin = car.skin
        if skin == nil and name == C.Dev.wearAll and kind.skins and #kind.skins > 1 and not kind.plow then
            local n = turn[kind.skins[1]] or 0
            turn[kind.skins[1]] = n + 1
            skin = (U.mod(n, #kind.skins) + 0.5) / #kind.skins
        end
        out.cars[i] = { kind = car.kind, flip = car.flip == true, rel = pos - len / 2, len = len, skin = skin,
                        slot = car.slot or i }
        pos = pos - len
        if i < #consist then
            out.decks[i] = { rel = pos - C.Gap / 2 }
            pos = pos - C.Gap
        end
    end
    layouts[name] = out
    return out
end

--- The turn to hand the engine for a car on track running ux, uy: degrees,
--- 0 or more and under 360. (A negative one sends the item down the
--- engine's flat-picture path: pz-heros POWERS.md 3.5.)
function T.yaw(ux, uy, flip)
    local deg = U.angle(ux, uy) * 180 / math.pi * C.YawSign + C.YawOffset
    if flip then deg = deg + 180 end
    return U.mod(deg, 360)
end

--- A point given along (a) and across (b) the track at px, py, in the world.
function T.toWorld(px, py, ux, uy, a, b)
    return px + a * ux - b * uy, py + a * uy + b * ux
end

--- And a point in the world, along and across.
function T.toLocal(px, py, ux, uy, x, y)
    local dx, dy = x - px, y - py
    return dx * ux + dy * uy, dy * ux - dx * uy
end

--- True when x, y is within halfLen along and halfWid across of a piece of
--- train at px, py on track running ux, uy. Also returns along and across.
function T.inside(px, py, ux, uy, halfLen, halfWid, x, y)
    local a, b = T.toLocal(px, py, ux, uy, x, y)
    return (a >= -halfLen and a <= halfLen and b >= -halfWid and b <= halfWid), a, b
end

--- A deck's place in the world: x, y, ux, uy.
function T.deckAt(route, train, w, index)
    local deck = T.layout(train.consist).decks[index]
    if not deck then return nil end
    -- It hangs between the ends of the two cars it joins.
    return T.pose(route, w.c + deck.rel, C.Gap / 2)
end

--- Where a rider standing `a` along and `b` across deck `index` is, held
--- inside the deck's edge. Returns x, y, and a and b as held.
function T.riderAt(route, train, w, index, a, b)
    local px, py, ux, uy = T.deckAt(route, train, w, index)
    if not px then return nil end
    a = U.clamp(a, -C.Deck.halfLen, C.Deck.halfLen)
    b = U.clamp(b, -C.Deck.halfWid, C.Deck.halfWid)
    local x, y = T.toWorld(px, py, ux, uy, a, b)
    return x, y, a, b
end

--- What a rider stands on, and where it is: a deck (r.deck) or the top of
--- a car (r.top, the car's number). x, y, ux, uy, then half its length and
--- half its width as there is room to stand, and how high it is in levels.
function T.perch(route, train, w, r)
    if r.top then
        local car = T.layout(train.consist).cars[r.top]
        if not car then return nil end
        local kind = C.Cars[car.kind]
        local px, py, ux, uy = T.carAt(route, w.c, car)
        return px, py, ux, uy, kind.topLen, kind.topWid, kind.top
    end
    local px, py, ux, uy = T.deckAt(route, train, w, r.deck)
    if not px then return nil end
    return px, py, ux, uy, C.Deck.halfLen, C.Deck.halfWid, 0
end

--- Where a rider standing `a` along and `b` across her perch is, held
--- inside its edge: x, y, a and b as held, and the height.
function T.riderOn(route, train, w, r, a, b)
    local px, py, ux, uy, halfLen, halfWid, h = T.perch(route, train, w, r)
    if not px then return nil end
    a = U.clamp(a, -halfLen, halfLen)
    b = U.clamp(b, -halfWid, halfWid)
    local x, y = T.toWorld(px, py, ux, uy, a, b)
    return x, y, a, b, h
end

--- The killing ground in front of the leading plow: x, y, ux, uy, halfLen.
--- Nil while the train is parked.
function T.plowAt(route, train, w)
    if not w.moving then return nil end
    local total = T.layout(train.consist).len
    local half = C.Plow.ahead / 2
    local px, py, ux, uy = T.at(route, w.c + w.dir * (total / 2 + half))
    return px, py, ux, uy, half
end

---------------------------------------------------------------------------
-- The routes there are
---------------------------------------------------------------------------
--- The dev test line as a route, from the few numbers the server keeps:
--- where it starts, which way it runs, and its length.
function T.devRoute(line)
    if line.bend then return T.bendRoute(line) end
    local ux, uy = 1, 0
    if line.axis == "y" then ux, uy = 0, 1 end
    local len, inset = line.len, line.inset
    return {
        id = "dev", z = line.z, closed = false,
        pts = { { line.x, line.y }, { line.x + ux * len, line.y + uy * len } },
        stops = {
            { d = inset, key = "IGUI_TRN_StopFirst" },
            { d = len / 2, key = "IGUI_TRN_StopMiddle" },
            { d = len - inset, key = "IGUI_TRN_StopLast" },
        },
        trains = { { id = "dev1", consist = line.consist or "dev", offset = 0, room = 0 } },
    }
end

--- The test line with a bend in it: east from line.x, line.y, a quarter
--- turn to the right, and south. The middle stop is on the first straight,
--- its own inset short of where the turn begins, so that a train leaving it
--- goes straight into the bend.
function T.bendRoute(line)
    local D = C.Dev
    local a, r, b = line.before or D.bendBefore, D.bendRadius, line.after or D.bendAfter
    local pts = { { line.x, line.y }, { line.x + a, line.y } }
    -- The turn's centre is r south of where it begins.
    local cx, cy = line.x + a, line.y + r
    for i = 1, D.bendSteps do
        local t = (math.pi / 2) * i / D.bendSteps
        pts[#pts + 1] = { cx + r * math.sin(t), cy - r * math.cos(t) }
    end
    pts[#pts + 1] = { cx + r, cy + b }
    local route = {
        id = "dev", z = line.z, closed = false, pts = pts,
        trains = { { id = "dev1", consist = line.consist or "dev", offset = 0, room = 0 } },
    }
    T.measure(route)
    route.stops = {
        { d = line.inset, key = "IGUI_TRN_StopFirst" },
        { d = a - line.inset, key = "IGUI_TRN_StopMiddle" },
        { d = route.len - line.inset, key = "IGUI_TRN_StopLast" },
    }
    return route
end

local cache = { rev = nil, routes = {} }

--- Every route in a state (the server's, or a client's mirror of it).
--- Built once for each revision of the state.
function T.routes(state)
    if not state then return {} end
    -- And once for each thing a host changes in the sandbox (TRN_Setup).
    local stamp = TRN.Setup.stamp()
    if cache.rev == state.rev and cache.state == state and cache.stamp == stamp then return cache.routes end
    local routes = {}
    if state.line then
        routes[#routes + 1] = T.devRoute(state.line)
    elseif C.Network and TRN.Routes and type(state.seed) == "number" then
        routes = T.network(state.seed, state.lines)
    end
    cache.rev, cache.state, cache.routes, cache.stamp = state.rev, state, routes, stamp
    return routes
end

--- The map's own routes (TRN_Routes.lua) with their trains, for a world
--- whose seed is `seed`. Each train's cars are rolled from the seed and
--- the train's number; `room` is which cell its cars' insides stand in
--- (TRN_Rooms: 0 is the test line's train's), and never changes.
---
--- **A train has a number, and the number is the train**: its cars are
--- rolled from it, its rooms are in the cell of that number, its name is
--- the name of that number and its id ends in its place on its line. A
--- line was made for so many trains (`slots`) and has those numbers
--- whatever a host sets: fewer trains is some of them missing, never the
--- rest renumbered. So somebody's home is still her home.
---
--- What a host sets (TRN_Setup, SERVERS.md): which of the map's lines run;
--- whether they call at the halts between towns; how many trains; what a
--- train is made of; what it is called. And `lines`: the lines an admin has
--- laid, saved with the world.
function T.network(seed, lines)
    local Su = TRN.Setup
    local routes, base = {}, 0
    local every, own, length, empties = Su.every(), Su.consist(), Su.length(), Su.empties()
    local function man(route, slots, label)
        local n = #route.stops
        -- Where each train starts, in stops round from the first: on a loop,
        -- one to every `every` stops; on a line run out and back, two half a
        -- round apart, which never stand at one stop where its stops are
        -- even in number, and one where they are not.
        local places = { 0 }
        if route.closed and every then
            places = {}
            for at = 0, n - 1, every do places[#places + 1] = at end
        elseif not route.closed and every and U.mod(n, 2) == 0 then
            places = { 0, n - 1 }
        end
        for k, at in ipairs(places) do
            local slot = route.closed and (at + 1) or k
            if slot <= slots then
                local number = base + slot
                local name
                if own then
                    name = "own:" .. string.lower(Su.text("Consist")) .. ":" .. tostring(seed) .. ":" .. number
                    if not T.rolled[name] then
                        local cars = {}
                        for i, car in ipairs(own) do cars[i] = { kind = car.kind, flip = car.flip } end
                        T.rolled[name] = T.wear(cars, seed, number)
                    end
                else
                    name = "roll:" .. tostring(seed) .. ":" .. number .. (length > 1 and (":" .. length) or "")
                           .. (empties > 0 and ("+" .. empties) or "")
                    if not T.rolled[name] then T.rolled[name] = T.roll(seed, number, length, empties) end
                end
                route.trains[#route.trains + 1] = { id = route.id .. slot, consist = name, offset = at, room = number,
                                                    name = Su.name(number, label and (label .. " " .. slot) or nil) }
            end
        end
    end
    for _, def in ipairs(TRN.Routes) do
        if Su.runs(def.id) then
            local stops = {}
            for _, stop in ipairs(def.stops) do
                if Su.calls(stop) then stops[#stops + 1] = stop end
            end
            if #stops >= 2 then
                local route = { id = def.id, z = def.z or 0, closed = def.closed == true, pts = def.pts, stops = stops,
                                trains = {} }
                man(route, def.trains, nil)
                routes[#routes + 1] = route
            end
        end
        base = base + def.trains
    end
    -- The host's own lines, after the map's: each keeps the block of numbers
    -- it was given when it was laid (`room0`), whatever is laid or taken up
    -- after it.
    local mapped = base
    for _, line in ipairs(lines or {}) do
        local route = { id = line.id, z = line.z or 0, closed = line.closed == true, pts = line.pts, stops = line.stops,
                        trains = {}, own = true, label = line.name }
        base = mapped + (line.room0 or 0)
        man(route, line.slots or 0, line.name)
        routes[#routes + 1] = route
    end
    return routes
end

--- How many trains the map's own lines were made for: a host's lines are
--- numbered after them.
function T.mapped()
    local n = 0
    for _, def in ipairs(TRN.Routes or {}) do n = n + def.trains end
    return n
end

--- Forgets the routes built from a state, for when one is replaced whole.
function T.forget()
    cache.rev, cache.state, cache.routes, cache.stamp = nil, nil, {}, nil
end

--- A route and one of its trains, by the train's id.
function T.find(routes, trainId)
    for _, route in ipairs(routes) do
        for _, train in ipairs(route.trains) do
            if train.id == trainId then return route, train end
        end
    end
    return nil, nil
end

return T
