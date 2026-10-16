if isServer() then return end

--[[ Trains -- this machine's player.

    Runs in single player and on any client; never on a server. It says
    hello when a character appears, keeps what the server answers (a client
    of a server: its mirror of the state and the clock), and hands each
    reply to the file whose business it is.

    Asking changes nothing here: the request goes to the server and
    everything that follows comes back from it.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Rooms"

TRN = TRN or {}
local C, U, Net, T, K = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock

local CL = {}
TRN.Client = CL

CL.answered = false     -- the server has answered this character's hello
CL.helloMs = 0

--- The local character with this username, or the first one.
function CL.player(who)
    for i = 0, 3 do
        local p = U.try("client.local", function() return getSpecificPlayer(i) end)
        if p and (who == nil or U.username(p) == who) then return p end
    end
    return nil
end

function CL.hello()
    local p = CL.player()
    if not p then return end
    CL.helloMs = U.nowMs()
    Net.send(p, "hello", {})
end

---------------------------------------------------------------------------
-- Replies
---------------------------------------------------------------------------
Net.onClient("state", function(args)
    K.take(args)
    CL.answered = true
    if TRN.Body then TRN.Body.changed() end
    if TRN.Admin then TRN.Admin.changed() end
    local D = TRN.Deck
    if not D then return end
    -- A whole state names a rider only in answer to a hello. Anybody riding
    -- a train that is no longer there is let go.
    if args.train and args.who then
        local p = CL.player(args.who)
        if p and args.car then
            if TRN.Inside then TRN.Inside.enter(p, args.train, args.car, nil) end
        elseif p then
            D.board(p, args.train, args.deck, args.top)
        end
    else
        D.check()
    end
end)

Net.onClient("entered", function(args)
    local p = CL.player(args.who)
    if not p or not TRN.Inside then return end
    if TRN.Deck then TRN.Deck.release(p) end
    TRN.Inside.enter(p, args.train, args.car, args.door)
end)

Net.onClient("roomReady", function(args)
    local p = CL.player(args.who)
    if p and TRN.Inside then TRN.Inside.ready(p) end
end)

Net.onClient("clock", function(args)
    K.heard(args, false)
end)

Net.onClient("boarded", function(args)
    local p = CL.player(args.who)
    if p and TRN.Inside then TRN.Inside.leave(p) end
    if p and TRN.Deck then TRN.Deck.board(p, args.train, args.deck, args.top, args.a) end
end)

Net.onClient("alighted", function(args)
    local p = CL.player(args.who)
    if p and TRN.Inside then TRN.Inside.leave(p) end
    if p and TRN.Deck then TRN.Deck.alight(p, args.x, args.y, args.z) end
end)

Net.onClient("dropped", function(args)
    local p = CL.player(args.who)
    if p and TRN.Inside then TRN.Inside.leave(p) end
    if p and TRN.Deck then TRN.Deck.drop(p) end
end)

--- Something the server says that is not a refusal.
Net.onClient("said", function(args)
    local p = CL.player(args.who)
    if not p then return end
    local function word(v) return v ~= nil and tostring(v) or nil end
    U.note(p, getText(args.key, word(args.arg), word(args.b), word(args.c), word(args.d)), 150, 220, 150)
end)

Net.onClient("refused", function(args)
    local p = CL.player(args.who)
    if not p then return end
    local text = getText(args.key or "IGUI_TRN_Refused", args.arg ~= nil and tostring(args.arg) or nil,
                         args.b ~= nil and tostring(args.b) or nil)
    U.note(p, text, 255, 120, 90)
end)

---------------------------------------------------------------------------
-- Hello, and again until answered
---------------------------------------------------------------------------
-- The order matters, and in single player it is all one call: the answer to
-- the hello comes back before sendClientCommand returns, and it may put
-- this character back on a deck. So what is left of an earlier ride is
-- cleared first, here, and never by a handler of the deck's own that would
-- run after the answer (found by the tests: a rider who saved aboard was
-- put back and then let go).
Events.OnCreatePlayer.Add(function(_, player)
    CL.answered = false
    if player and TRN.Deck then U.try("client.reset", TRN.Deck.reset, player) end
    if player and TRN.Inside then U.try("client.resetInside", TRN.Inside.reset, player) end
    U.try("client.hello", CL.hello)
end)

--- Somebody standing in the rooms' ground whom nothing has inside a car:
--- a save from a world whose line was taken up, or a state that was lost.
--- There is nothing there for them, so the server is asked for a way out.
function CL.stranded()
    local p = CL.player()
    if not p or not TRN.Inside or TRN.Inside.aboard(p) then return false end
    local x = U.try("client.x", function() return p:getX() end)
    local y = U.try("client.y", function() return p:getY() end)
    if not x or not y or not TRN.Rooms.ground(x, y) then return false end
    Net.send(p, "stranded", {})
    return true
end

Events.OnTick.Add(function()
    if U.nowMs() - CL.helloMs < 2000 then return end
    if not CL.answered then
        U.try("client.helloAgain", CL.hello)
    else
        CL.helloMs = U.nowMs()
        U.try("client.stranded", CL.stranded)
    end
end)

---------------------------------------------------------------------------
-- The console
---------------------------------------------------------------------------
--- TRN_Status() from the debug console: what this machine believes.
function TRN_Status()
    local t = K.now()
    U.log("status: version %s, clock %s, answered %s, %d route(s)", C.Version,
          t and string.format("%.1f", t) or "unknown", tostring(CL.answered), #K.routes())
    for _, route in ipairs(K.routes()) do
        for _, train in ipairs(route.trains) do
            local w = K.where(route, train)
            if w then
                local x, y = T.at(route, w.c)
                U.log("status: %s at %.1f,%.1f %s, stop %d to %d, %.0f s to go, every leg %.1f s, parked %.0f s",
                      train.id, x, y, w.moving and string.format("moving at %.1f", w.speed) or "parked",
                      w.at, w.to, w.depart or w.arrive, K.moveTime(), K.dwell())
            end
        end
    end
    -- How far this player is from each route's track: the menu's Flag and
    -- Wait are offered within C.Stop.reach of one, on its level.
    local me = CL.player()
    for _, route in ipairs(K.routes()) do
        local d, far = nil, nil
        if me then d, far = T.nearest(route, me:getX(), me:getY()) end
        if d then
            U.log("status: she is at %.1f,%.1f level %d: %.1f squares from the track of %s (level %d), %.0f along it; "
                  .. "a train is flagged within %d", me:getX(), me:getY(), math.floor(me:getZ()), far, route.id, route.z, d,
                  C.Stop.reach)
        end
    end
    if TRN.Deck then TRN.Deck.status() end
    if TRN.Inside then TRN.Inside.status() end
    if TRN.Body then TRN.Body.status() end
    if TRN.Plow then TRN.Plow.status() end
    if TRN.Map then TRN.Map.status() end
    if TRN.Trip then TRN.Trip.status() end
    if TRN.Track then TRN.Track.status() end
    if TRN.Admin then TRN.Admin.status() end
    -- The authority's own, where this machine is one (single player): a server's are in its log.
    if TRN.Build and TRN.Build.status then TRN.Build.status() end
    if TRN.Garden then TRN.Garden.status() end
    if TRN.Herd then TRN.Herd.status() end
    if TRN.Claims then
        local held = 0
        for _ in pairs(K.state and K.state.claims or {}) do held = held + 1 end
        U.log("status: claims: a player may own %d train(s); %d owned in this world, %d of them hers",
              TRN.Claims.most(), held, #TRN.Claims.owned(U.username(me)))
    end
    local Su = TRN.Setup
    U.log("status: setup: top speed %s, %s s at a stop, every leg %.0f s; fleet %s, length %s, consist '%s'; circle %s, "
          .. "louisville %s, halts %s; %d line(s) of the host's", tostring(Su.top()), tostring(Su.dwell()), K.moveTime(),
          tostring(Su.num("Fleet", 1)), tostring(Su.length()), Su.text("Consist"), tostring(Su.on("Circle")),
          tostring(Su.on("Louisville")), tostring(Su.num("Halts", 1) ~= 2), K.state and K.state.lines and #K.state.lines or 0)
end

U.log("client loaded, version %s", C.Version)

return CL
