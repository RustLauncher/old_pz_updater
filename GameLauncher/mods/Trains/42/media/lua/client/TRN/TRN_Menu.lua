if isServer() then return end

--[[ Trains -- the right-click (DESIGN.md 5.1).

    What is offered depends on where the player is, not on what the click
    landed on: a right-click names a square on the floor plane, and a car is
    tall, so its picture is a square or two off where it stands
    (pz_trekship DEV_GUIDE.md, "A right-click lands on the floor, not on the
    picture").

    **Every car is named by its number**, which is painted on its top and
    its ends (the author, 2026-10-08): "Enter car 3", "Climb onto car 3".
    Which way is ahead inside a room is not which way the train is going,
    and a number is the same from anywhere.

    **And the one the click was toward needs no number**: from a platform,
    a click toward one of its two cars puts that car's options first, as
    plain "Enter" and "Climb up"; from a top, "Climb down" is the end the
    click was toward. Where each of them is, is drawn in green (TRN_Body,
    B.marks). Only which side of the rider the click fell is used, never
    what it landed on.

      * **beside a train**, within reach of any part of it: *Board the
        train*, onto the nearest deck. Greyed with the reason while it moves;
      * **on a deck**, between two cars: into either, onto the top of
        either, and *Get off the train* at a stop. A car there is no way
        into (a tank, a flatcar) is greyed and says so;
      * **on top of a car**: down to the deck at either end of it;
      * **inside a car**: out to the deck at either end, always, and *Leave
        the train* by the side door, at a stop;
      * **aboard, anywhere**: *Get off at...*, each stop her train calls at
        and how long until it does. Chosen once, and she is put off there
        (TRN_Trip);
      * **on the ground by a track**: *Wait for a train*, each train of that
        track by its name and how long until it is there. She is told as it
        nears, and it is asked to stop for her (TRN_Trip);
      * **aboard a train that is nobody's**: *Claim it as your own*, where
        the host lets trains be owned (TRN_Claims). **Its owner, anywhere**:
        a menu of her train, to lock the cars she is at or all of them, to
        close it to everybody else, and to give it up. Anybody else is told
        whose it is, and a locked door and a closed train are greyed with
        the reason;
      * **the dev build**: lay the test line, take it up, skip the clock.

    An option that would be refused is greyed **with its reason**, never
    hidden; the server checks again whatever this file thinks.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Plow"
require "TRN/TRN_Claims"
require "TRN/TRN_Deck"
require "TRN/TRN_Inside"
require "TRN/TRN_Trip"

TRN = TRN or {}
local C, U, Net, T, K, D = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock, TRN.Deck
local Cl = TRN.Claims

local M = {}
TRN.Menu = M

function M.onSend(_, player, cmd, args)
    Net.send(player, cmd, args or {})
end

--- "Make this my train": kept with her character, and marked on her map.
function M.onHome(_, player, train)
    TRN.Map.setHome(player, train.id)
    U.note(player, getText("IGUI_TRN_HomeSet", U.trainName(train)), 150, 220, 150)
end

--- Where her own train is, in words, for somebody who is not aboard it:
--- when it is next due at the stop she is nearest, if it calls there and
--- she is within a walk of it; else the stop it is at or bound for.
function M.homeLine(player, homeId)
    local route, train = T.find(K.routes(), homeId)
    local w = route and K.where(route, train)
    if not w then return nil end
    local name = U.trainName(train)
    local x, y = player:getX(), player:getY()
    local best, bestD = nil, nil
    for i, stop in ipairs(route.stops) do
        local sx, sy = T.at(route, stop.d)
        local d = (sx - x) * (sx - x) + (sy - y) * (sy - y)
        if not bestD or d < bestD then best, bestD = i, d end
    end
    if best and bestD <= C.Map.afoot * C.Map.afoot then
        local secs, here = T.due(route, train, K.now(), K.moveTime(), K.dwell(), best)
        local stop = U.stopName(route.stops[best])
        if secs and here then return getText("IGUI_TRN_HomeHere", name, stop, tostring(math.ceil(secs))) end
        if secs then return getText("IGUI_TRN_HomeDue", name, stop, tostring(math.ceil(secs / 60))) end
    end
    return getText(w.moving and "IGUI_TRN_HomeBound" or "IGUI_TRN_HomeAt", name,
                   U.stopName(route.stops[w.moving and w.to or w.at]))
end

--- "Get off at N": kept with her character, and TRN_Trip puts her off there.
function M.onOff(_, player, train, stop)
    local route = T.find(K.routes(), train.id)
    TRN.Trip.setOff(player, train.id, stop)
    U.note(player, getText("IGUI_TRN_OffSet", U.stopName(route and route.stops[stop])), 150, 220, 150)
end

function M.onOffClear(_, player)
    TRN.Trip.setOff(player, nil)
    U.note(player, getText("IGUI_TRN_OffCleared"), 150, 220, 150)
end

--- "Board the N": she waits for that train, and is told where it is now.
function M.onWait(_, player, train)
    TRN.Trip.setWait(player, train.id)
    local m = TRN.Trip.look(player, train.id)
    if m then U.note(player, TRN.Trip.words(m), 150, 220, 150) end
end

function M.onWaitClear(_, player, name)
    TRN.Trip.setWait(player, nil)
    U.note(player, getText("IGUI_TRN_WaitCleared", name), 150, 220, 150)
end

--- Every train of the track this player is beside, soonest first, with how
--- long until it is where she stands: { { train, secs }, ... }. Not the one
--- she already waits for, nor one that is standing there now: that one is
--- boarded. Asked on a right-click, not a frame.
function M.waitPicks(player, waitId)
    local out = {}
    local t = K.now()
    if not t then return out end
    local x, y, z = player:getX(), player:getY(), math.floor(player:getZ())
    for _, route in ipairs(K.routes()) do
        if route.z == z then
            local d, far = T.nearest(route, x, y)
            if d and far <= C.Stop.reach then
                for _, train in ipairs(route.trains) do
                    local m = train.id ~= waitId
                              and T.meet(route, train, t, K.moveTime(), K.dwell(), d, C.Stop.clear, K.state and K.state.halts)
                    if m and not m.here then out[#out + 1] = { train = train, secs = m.secs } end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.secs < b.secs end)
    return out
end

--- The dev build: what this machine believes, into the log, for somebody
--- without the debug console (TRN_Client, TRN_Status).
function M.onStatus(_, player)
    TRN_Status()
    U.note(player, getText("IGUI_TRN_DevStatusDone"), 150, 220, 150)
end

local function grey(option, why, arg, b)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = getText(why, arg ~= nil and tostring(arg) or nil, b ~= nil and tostring(b) or nil)
end

--- For a player within reach of any part of a train: its route, the
--- train, where it is, and the number of the deck nearest them. Else nil.
function M.nearestDeck(player)
    local x, y, z = player:getX(), player:getY(), math.floor(player:getZ())
    local best, bestD = nil, nil
    for _, route in ipairs(K.routes()) do
        if route.z == z then
            for _, train in ipairs(route.trains) do
                local w = K.where(route, train)
                -- (Not a train whose middle is further off than it is long:
                -- this is asked every frame, of every train on the map.)
                local len = T.layout(train.consist).len
                if w then
                    local mx, my = T.at(route, w.c)
                    if (mx - x) * (mx - x) + (my - y) * (my - y) > len * len then w = nil end
                end
                -- Beside any part of the train, not only its decks: the
                -- first play (2026-10-08) stood by a car and was offered
                -- nothing.
                if w and TRN.Plow.within(TRN.Plow.boxes(route, train, w, C.Deck.reach), x, y) then
                    for i = 1, #T.layout(train.consist).decks do
                        local px, py = T.deckAt(route, train, w, i)
                        local dx, dy = px - x, py - y
                        local d = dx * dx + dy * dy
                        if not bestD or d < bestD then
                            best, bestD = { route = route, train = train, w = w, deck = i }, d
                        end
                    end
                end
            end
        end
    end
    return best
end

--- True when this player is beside the track of some route, near enough to
--- flag a train down (C.Stop.reach). Asked on a right-click, not a frame.
function M.byTrack(player)
    local x, y, z = player:getX(), player:getY(), math.floor(player:getZ())
    for _, route in ipairs(K.routes()) do
        if route.z == z then
            local d, far = T.nearest(route, x, y)
            if d and far <= C.Stop.reach then return true end
        end
    end
    return false
end

--- Where on the ground the click was, or nil where that cannot be told.
function M.clicked(playerNum, z)
    if not (screenToIsoX and screenToIsoY and getMouseX and getMouseY) then return nil end
    local mx, my = getMouseX(), getMouseY()
    if not (mx and my) then return nil end
    local x, y = screenToIsoX(playerNum, mx, my, z), screenToIsoY(playerNum, mx, my, z)
    if not (x and y) then return nil end
    return { x = x, y = y }
end

--- Which way along a train a click was from a point on it: 1 toward the
--- front, -1 toward the rear, nil if it cannot be told.
local function toward(click, px, py, ux, uy)
    if not (click and px) then return nil end
    return ((click.x - px) * ux + (click.y - py) * uy) >= 0 and 1 or -1
end

--- The options a deck has for one of the two cars it joins. `here` is the
--- car the click was toward: its options need no number, the green marks
--- say which car it is (the author, 2026-10-08).
local function carOptions(context, worldobjects, player, train, car, here)
    local kind = C.Cars[T.layout(train.consist).cars[car].kind]
    local into = context:addOption(here and getText("IGUI_TRN_EnterHere") or getText("IGUI_TRN_EnterCar", tostring(car)),
                                   worldobjects, M.onSend, player, "enter", { car = car })
    if not kind.inside then
        grey(into, "IGUI_TRN_RefuseNoInside", car)
    elseif Cl.locked(train.id, T.slotOf(train.consist, car)) and not Cl.free(player, train.id) then
        grey(into, "IGUI_TRN_RefuseLocked", car, Cl.of(train.id).who)
    end
    context:addOption(here and getText("IGUI_TRN_ClimbHere") or getText("IGUI_TRN_ClimbCar", tostring(car)),
                      worldobjects, M.onSend, player, "climb", { car = car })
end

--- Her own train's menu (TRN_Claims): the cars she is at, to lock or
--- unlock by their numbers; every car; closing it to everybody else; and
--- giving it up. A train of hers that is not running now can only be given
--- up.
function M.claimMenu(context, worldobjects, player, id, riding, inside)
    local _, train = T.find(K.routes(), id)
    local top = context:addOption(getText("IGUI_TRN_ClaimMenu", train and U.trainName(train) or id), worldobjects, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(top, menu)
    if train then
        local cars = T.layout(train.consist).cars
        local at = {}
        if inside and inside.train == id then at = { inside.car } end
        if riding and riding.train == id then
            at = riding.top and { riding.top } or { riding.deck, riding.deck + 1 }
        end
        for _, n in ipairs(at) do
            if cars[n] and C.Cars[cars[n].kind].inside then
                local on = not Cl.locked(id, cars[n].slot)
                menu:addOption(getText(on and "IGUI_TRN_ClaimLockCar" or "IGUI_TRN_ClaimUnlockCar", tostring(n)), worldobjects,
                               M.onSend, player, "lock", { train = id, car = n, on = on })
            end
        end
        menu:addOption(getText("IGUI_TRN_ClaimLockAll"), worldobjects, M.onSend, player, "lock", { train = id, on = true })
        if Cl.anyLocked(id) then
            menu:addOption(getText("IGUI_TRN_ClaimUnlockAll"), worldobjects, M.onSend, player, "lock", { train = id, on = false })
        end
        local shut = Cl.closed(id)
        menu:addOption(getText(shut and "IGUI_TRN_ClaimOpen" or "IGUI_TRN_ClaimClose"), worldobjects, M.onSend, player,
                       "close", { train = id, on = not shut })
    end
    menu:addOption(getText("IGUI_TRN_ClaimDrop", train and U.trainName(train) or id), worldobjects, M.onSend, player,
                   "unclaim", { train = id })
end

function M.fill(playerNum, context, worldobjects, test)
    local player = U.try("menu.player", function() return getSpecificPlayer(playerNum) end)
    if not player then return end
    local riding = D.record(player)
    local inside = TRN.Inside and TRN.Inside.record(player) or nil
    local near = (not riding and not inside) and U.try("menu.near", M.nearestDeck, player) or nil
    local homeId = TRN.Map and TRN.Map.home(player) or nil
    if homeId and not T.find(K.routes(), homeId) then homeId = nil end
    local waitId = TRN.Trip.waiting(player)
    if waitId and not T.find(K.routes(), waitId) then waitId = nil end
    local admin = TRN.Admin ~= nil and U.admin(player)
    local me = U.username(player)
    local mine = Cl.owned(me)
    if not riding and not inside and not near and not C.DevTools and not homeId and not waitId and not admin
       and #mine == 0 and not U.try("menu.byTrack", M.byTrack, player) then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    if riding and riding.top then
        -- On top of car n: deck n - 1 is at its front end, deck n at its rear.
        local route, train = T.find(K.routes(), riding.train)
        local decks = train and T.layout(train.consist).decks or {}
        local w = route and K.where(route, train)
        local side = nil
        if w then
            local px, py, ux, uy = T.perch(route, train, w, riding)
            side = toward(U.try("menu.click", M.clicked, playerNum, route.z), px, py, ux, uy)
        end
        -- The end the click was toward first, and by no number.
        local ways = { { deck = riding.top - 1, to = riding.top - 1, side = 1 }, { deck = riding.top, to = riding.top + 1, side = -1 } }
        if side == -1 then ways = { ways[2], ways[1] } end
        for _, way in ipairs(ways) do
            if decks[way.deck] then
                context:addOption(way.side == side and getText("IGUI_TRN_ClimbDownHere")
                                  or getText("IGUI_TRN_ClimbDown", tostring(way.to)), worldobjects, M.onSend, player,
                                  "descend", { deck = way.deck })
            end
        end
    elseif riding then
        local route, train = T.find(K.routes(), riding.train)
        local w = route and K.where(route, train)
        local off = context:addOption(getText("IGUI_TRN_GetOff"), worldobjects, M.onSend, player, "alight")
        if w and w.moving then grey(off, "IGUI_TRN_RefuseMovingOff", math.ceil(w.arrive)) end
        -- A deck is between two cars: each has a door onto it and a ladder up.
        if train then
            local side = nil
            if w then
                local px, py, ux, uy = T.deckAt(route, train, w, riding.deck)
                side = toward(U.try("menu.click", M.clicked, playerNum, route.z), px, py, ux, uy)
            end
            -- The car the click was toward first, and by no number.
            local ahead, behind = riding.deck, riding.deck + 1
            if side == -1 then
                carOptions(context, worldobjects, player, train, behind, true)
                carOptions(context, worldobjects, player, train, ahead, false)
            else
                carOptions(context, worldobjects, player, train, ahead, side == 1)
                carOptions(context, worldobjects, player, train, behind, false)
            end
        end
    elseif inside then
        local route, train = T.find(K.routes(), inside.train)
        local w = route and K.where(route, train)
        local cars = train and #T.layout(train.consist).cars or 0
        -- Out of car n by its front door is toward car n - 1; by its rear, n + 1.
        -- The end the click was toward is plain "Go out": a room's front is its west.
        local side = nil
        if inside.room then
            local mx, my = TRN.Rooms.spot(inside.room, nil)
            side = toward(U.try("menu.click", M.clicked, playerNum, inside.room.z), mx, my, -1, 0)
        end
        local function frontDoor()
            local front = context:addOption((side == 1 and inside.car > 1) and getText("IGUI_TRN_OutHere")
                                            or getText(inside.car > 1 and "IGUI_TRN_OutToward" or "IGUI_TRN_OutFront",
                                                       tostring(inside.car - 1)), worldobjects, M.onSend, player,
                                            "exitTo", { door = "front" })
            if inside.car <= 1 then grey(front, "IGUI_TRN_RefuseEnd") end
        end
        local function rearDoor()
            local rear = context:addOption((side == -1 and inside.car < cars) and getText("IGUI_TRN_OutHere")
                                           or getText(inside.car < cars and "IGUI_TRN_OutToward" or "IGUI_TRN_OutRear",
                                                      tostring(inside.car + 1)), worldobjects, M.onSend, player,
                                           "exitTo", { door = "rear" })
            if inside.car >= cars then grey(rear, "IGUI_TRN_RefuseEnd") end
        end
        if side == -1 then rearDoor(); frontDoor() else frontDoor(); rearDoor() end
        local off = context:addOption(getText("IGUI_TRN_LeaveCar"), worldobjects, M.onSend, player, "leave")
        if w and w.moving then grey(off, "IGUI_TRN_RefuseMovingOff", math.ceil(w.arrive)) end
    elseif near then
        local on = context:addOption(near.train.name and getText("IGUI_TRN_BoardNamed", near.train.name)
                                     or getText("IGUI_TRN_Board"), worldobjects, M.onSend, player, "board",
                                     { train = near.train.id, deck = near.deck })
        if near.w.moving then
            grey(on, "IGUI_TRN_RefuseMoving", math.ceil(near.w.arrive))
        elseif Cl.closed(near.train.id) and not Cl.free(player, near.train.id) then
            grey(on, "IGUI_TRN_RefuseClosed", U.trainName(near.train), Cl.of(near.train.id).who)
        end
    end

    -- Aboard, anywhere: the cord, after the ways out, which a click picks
    -- between. Greyed while the train is standing.
    if riding or inside then
        local route, train = T.find(K.routes(), (riding or inside).train)
        local w = route and K.where(route, train)
        if TRN.Setup.on("Cord") then
            local pull = context:addOption(getText("IGUI_TRN_PullStop"), worldobjects, M.onSend, player, "pull")
            if not w or not w.moving then grey(pull, "IGUI_TRN_RefuseStanding") end
        end
        -- Where she gets off: said once, and she is put off there. What she has said
        -- already, the way to unsay it, and every stop the train calls at, soonest first.
        if train and K.now() then
            local plan = TRN.Trip.off(player)
            if plan and plan.train == train.id and route.stops[plan.stop] then
                local secs = T.due(route, train, K.now(), K.moveTime(), K.dwell(), plan.stop)
                context:addOption(getText("IGUI_TRN_OffIs", U.stopName(route.stops[plan.stop]), TRN.Trip.span(secs or 0)),
                                  worldobjects, nil).notAvailable = true
                context:addOption(getText("IGUI_TRN_OffClear"), worldobjects, M.onOffClear, player)
            end
            local calls = TRN.Trip.calls(route, train)
            if #calls > 0 then
                local at = context:addOption(getText("IGUI_TRN_OffMenu"), worldobjects, nil)
                local sub = ISContextMenu:getNew(context)
                context:addSubMenu(at, sub)
                for _, call in ipairs(calls) do
                    sub:addOption(getText("IGUI_TRN_OffPick", U.stopName(route.stops[call.stop]), TRN.Trip.span(call.secs)),
                                  worldobjects, M.onOff, player, train, call.stop)
                end
            end
        end
    elseif not near and TRN.Setup.on("Flag") and M.byTrack(player) then
        -- On the ground beside the track, with no train in reach: ask the
        -- next one along to stop here.
        context:addOption(getText("IGUI_TRN_Flag"), worldobjects, M.onSend, player, "flag")
    end

    -- On the ground: the train she waits for, wherever she is; and by a track,
    -- every train of it by name, to wait for.
    if not riding and not inside then
        if waitId then
            local m = U.try("menu.waitLook", TRN.Trip.look, player, waitId)
            if m then context:addOption(TRN.Trip.words(m), worldobjects, nil).notAvailable = true end
            local _, awaited = T.find(K.routes(), waitId)
            context:addOption(getText("IGUI_TRN_WaitClear", U.trainName(awaited)), worldobjects, M.onWaitClear, player,
                              U.trainName(awaited))
        end
        local picks = U.try("menu.waitPicks", M.waitPicks, player, waitId) or {}
        if #picks > 0 then
            local wait = context:addOption(getText("IGUI_TRN_WaitMenu"), worldobjects, nil)
            local sub = ISContextMenu:getNew(context)
            context:addSubMenu(wait, sub)
            for _, pick in ipairs(picks) do
                sub:addOption(getText("IGUI_TRN_WaitPick", U.trainName(pick.train), TRN.Trip.span(pick.secs)),
                              worldobjects, M.onWait, player, pick.train)
            end
        end
    end

    -- Her own train: aboard one, making it hers; anywhere else, where hers is.
    local aboardId = (riding or inside) and (riding or inside).train or nil
    if aboardId and TRN.Map then
        local _, train = T.find(K.routes(), aboardId)
        if train and homeId == aboardId then
            grey(context:addOption(getText("IGUI_TRN_HomeIs", U.trainName(train)), worldobjects, nil), "IGUI_TRN_HomeIsTip")
        elseif train then
            context:addOption(getText("IGUI_TRN_HomeMake", U.trainName(train)), worldobjects, M.onHome, player, train)
        end
    end
    if homeId and homeId ~= aboardId then
        local text = U.try("menu.homeLine", M.homeLine, player, homeId)
        if text then context:addOption(text, worldobjects, nil).notAvailable = true end
    end

    -- Whose train it is (TRN_Claims). Aboard one that is nobody's: making it
    -- hers, greyed where she has as many as a player may. Aboard somebody
    -- else's: whose. And each train of her own, from anywhere.
    if aboardId and Cl.most() >= 1 then
        local _, train = T.find(K.routes(), aboardId)
        local claim = Cl.of(aboardId)
        if train and not claim then
            local make = context:addOption(getText("IGUI_TRN_ClaimMake", U.trainName(train)), worldobjects, M.onSend, player,
                                           "claim", {})
            if #mine >= Cl.most() then grey(make, "IGUI_TRN_RefuseClaimMany", Cl.most()) end
        elseif train and claim.who ~= me then
            context:addOption(getText("IGUI_TRN_ClaimOf", U.trainName(train), claim.who), worldobjects, nil).notAvailable = true
        end
    end
    for _, id in ipairs(mine) do
        U.try("menu.claim", M.claimMenu, context, worldobjects, player, id, riding, inside)
    end

    -- An admin's tools: a line of the host's own (SERVERS.md). Not from aboard.
    if admin and not riding and not inside then
        U.try("menu.admin", TRN.Admin.fill, context, worldobjects, player)
    end

    if C.DevTools then
        local dev = context:addOption(getText("IGUI_TRN_DevMenu"), worldobjects, nil)
        local menu = ISContextMenu:getNew(context)
        context:addSubMenu(dev, menu)
        -- Where the trains are, first: lines to read, not to choose. The
        -- three nearest: the map's routes have a score of them.
        local found = {}
        local hx, hy = player:getX(), player:getY()
        for _, route in ipairs(K.routes()) do
            for _, train in ipairs(route.trains) do
                local w = K.where(route, train)
                if w then
                    local x, y = T.at(route, w.c)
                    found[#found + 1] = { route = route, w = w, far = (x - hx) * (x - hx) + (y - hy) * (y - hy) }
                end
            end
        end
        table.sort(found, function(a, b) return a.far < b.far end)
        for i = 1, math.min(3, #found) do
            local w, route = found[i].w, found[i].route
            local line = menu:addOption(getText(w.moving and "IGUI_TRN_DevMoving" or "IGUI_TRN_DevParked",
                                                U.stopName(route.stops[w.moving and w.to or w.at]),
                                                tostring(math.ceil(w.moving and w.arrive or w.depart))),
                                        worldobjects, nil)
            line.notAvailable = true
        end
        local go = menu:addOption(getText("IGUI_TRN_DevGoStop"), worldobjects, M.onSend, player, "goStop")
        if #found == 0 then grey(go, "IGUI_TRN_RefuseNoTrain") end
        menu:addOption(getText("IGUI_TRN_DevLayEast"), worldobjects, M.onSend, player, "layLine", { axis = "x" })
        menu:addOption(getText("IGUI_TRN_DevLaySouth"), worldobjects, M.onSend, player, "layLine", { axis = "y" })
        menu:addOption(getText("IGUI_TRN_DevLayBend"), worldobjects, M.onSend, player, "layLine", { bend = true })
        local has = K.state ~= nil and K.state.line ~= nil
        local skip = menu:addOption(getText("IGUI_TRN_DevSkip"), worldobjects, M.onSend, player, "skip")
        local clear = menu:addOption(getText("IGUI_TRN_DevClear"), worldobjects, M.onSend, player, "clearLine")
        if #found == 0 then grey(skip, "IGUI_TRN_RefuseNoTrain") end
        if not has then grey(clear, "IGUI_TRN_RefuseNoTrain") end
        menu:addOption(getText("IGUI_TRN_DevStatus"), worldobjects, M.onStatus, player)
    end
end

Events.OnFillWorldObjectContextMenu.Add(M.fill)

---------------------------------------------------------------------------
-- The interact key
---------------------------------------------------------------------------
--- What the interact key does from where this player stands (the author,
--- 2026-10-09: "pressing E near any door makes you go through it from the
--- inside or outside of the train"). **Wherever a green mark is shown, the
--- key takes it** (TRN_Body, B.marks: the same nearness, C.Marks.near), and
--- the nearest one if she is by two:
---
---   * inside a car, at one of its three doors: out by it;
---   * on a platform, at a car's end: in by its door, or up its ladder if
---     it is a car with no way in;
---   * on a top, at its end: down to the platform there;
---   * on the ground, at the platform of a parked train: aboard.
---
--- Returns { cmd, args } for the server, which checks it as it checks the
--- menu's; nil where there is nothing in reach, and the key is the game's.
function M.door(player)
    local x, y = player:getX(), player:getY()
    local reach = C.Marks.near
    local best, bestD = nil, nil
    local function offer(px, py, slack, cmd, args)
        local dx, dy = px - x, py - y
        local d, far = dx * dx + dy * dy, reach + (slack or 0)
        if d <= far * far and (not bestD or d < bestD) then best, bestD = { cmd = cmd, args = args }, d end
    end
    local inside = TRN.Inside and TRN.Inside.record(player) or nil
    if inside then
        -- Not while she is being put in: the room may not be there yet.
        if inside.arriving or not inside.room then return nil end
        for _, door in ipairs({ "front", "rear", "side" }) do
            local sx, sy = TRN.Rooms.spot(inside.room, door)
            if door == "side" then offer(sx, sy, 0, "leave", {}) else offer(sx, sy, 0, "exitTo", { door = door }) end
        end
        return best
    end
    local r = D.record(player)
    if not r then
        local near = M.nearestDeck(player)
        if near and not near.w.moving then
            local px, py = T.deckAt(near.route, near.train, near.w, near.deck)
            offer(px, py, C.Deck.halfWid, "board", { train = near.train.id, deck = near.deck })
        end
        return best
    end
    if r.landing then return nil end
    local route, train = T.find(K.routes(), r.train)
    local w = route and K.where(route, train)
    if not w then return nil end
    local layout = T.layout(train.consist)
    if r.top then
        local car = layout.cars[r.top]
        local cx, cy, ux, uy = T.carAt(route, w.c, car)
        -- The end of what there is to stand on, not of the car: a tank's catwalk and a
        -- caboose's roof stop short of it, and she comes up half a square in from there.
        local half = C.Cars[car.kind].topLen
        for _, e in ipairs({ { deck = r.top - 1, s = 1 }, { deck = r.top, s = -1 } }) do
            if layout.decks[e.deck] then
                offer(cx + ux * half * e.s, cy + uy * half * e.s, 0, "descend", { deck = e.deck })
            end
        end
        return best
    end
    -- On a platform: the car ahead shows it its rear end, the car behind its front.
    for _, e in ipairs({ { car = r.deck, s = -1 }, { car = r.deck + 1, s = 1 } }) do
        local car = layout.cars[e.car]
        if car then
            local kind = C.Cars[car.kind]
            local cx, cy, ux, uy = T.carAt(route, w.c, car)
            offer(cx + ux * kind.len / 2 * e.s, cy + uy * kind.len / 2 * e.s, 0,
                  kind.inside and "enter" or "climb", { car = e.car })
        end
    end
    return best
end

--- The interact key, as vanilla's own Lua asks for it
--- (client/Farming/CFarming_Interact.lua). The game does whatever else it
--- does with the key: nothing here can take it away.
function M.onKey(key)
    if U.try("menu.isKey", function() return getCore():isKey(KeybindId.INTERACT, key) end) ~= true then return end
    local player = U.try("menu.keyPlayer", function() return getSpecificPlayer(0) end)
    if not player or U.try("menu.keyDead", function() return player:isDead() end) == true then return end
    local way = U.try("menu.door", M.door, player)
    if way then Net.send(player, way.cmd, way.args) end
end

Events.OnKeyStartPressed.Add(M.onKey)

return M
