if isClient() then return end

--[[ Trains -- laying the sidings (DESIGN.md 4.3).

    Runs in single player and on any server. Vanilla stands cars of its own
    on its track, and where they stand on a route the route goes round them
    (tools/gen_rails.py, TRN_Sidings.lua). The route is arithmetic and needs
    nothing on the ground. **This file is the ground**: the new track a
    train is then seen to run on, laid in vanilla's own track tiles, and
    what stood in a train's way taken off it.

      * **Round players only.** Nothing can be laid into ground that has not
        streamed in (pz_trekship DESIGN.md, constraint 1). A siding is cut
        into stretches of C.Track.stretch rows, and a stretch is laid when
        somebody is near its siding and every square of it is there. One stretch a
        pass: a siding is hundreds of squares (pz_sewars DEV_GUIDE.md,
        *Slice any search that touches thousands of squares*).
      * **Once.** A stretch that has been laid is written down in the saved
        state, by siding and number, and not looked at again: a rail a
        player pulls up for its metal stays up (DESIGN.md 4.2, *The track
        tiles are scenery*). The list is as long as the sidings are and
        never grows.
      * **A rail is an object with a rail's sprite**, tagged as ours and
        sent (TRN_Build's own `place`). Vanilla's rails are
        `RenderLayer=Floor`, which is what puts a placed object in the floor
        pass (pz_sewars DEV_GUIDE.md, *A tile of ours has no depth*).
      * **What is taken away is named.** The generator read the map and
        listed every fence, tree and bin on the squares a train's body will
        pass: those sprites on those squares, and nothing else of the map's.
        And whatever the engine has grown on a square a rail goes on, since
        the map was drawn: never the ground itself.

    UNMEASURED, all of it: nothing here has been seen in the game.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Clock"
require "TRN/TRN_Setup"
require "TRN/TRN_Sidings"
require "TRN/TRN_Build"

TRN = TRN or {}
local C, U, K, B = TRN.Config, TRN.Util, TRN.Clock, TRN.Build

local Tk = {}
TRN.Track = Tk

Tk.stats = { stretches = 0, laid = 0, cleared = 0, grown = 0, waits = 0 }

---------------------------------------------------------------------------
-- What a siding is, row by row
---------------------------------------------------------------------------
local plans = nil

--- Every siding as rows: plans[i] = { id, x0, x1, y0, y1, rows = { [y] =
--- { lay = { { x, sprite } }, clear = { { x, sprite } } } } }. Worked out
--- once: the data is the same for the life of the process.
function Tk.plans()
    if plans then return plans end
    plans = {}
    local data = TRN.Sidings or {}
    for _, s in ipairs(data.list or {}) do
        local p = { id = s.id, rows = {}, x0 = s.x, x1 = s.x, y0 = s.y0, y1 = s.y1 }
        local function row(y)
            if not p.rows[y] then p.rows[y] = { lay = {}, clear = {} } end
            if y < p.y0 then p.y0 = y end
            if y > p.y1 then p.y1 = y end
            return p.rows[y]
        end
        local function wide(x)
            if x < p.x0 then p.x0 = x end
            if x > p.x1 then p.x1 = x end
        end
        for y = s.y0, s.y1 do
            local r = row(y)
            for k, sprite in ipairs(data.rails) do
                r.lay[#r.lay + 1] = { s.x + k - 1, sprite }
                wide(s.x + k - 1)
            end
        end
        for _, t in ipairs(s.curves or {}) do
            local r = row(t[2])
            r.lay[#r.lay + 1] = { t[1], t[3] }
            wide(t[1])
        end
        for _, t in ipairs(s.clear or {}) do
            local r = row(t[2])
            r.clear[#r.clear + 1] = { t[1], t[3] }
            wide(t[1])
        end
        plans[#plans + 1] = p
    end
    return plans
end

--- How many stretches a siding is cut into.
function Tk.count(p)
    return math.floor((p.y1 - p.y0) / C.Track.stretch) + 1
end

local function key(p, n)
    return p.id .. ":" .. n
end

--- True when a stretch has been laid by this revision.
function Tk.done(p, n)
    local t = K.state and K.state.track
    return t ~= nil and t[key(p, n)] == C.Track.rev
end

---------------------------------------------------------------------------
-- Laying
---------------------------------------------------------------------------
--- True when every square of a stretch that something is done to is there.
local function there(p, n)
    local z = C.Track.z
    local ya = p.y0 + (n - 1) * C.Track.stretch
    for y = ya, math.min(ya + C.Track.stretch - 1, p.y1) do
        local r = p.rows[y]
        if r then
            for _, t in ipairs(r.lay) do
                if not B.there(t[1], y, z) then return false end
            end
            for _, t in ipairs(r.clear) do
                if not B.there(t[1], y, z) then return false end
            end
        end
    end
    return true
end

--- Lays one stretch: what the map has in a train's way is taken off it,
--- then what has grown where a rail goes, then the rails. Returns how many
--- rails were laid.
function Tk.lay(p, n)
    local z = C.Track.z
    local ya = p.y0 + (n - 1) * C.Track.stretch
    local laid, cleared, grown = 0, 0, 0
    for y = ya, math.min(ya + C.Track.stretch - 1, p.y1) do
        local r = p.rows[y]
        if r then
            for _, t in ipairs(r.clear) do
                cleared = cleared + B.takeSprite(t[1], y, z, t[2])
            end
            for _, t in ipairs(r.lay) do
                grown = grown + B.takeGrown(t[1], y, z)
                if B.lay(t[1], y, z, t[2], "track") then laid = laid + 1 end
            end
        end
    end
    K.state.track = K.state.track or {}
    K.state.track[key(p, n)] = C.Track.rev
    Tk.stats.stretches = Tk.stats.stretches + 1
    Tk.stats.laid = Tk.stats.laid + laid
    Tk.stats.cleared = Tk.stats.cleared + cleared
    Tk.stats.grown = Tk.stats.grown + grown
    U.log("track: the %s siding, stretch %d of %d (rows %d to %d): %d rails laid, %d of the map's things and %d grown "
          .. "ones taken out of the way", p.id, n, Tk.count(p), ya, math.min(ya + C.Track.stretch - 1, p.y1), laid,
          cleared, grown)
    return laid
end

--- Now and then: the first stretch that somebody is near, is not laid and
--- has all its ground, is laid. One a pass.
function Tk.pass()
    if not K.state then return false end
    -- A host may leave the ground as the map has it (sandbox Sidings): the
    -- trains go round vanilla's cars all the same, over bare ground.
    if not TRN.Setup.on("Sidings") then return false end
    local near = C.Track.near
    for _, player in ipairs(U.players()) do
        local px = U.try("track.x", function() return player:getX() end)
        local py = U.try("track.y", function() return player:getY() end)
        if px and py then
            for _, p in ipairs(Tk.plans()) do
                if px >= p.x0 - near and px <= p.x1 + near and py >= p.y0 - near and py <= p.y1 + near then
                    -- (Every stretch of it not yet laid is asked for: which of them
                    -- she is near enough to is decided by whether its ground is
                    -- there, and by nothing else. A second test of how far she is
                    -- was a guard no mutation could break.)
                    for n = 1, Tk.count(p) do
                        if not Tk.done(p, n) then
                            if there(p, n) then
                                Tk.lay(p, n)
                                return true
                            end
                            -- Not "nothing to lay": cannot tell yet. It is asked again.
                            Tk.stats.waits = Tk.stats.waits + 1
                        end
                    end
                end
            end
        end
    end
    return false
end

function Tk.status()
    local total, done = 0, 0
    for _, p in ipairs(Tk.plans()) do
        for n = 1, Tk.count(p) do
            total = total + 1
            if Tk.done(p, n) then done = done + 1 end
        end
    end
    U.log("status: track: %d siding(s), %d of %d stretch(es) laid in this world; since it loaded %d rails laid, %d of "
          .. "the map's things and %d grown ones cleared, %d wait(s) for ground", #Tk.plans(), done, total,
          Tk.stats.laid, Tk.stats.cleared, Tk.stats.grown, Tk.stats.waits)
end

return Tk
