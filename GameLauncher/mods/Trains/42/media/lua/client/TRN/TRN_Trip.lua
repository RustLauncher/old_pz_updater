if isServer() then return end

--[[ Trains -- a rider's plans: the stop she gets off at, and the train she waits for.

    The author, 2026-10-09. Two things a player sets once and then stops
    thinking about, and both are this machine's own: the server is asked
    exactly what the menu would ask it, when the time comes.

      * **Get off at N.** Aboard, she picks a stop of her train's route.
        She then goes about her business, through the cars and over them,
        and when the train stands at that stop she is put off it: by the
        side door from inside a car, off the platform from a platform, down
        the ladder and off from a top. A minute before, she is told, woken
        if she sleeps, and a game run fast is set back to normal. A stop out
        on the line (the cord, a flag) is not her stop.

      * **Board the N.** On the ground by any track, she picks a train by
        its name, and waits: it may be hours away, and she is told how long.
        She is told again as it nears, with a sound. If she is by the track
        when it is within a beat of her, it is asked to stop for her there
        (the server's "flag", for that one train); within a station's length
        of a stop it stops there anyway. **Boarding is hers to do**: it stands, and she
        gets on.

    Both are kept with her character (its mod data), so a save, a load and
    a night's sleep keep them. When each next matters is TRN_Time.due and
    TRN_Time.meet: the timetable, never where a picture is.

    UNMEASURED, all of it in the game: that forceAwake wakes a sleeper on
    her own machine; that the speed controls take a setting from here as
    they do from vanilla's own dialogs; the sound.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Plow"
require "TRN/TRN_Deck"
require "TRN/TRN_Inside"

TRN = TRN or {}
local C, U, Net, T, K, D = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock, TRN.Deck

local P = {}
TRN.Trip = P

-- username -> what has been said and asked, so that nothing is said twice.
P.memo = {}
P.stats = { offs = 0, flags = 0, alerts = 0 }
P.dueMs = 0

local function mem(player)
    local who = U.username(player) or "?"
    P.memo[who] = P.memo[who] or {}
    return P.memo[who]
end

--- What she is aboard: her record inside a car, or on a platform or a top.
local function aboard(player)
    local inside = TRN.Inside and TRN.Inside.record(player) or nil
    return inside or D.record(player), inside
end

--- True once the server has said whether it has her aboard anything: until
--- then "aboard nothing" is only "not told yet" (a save loaded on a train).
local function answered()
    return TRN.Client ~= nil and TRN.Client.answered == true
end

--- A length of time in words: minutes from a minute and a half up.
function P.span(secs)
    if secs >= 90 then return getText("IGUI_TRN_SpanMin", tostring(math.ceil(secs / 60))) end
    return getText("IGUI_TRN_SpanSec", tostring(math.max(0, math.ceil(secs))))
end

--- Something she should not miss: words, a sound, and when it is `urgent`
--- she is woken and a game run fast is set back to normal, as vanilla's own
--- dialogs set it (ISAlarmClockDialog).
function P.alert(player, text, urgent)
    U.note(player, text, 255, 225, 120)
    U.try("trip.sound", function() getSoundManager():playUISound(C.Trip.sound) end)
    if urgent then
        U.try("trip.wake", function()
            if player:isAsleep() then player:forceAwake() end
        end)
        if not isClient() then
            U.try("trip.speed", function()
                local speed = UIManager.getSpeedControls()
                if speed:getCurrentGameSpeed() > 1 then speed:SetCurrentGameSpeed(1) end
            end)
        end
    end
    P.stats.alerts = P.stats.alerts + 1
end

---------------------------------------------------------------------------
-- Get off at N
---------------------------------------------------------------------------
--- Where she has said she gets off: { train, stop }, or nil.
function P.off(player)
    local plan = U.try("trip.getOff", function() return player:getModData().TRN_off end)
    if type(plan) ~= "table" or not plan.train or not tonumber(plan.stop) then return nil end
    return plan
end

function P.setOff(player, trainId, stop)
    U.try("trip.setOff", function()
        player:getModData().TRN_off = trainId and { train = trainId, stop = stop } or nil
    end)
    local m = mem(player)
    m.offSaid, m.offStood, m.offAsked, m.offTries, m.offAskMs = nil, nil, nil, nil, nil
end

--- The stops a train calls at, soonest first: { { stop, secs }, ... }. Not
--- the one it is standing at.
function P.calls(route, train)
    local out = {}
    local t = K.now()
    if not t then return out end
    for i = 1, #route.stops do
        local secs, here = T.due(route, train, t, K.moveTime(), K.dwell(), i)
        if secs and not here then out[#out + 1] = { stop = i, secs = secs } end
    end
    table.sort(out, function(a, b) return a.secs < b.secs end)
    return out
end

--- One tick of somebody who has said where she gets off.
function P.offTick(player)
    local plan = P.off(player)
    if not plan then return end
    local m = mem(player)
    local r, inside = aboard(player)
    if not r then
        if not answered() then return end
        -- Off the train: put off at her stop by this file, or gone by her own hand.
        if m.offAsked then
            U.note(player, getText("IGUI_TRN_OffDone", m.offAsked), 150, 220, 150)
            P.stats.offs = P.stats.offs + 1
        end
        return P.setOff(player, nil)
    end
    if r.train ~= plan.train then return P.setOff(player, nil) end
    local route, train = T.find(K.routes(), plan.train)
    local w = route and K.where(route, train)
    if not w then return end
    local stop = route.stops[plan.stop]
    if not stop then return P.setOff(player, nil) end
    local name = U.stopName(stop)

    if w.moving or w.halted or w.at ~= plan.stop then
        if m.offStood then
            -- It stood at her stop and left with her aboard: said, and forgotten.
            U.note(player, getText("IGUI_TRN_OffMissed", name), 255, 120, 90)
            return P.setOff(player, nil)
        end
        if w.moving and w.to == plan.stop and w.arrive <= C.Trip.soon and m.offSaid ~= w.beat then
            m.offSaid = w.beat
            P.alert(player, getText("IGUI_TRN_OffSoon", name, P.span(w.arrive)), true)
        end
        return
    end

    -- Standing at her stop. Not while she is still being put somewhere: the
    -- room may not be there yet, nor the ground under the platform.
    m.offStood = true
    if (inside and (inside.arriving or not inside.room)) or r.landing then return end
    local now = U.nowMs()
    if m.offAskMs and now - m.offAskMs < C.Trip.askMs then return end
    if (m.offTries or 0) >= C.Trip.tries then return end
    m.offAskMs, m.offTries, m.offAsked = now, (m.offTries or 0) + 1, name
    if inside then
        Net.send(player, "leave", {})
    elseif r.top then
        -- Down the ladder first, to the platform behind her car, or ahead of the last one.
        local decks = T.layout(train.consist).decks
        Net.send(player, "descend", { deck = decks[r.top] and r.top or (r.top - 1) })
    else
        Net.send(player, "alight", {})
    end
    -- In single player the answer is here already (DEV_GUIDE.md): the next
    -- step, off the platform she has just come down to, need not wait.
    if aboard(player) ~= r then m.offAskMs, m.offTries = nil, 0 end
end

---------------------------------------------------------------------------
-- Board the N
---------------------------------------------------------------------------
--- The train she is waiting for, by its id, or nil.
function P.waiting(player)
    local id = U.try("trip.getWait", function() return player:getModData().TRN_wait end)
    if type(id) ~= "string" then return nil end
    return id
end

function P.setWait(player, trainId)
    U.try("trip.setWait", function() player:getModData().TRN_wait = trainId end)
    local m = mem(player)
    m.eta, m.wasHere, m.hereSaid, m.flagBeat, m.view = nil, nil, nil, nil, nil
end

--- Where a train is to her, from where she stands: TRN.Time.meet at the
--- place on its route nearest her, and with it the route, the train, where
--- it is (`w`), how far she is from the track (`far`), and whether it is
--- standing beside her now (`beside`). Nil before the clock is known.
function P.look(player, trainId)
    local route, train = T.find(K.routes(), trainId)
    local w = route and K.where(route, train)
    if not w then return nil end
    local x, y = player:getX(), player:getY()
    local d, far = T.nearest(route, x, y)
    if not d then return nil end
    local m = T.meet(route, train, K.now(), K.moveTime(), K.dwell(), d, C.Stop.clear, K.state and K.state.halts)
    if not m then return nil end
    m.route, m.train, m.w, m.far = route, train, w, far
    m.level = math.floor(player:getZ()) == route.z
    m.beside = (not w.moving) and m.level
               and TRN.Plow.within(TRN.Plow.boxes(route, train, w, C.Trip.beside), x, y) ~= nil
    return m
end

--- That, in words.
function P.words(m)
    local name = U.trainName(m.train)
    if m.beside then return getText("IGUI_TRN_WaitHere", name, P.span(m.w.depart)) end
    if m.stop then
        local stop = U.stopName(m.route.stops[m.stop])
        if m.here then return getText("IGUI_TRN_WaitAt", name, stop, P.span(m.secs)) end
        return getText("IGUI_TRN_WaitStop", name, stop, P.span(m.secs))
    end
    if m.here then return getText("IGUI_TRN_WaitHere", name, P.span(m.secs)) end
    if m.level and m.far <= C.Stop.reach then return getText("IGUI_TRN_WaitTrack", name, P.span(m.secs)) end
    return getText("IGUI_TRN_WaitFar", name, P.span(m.secs))
end

--- One look at somebody who is waiting for a train.
function P.waitTick(player)
    local id = P.waiting(player)
    if not id then return end
    if aboard(player) then
        -- Aboard: the waiting is over, whichever train it is.
        if answered() then P.setWait(player, nil) end
        return
    end
    local m = P.look(player, id)
    local s = mem(player)
    s.view = m
    if not m then return end
    local name = U.trainName(m.train)
    local cycle = K.dwell() + K.moveTime()

    if m.beside or m.here then
        -- Standing for her: said once each time it stands.
        local key = tostring(m.w.beat) .. (m.w.halted and "h" or "s")
        if s.hereSaid ~= key then
            s.hereSaid = key
            P.alert(player, P.words(m), true)
        end
        s.eta, s.wasHere = nil, true
        return
    end
    if s.wasHere or (s.eta and m.secs > s.eta + cycle / 2) then
        -- It was here, or went by, and she is not on it.
        s.wasHere = nil
        U.note(player, getText("IGUI_TRN_WaitGone", name, P.span(m.secs)), 255, 120, 90)
    elseif s.eta then
        for _, mark in ipairs(C.Trip.alerts) do
            if s.eta > mark and m.secs <= mark then
                -- By how far off it is now, not by which mark was passed: a clock run
                -- fast passes several between two looks.
                P.alert(player, P.words(m), m.secs <= C.Trip.soon)
                break
            end
        end
    end
    s.eta = m.secs

    -- By the track, out between two stations, with her train within a beat
    -- of her: it is asked to stop for her here. A beat, so that it is asked
    -- while it has yet to start the leg she is on: from standing there is
    -- always the time, and a train already on its way may have none. Not
    -- twice: a stop asked for is in the state, and a refusal is not asked
    -- again until the next beat.
    if not m.stop and m.level and m.far <= C.Stop.reach and m.secs <= cycle then
        local halts = K.state and K.state.halts
        local h = halts and halts[id]
        local beat = math.floor(K.now() / cycle)
        if not (h and h.beat >= beat) and s.flagBeat ~= beat then
            s.flagBeat = beat
            P.stats.flags = P.stats.flags + 1
            Net.send(player, "flag", { train = id })
        end
    end
end

--- What was last seen of the train she waits for (P.look), for the map.
function P.view(player)
    return mem(player).view
end

---------------------------------------------------------------------------
-- Every tick
---------------------------------------------------------------------------
Events.OnTick.Add(function()
    local player = U.try("trip.who", function() return getSpecificPlayer(0) end)
    if not player or U.try("trip.dead", function() return player:isDead() end) == true then return end
    U.try("trip.offTick", P.offTick, player)
    local now = U.nowMs()
    if now < P.dueMs then return end
    P.dueMs = now + C.Trip.everyMs
    U.try("trip.waitTick", P.waitTick, player)
end)

function P.status()
    local player = U.try("trip.statusWho", function() return getSpecificPlayer(0) end)
    local plan = player and P.off(player)
    U.log("status: plans: getting off at %s, waiting for %s; %d put off, %d train(s) asked to stop, %d alert(s)",
          plan and (tostring(plan.train) .. " stop " .. tostring(plan.stop)) or "nowhere",
          tostring(player and P.waiting(player) or "nothing"), P.stats.offs, P.stats.flags, P.stats.alerts)
end

return P
