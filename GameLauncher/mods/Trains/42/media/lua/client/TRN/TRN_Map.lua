if isServer() then return end

--[[ Trains -- the trains on the game's map, and the map from aboard (DESIGN.md 5.6).

    The author, 2026-10-09: "we can see all the trains on the map somehow
    and where they currently are (even if they are on blank map because the
    fog of war)", and "we can open the map from inside a car and see where
    we are ... based on time and schedule we auto clear fog of war along the
    train routes (so time skipping also covers it)".

    Three things, all this machine's own and none of them in the world:

      * **every train is drawn on the map**, over whatever the map shows or
        hides there: a mark where the timetable says it is now, with the
        stop it is at or bound for. The one this player is aboard is marked
        as hers;
      * **what a rider would see from the train becomes known on her map**:
        a strip either side of the track, for as far as the train has gone
        since it was last looked at. It is worked out from the timetable,
        not from where she is (inside a car she is in a room off the map),
        so a night slept aboard, or the clock sped up, uncovers the whole of
        what went by;
      * **opened from inside a car, the map is centred on the train**, not on
        the room the car's inside really is.

    The map's own calls are the ones vanilla's Lua makes: the map's drawing
    hooks in ISWorldMap (worldToUIX, worldToUIY, as its own stash-map marks
    use), and WorldMapVisited:setKnownInSquares, as reading a map does
    (ISReadABook; on a server's client the server is told too, by vanilla's
    own command, ClientCommands "map").

    **The game's own mark for the player is not moved**: from inside a car
    it is where the room is, far off the east of the map. Ours says where
    she is.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Claims"
require "TRN/TRN_Deck"
require "TRN/TRN_Inside"

TRN = TRN or {}
local C, U, T, K = TRN.Config, TRN.Util, TRN.Time, TRN.Clock

local MP = {}
TRN.Map = MP

MP.seen = {}            -- username -> { train, beat, c, to }: how far her train had got when last looked at
MP.stats = { known = 0, drawn = 0 }
MP.dueMs = 0

---------------------------------------------------------------------------
-- Aboard what
---------------------------------------------------------------------------
--- The route, the train and where it is, for a player who is aboard one:
--- on a platform, on a top or inside a car. And whether she is inside.
function MP.aboard(player)
    if not player then return nil end
    local inside = TRN.Inside and TRN.Inside.record(player) or nil
    local r = inside or (TRN.Deck and TRN.Deck.record(player)) or nil
    if not r then return nil end
    local route, train = T.find(K.routes(), r.train)
    local w = route and K.where(route, train)
    if not w then return nil end
    return route, train, w, inside ~= nil
end

---------------------------------------------------------------------------
-- What went by
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Her own train
---------------------------------------------------------------------------
--- The train this player has made hers, by its id, or nil. Kept with the
--- character (her own mod data), so it is hers on any machine and gone
--- with her: somebody who makes a home in a train can find it again.
function MP.home(player)
    return U.try("map.home", function() return player:getModData().TRN_home end)
end

function MP.setHome(player, trainId)
    U.try("map.setHome", function() player:getModData().TRN_home = trainId end)
end

--- The stretches of its route a train has covered between the last time it
--- was looked at (`seen`, or nil) and now: { { from, to }, ... } as
--- distances along the route. Across a change of leg, the rest of the old
--- one and the start of the new; across several (a night aboard), every
--- leg between, and never more than once round.
function MP.covered(route, seen, w)
    if not seen or seen.beat > w.beat then return { { w.c, w.c } } end
    if seen.beat == w.beat then return { { seen.c, w.c } } end
    local out = { { seen.c, seen.to } }
    local legs = T.legs(route)
    local between = math.min(w.beat - seen.beat - 1, #legs)
    for k = between, 1, -1 do
        local leg = legs[U.mod(w.index - 1 - k, #legs) + 1]
        out[#out + 1] = { leg.from, leg.to }
    end
    out[#out + 1] = { w.leg.from, w.c }
    return out
end

--- Makes the ground round a place known on this player's map.
local function know(player, x, y)
    local r = C.Map.see
    local x1, y1, x2, y2 = math.floor(x - r), math.floor(y - r), math.floor(x + r), math.floor(y + r)
    U.try("map.know", function() WorldMapVisited.getInstance():setKnownInSquares(x1, y1, x2, y2) end)
    if isClient() then
        U.try("map.knowServer", function()
            sendClientCommand(player, "map", "setKnownInSquares", { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        end)
    end
    MP.stats.known = MP.stats.known + 1
end

--- What her train has passed since last time becomes known on her map.
function MP.reveal(player)
    local who = U.username(player) or "?"
    local route, train, w = MP.aboard(player)
    if not route then
        MP.seen[who] = nil
        return 0
    end
    local seen = MP.seen[who]
    if seen and seen.train ~= train.id then seen = nil end
    local n = 0
    for _, span in ipairs(MP.covered(route, seen, w)) do
        local a, b = math.min(span[1], span[2]), math.max(span[1], span[2])
        local d = a
        while true do
            local x, y = T.at(route, d)
            know(player, x, y)
            n = n + 1
            if d >= b then break end
            d = math.min(b, d + C.Map.step)
        end
    end
    MP.seen[who] = { train = train.id, beat = w.beat, c = w.c, to = w.leg.to }
    return n
end

Events.OnTick.Add(function()
    local now = U.nowMs()
    if now < MP.dueMs then return end
    MP.dueMs = now + C.Map.everyMs
    local player = U.try("map.who", function() return getSpecificPlayer(0) end)
    if player then U.try("map.reveal", MP.reveal, player) end
end)

---------------------------------------------------------------------------
-- On the map
---------------------------------------------------------------------------
--- Every train, drawn on the game's map where it is now.
function MP.draw(map)
    local api = map.mapAPI
    if not api then return end
    -- A host may keep the trains off the map (sandbox OnMap): then a train is
    -- found by going to the track, or by its timetable in the menu.
    if not TRN.Setup.on("OnMap") then return end
    local player = map.character or getSpecificPlayer(0)
    local _, mine = MP.aboard(player)
    local home = MP.home(player)
    -- A train she owns is marked as hers too (TRN_Claims).
    local me = U.username(player)
    local function owner(id)
        local claim = TRN.Claims.of(id)
        return claim and claim.who or nil
    end
    -- The train she is waiting for (TRN_Trip), and what was last seen of it.
    local waited = TRN.Trip and TRN.Trip.waiting(player) or nil
    local view = waited and TRN.Trip.view(player) or nil
    local zoom = api:getZoomF()
    local M = C.Map
    for _, route in ipairs(K.routes()) do
        for _, train in ipairs(route.trains) do
            local w = K.where(route, train)
            if w then
                local x, y = T.at(route, w.c)
                local sx, sy = api:worldToUIX(x, y), api:worldToUIY(x, y)
                if sx > -40 and sy > -40 and sx < map.width + 40 and sy < map.height + 40 then
                    local own = mine ~= nil and mine.id == train.id
                    local hers = (home ~= nil and home == train.id) or (me ~= nil and owner(train.id) == me)
                    local due = waited ~= nil and waited == train.id and not own
                    local half = (own or hers or due) and M.mark + 3 or M.mark
                    map:drawRect(sx - half - 2, sy - half - 2, half * 2 + 4, half * 2 + 4, 1, 0, 0, 0)
                    if own then
                        map:drawRect(sx - half, sy - half, half * 2, half * 2, 1, 0.25, 0.95, 0.35)
                    elseif due then
                        map:drawRect(sx - half, sy - half, half * 2, half * 2, 1, 1.00, 0.55, 0.10)
                    elseif hers then
                        map:drawRect(sx - half, sy - half, half * 2, half * 2, 1, 0.30, 0.60, 1.00)
                    elseif w.moving then
                        map:drawRect(sx - half, sy - half, half * 2, half * 2, 1, 0.98, 0.80, 0.10)
                    else
                        map:drawRect(sx - half, sy - half, half * 2, half * 2, 1, 0.95, 0.95, 0.95)
                    end
                    -- Her own two are named at any zoom; the rest from a middling one.
                    local name = U.trainName(train)
                    if own then
                        map:drawText(getText("IGUI_TRN_MapHere", name), sx + half + 6, sy - 8, 0.1, 0.5, 0.15, 1, UIFont.Medium)
                    elseif due then
                        map:drawText(view and view.train == train and TRN.Trip.words(view) or name, sx + half + 6, sy - 8,
                                     0.6, 0.3, 0.0, 1, UIFont.Medium)
                    elseif hers then
                        map:drawText(getText("IGUI_TRN_MapHome", name), sx + half + 6, sy - 8, 0.1, 0.25, 0.7, 1, UIFont.Medium)
                    elseif zoom >= M.names then
                        map:drawText(name, sx + half + 6, sy - 7, 0.1, 0.1, 0.1, 1, UIFont.Small)
                    end
                    MP.stats.drawn = MP.stats.drawn + 1
                end
            end
        end
    end
end

--- Hangs the two on the game's map: after it has drawn itself, the trains;
--- and when it is opened from inside a car, the train in the middle of it.
function MP.hook()
    if MP.hooked or not ISWorldMap or not ISWorldMap.render then return end
    MP.hooked = true
    local render = ISWorldMap.render
    ISWorldMap.render = function(self)
        render(self)
        U.try("map.draw", MP.draw, self)
    end
    local show = ISWorldMap.ShowWorldMap
    if show then
        ISWorldMap.ShowWorldMap = function(playerNum, centerX, centerY, zoom)
            if not centerX then
                local at = U.try("map.centre", function()
                    local route, _, w, inside = MP.aboard(getSpecificPlayer(playerNum))
                    if not route or not inside then return nil end
                    local x, y = T.at(route, w.c)
                    return { x = x, y = y }
                end)
                if at then centerX, centerY, zoom = at.x, at.y, zoom or C.Map.zoom end
            end
            return show(playerNum, centerX, centerY, zoom)
        end
    end
    U.log("map: the trains are drawn on the game's map")
end

-- The game's map is vanilla's Lua and is there before any mod's; and again
-- when the game starts, for a build where it is not.
U.try("map.hookNow", MP.hook)
Events.OnGameStart.Add(function() U.try("map.hook", MP.hook) end)

function MP.status()
    U.log("status: the map: %d place(s) made known from aboard, %d mark(s) drawn, %s", MP.stats.known, MP.stats.drawn,
          MP.hooked and "hung on the game's map" or "NOT hung on the game's map")
end

return MP
