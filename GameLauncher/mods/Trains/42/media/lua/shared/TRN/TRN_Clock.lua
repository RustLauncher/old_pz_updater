--[[ Trains -- the clock, and the little state that goes with it (DESIGN.md 3.1).

    **The trains' clock is the world's own, counted in seconds of play at
    normal speed.** The authority (single player, or a server) adds to one
    number, `t`, kept in the world's saved mod data, as much as the world's
    clock moved each tick. So:

      * at normal speed a second is a second, as it always was;
      * **fast-forward and sleep carry the trains with them** (the author,
        2026-10-09: "speed up time moves the train to the next dest quicker
        so the arrive time lines up in world"): a train due in ten of the
        world's minutes is due in ten of them at any speed. 0.1.0 to 0.17.0
        counted real milliseconds, and a train stood nearly still while the
        world ran at forty times;
      * a pause stops every train: no tick, nothing added;
      * a save keeps it, and a load puts every train back where it was.

    How fast the world went is read off its clock, not asked of a speed
    setting: GameTime.update adds multiplier / minutesPerDay / 120 hours a
    frame (bci 469-536), and the multiplier is the frame's length times the
    speed, so `worldAgeHours * minutesPerDay * 2.5` is seconds at normal
    speed whatever sets the speed: the buttons, sleep, or a server whose
    players are all asleep.

    A client of a server keeps its own copy: it is told `t` every couple of
    seconds, works out how far its own millisecond clock is from it, and
    leans toward that a little at a time so a late message is not a jerk.
    **A time never crosses the network as a time on anybody's wall**: only
    `t`, which is the same number everywhere.

    The state is small and is sent whole only when it changes:

        { t, rev, line = { x, y, z, axis, len, inset, dwell } or nil, riders, claims }

    `riders` is the server's own and is never sent. `claims` is whose each
    train is (TRN_Claims), and is.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"

TRN = TRN or {}
local C, U, Net, T = TRN.Config, TRN.Util, TRN.Net, TRN.Time

local K = {}
TRN.Clock = K

K.state = nil           -- the authority's saved table, or a client's mirror
K.known = false         -- a client: the server has answered once
K.offset = nil          -- a client: t minus this machine's seconds
K.lastTickMs = nil      -- the authority: when it last counted
K.lastWorld = nil       -- the authority: what the world's clock said then

---------------------------------------------------------------------------
-- The sandbox's numbers, the same on every machine (TRN_Setup)
---------------------------------------------------------------------------
--- The fastest a train goes at the peak of its ease.
function K.top()
    return TRN.Setup.top()
end

--- How long every train is parked at a stop. The dev test line has its
--- own, shorter, so that a test is not mostly waiting.
function K.dwell()
    local s = K.state
    if s and s.line and s.line.dwell then return s.line.dwell end
    return TRN.Setup.dwell()
end

function K.routes()
    return T.routes(K.state)
end

--- How long every train moves for (TRN_Time.moveTime).
function K.moveTime()
    return T.moveTime(K.routes(), K.top())
end

---------------------------------------------------------------------------
-- What time it is
---------------------------------------------------------------------------
--- The trains' clock now, on this machine, or nil before it is known.
function K.now()
    local s = K.state
    if not s then return nil end
    if Net.isAuthority() then
        if not s.t then return nil end
        local lead = 0
        if K.lastTickMs then
            lead = U.clamp((U.nowMs() - K.lastTickMs) / 1000, 0, C.RenderLead)
        end
        return s.t + lead
    end
    if not K.offset then return nil end
    return K.offset + U.nowMs() / 1000
end

--- A train's whereabouts now: TRN_Time.where, or nil before the clock is
--- known.
function K.where(route, train)
    local t = K.now()
    if not t then return nil end
    return T.where(route, train, t, K.moveTime(), K.dwell(), K.state and K.state.halts)
end

---------------------------------------------------------------------------
-- The authority's half
---------------------------------------------------------------------------
--- Takes the saved state, or starts one.
function K.load()
    if not Net.isAuthority() then return end
    local s = U.try("clock.load", function() return ModData.getOrCreate(C.StateKey) end)
    if not s then
        U.warnOnce("clock.noState", "the world's mod data could not be read; trains will not be kept")
        s = {}
    end
    if type(s.t) ~= "number" then s.t = 0 end
    if type(s.rev) ~= "number" then s.rev = 0 end
    if type(s.riders) ~= "table" then s.riders = {} end
    -- What this world's trains are rolled from: once, and kept.
    if type(s.seed) ~= "number" then
        s.seed = U.try("clock.seed", function() return ZombRand(1, 2000000000) end)
        if type(s.seed) ~= "number" then s.seed = U.mod(U.nowMs(), 2000000000) + 1 end
    end
    K.state = s
    K.known = true
    K.lastTickMs = nil
    K.lastWorld = nil
    T.forget()
    U.log("clock: loaded at %.1f s, revision %d, %s", s.t, s.rev, s.line and "a test line laid" or "no line")
end

--- The world's clock, as seconds of play at normal speed. Nil where it
--- cannot be read.
function K.world()
    local v = U.try("clock.world", function()
        local g = getGameTime()
        return g:getWorldAgeHours() * g:getMinutesPerDay() * 2.5
    end)
    if type(v) ~= "number" or v ~= v then return nil end
    return v
end

--- One tick: as much as the world's clock moved since the last one, added.
--- A hitch is not a jump: a tick longer than C.TickCapMs of real time
--- counts for that much of itself. And never backwards, nor further than
--- the fastest the game runs: a clock that is set by hand (a debug menu, a
--- server's command) does not throw a train across the map.
function K.tick()
    local s = K.state
    if not s or not Net.isAuthority() then return end
    local now = U.nowMs()
    local world = K.world()
    if K.lastTickMs then
        local real = now - K.lastTickMs
        local kept = U.clamp(real, 0, C.TickCapMs)
        local add = kept / 1000
        if world and K.lastWorld then
            add = world - K.lastWorld
            if real > kept then add = add * kept / real end
            add = U.clamp(add, 0, kept / 1000 * C.FastMost)
        end
        s.t = s.t + add
    end
    K.lastTickMs = now
    K.lastWorld = world
end

--- The state as it is sent: never the riders.
function K.snapshot()
    local s = K.state
    return { t = s.t, rev = s.rev, line = s.line, seed = s.seed, halts = s.halts, lines = s.lines, claims = s.claims }
end

--- The state changed in a way the routes are built from.
function K.changed()
    K.state.rev = K.state.rev + 1
    T.forget()
end

---------------------------------------------------------------------------
-- A client's half
---------------------------------------------------------------------------
--- The server sent its state whole.
function K.take(args)
    if Net.isAuthority() then return end
    K.state = { rev = args.rev, line = args.line, seed = args.seed, halts = args.halts, lines = args.lines,
                claims = args.claims }
    K.known = true
    T.forget()
    K.heard(args, true)
end

--- The server said what time it is.
function K.heard(args, whole)
    if Net.isAuthority() then return end
    if type(args.t) ~= "number" then return end
    local want = args.t - U.nowMs() / 1000
    if whole or not K.offset or math.abs(want - K.offset) > C.SyncSnap then
        K.offset = want
    else
        K.offset = K.offset + (want - K.offset) * C.SyncBlend
    end
end

return K
