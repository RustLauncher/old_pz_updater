--[[ Trains -- shared helpers.

    Everything here is defensive on purpose: a wrong engine call throws out
    of Java, and inside a per-zombie loop the engine dumps a stack trace for
    every call (DEV_GUIDE.md, "Batch anything repeated"). The wrappers are
    the Shuttlecraft's, by way of the Heroes mod, unchanged, because they
    were paid for there.
]]

require "TRN/TRN_Config"

TRN = TRN or {}
local C = TRN.Config

local U = {}
TRN.Util = U

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
function U.log(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        if ok then msg = formatted end
    end
    print(C.ModPrefix .. " " .. tostring(msg))
end

function U.debug(fmt, ...)
    if C.Debug then U.log(fmt, ...) end
end

-- Errors are noisy the first time and silent afterwards, so a per-tick
-- failure cannot flood console.txt.
local reported = {}
function U.warnOnce(key, fmt, ...)
    if reported[key] then return end
    reported[key] = true
    U.log("WARN (" .. tostring(key) .. ") " .. tostring(fmt), ...)
end

--- Guards a call that is about to be repeated over many zombies or cars.
--- Returns a callable that stops trying after its first failure.
function U.batch(label)
    local broken = false
    return function(fn)
        if broken then return nil end
        local ok, result = pcall(fn)
        if not ok then
            broken = true
            U.warnOnce(label, tostring(result))
            return nil
        end
        return result
    end
end

--- Runs fn, logs the first failure under `label` and returns nil on error.
--- A nil back means "failed" as well as "returned nothing": never let it
--- mean yes.
function U.try(label, fn, ...)
    local args = { ... }
    local ok, result = pcall(function() return fn(unpack(args)) end)
    if not ok then
        U.warnOnce(label, tostring(result))
        return nil
    end
    return result
end

---------------------------------------------------------------------------
-- The world, read-only
---------------------------------------------------------------------------
function U.cell()
    return U.try("getCell", getCell)
end

--- Real milliseconds, on whichever machine is asking. Only ever subtracted
--- from another of the same machine's: a time never crosses the network.
function U.nowMs()
    return U.try("clock", getTimestampMs) or 0
end

--- Every player this process knows.
function U.players()
    local out = {}
    local list = U.try("playerList", function()
        if isServer() or isClient() then return getOnlinePlayers() end
        return IsoPlayer.getPlayers()
    end)
    if not list then return out end
    local n = U.try("playerCount", function() return list:size() end) or 0
    for i = 0, n - 1 do
        local p = U.try("playerAt", function() return list:get(i) end)
        if p then table.insert(out, p) end
    end
    return out
end

function U.username(player)
    if not player then return nil end
    return U.try("username", function() return player:getUsername() end)
end

--- The square at a position, or nil. Never creates one: a nil here means
--- "nothing there, or not loaded", and the caller treats both as a wall.
function U.square(x, y, z)
    local cell = U.cell()
    if not cell then return nil end
    return U.try("getGridSquare", function()
        return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    end)
end

--- True when this machine is the one that simulates this zombie, and so the
--- one whose moves of it stick. isRemoteZombie() answers true for every
--- zombie in single player (pz-heros DEV_GUIDE.md), so the question is only
--- put on a client connected to a server.
function U.simulated(zed)
    if not isClient() then return true end
    return not zed:isRemoteZombie()
end

--- Where a body at x, y ends up when thrown `push` tiles along dx, dy (a
--- unit vector): a square at a time, stopping at the first wall, closed
--- door, hole or unloaded square. (The Heroes mod's slam.)
function U.thrownTo(x, y, z, dx, dy, push)
    local from = U.square(x, y, z)
    if not from then return x, y end
    local steps = math.floor(push)
    local rest = push - steps
    for i = 1, steps + 1 do
        local d = (i <= steps) and 1 or rest
        if d <= 0 then break end
        local nx, ny = x + dx * d, y + dy * d
        local to = U.square(nx, ny, z)
        if not to then break end
        if to ~= from then
            local clear = U.try("throw.clear", function()
                if to:getFloor() == nil then return "hole" end
                if from:isBlockedTo(to) then return "wall" end
                return "ok"
            end)
            if clear ~= "ok" then break end
        end
        x, y, from = nx, ny, to
    end
    return x, y
end

---------------------------------------------------------------------------
-- Arithmetic the engine's Lua gets wrong, or does not have
---------------------------------------------------------------------------
--- a modulo b, for b > 0: always in 0 .. b. **Use this and never the %
--- operator.** Kahlua's % puts the quotient through a 32-bit int: wrong
--- past 2^31 and wrong for a negative a (pz-heros DEV_GUIDE.md, "The game's
--- Lua is not Lua"). tests/test_kahlua.py runs the timetable in the game's
--- own interpreter.
function U.mod(a, b)
    return a - math.floor(a / b) * b
end

--- The angle of the direction dx, dy, in radians, -pi .. pi. Written out:
--- the game's Lua has math.atan2 and the tests' does not, and one-argument
--- math.atan is in both.
function U.angle(dx, dy)
    if dx == 0 then
        if dy > 0 then return math.pi / 2 end
        if dy < 0 then return -math.pi / 2 end
        return 0
    end
    local a = math.atan(dy / dx)
    if dx < 0 then
        if dy >= 0 then return a + math.pi end
        return a - math.pi
    end
    return a
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- True for somebody who may do what only an admin may (SERVERS.md): a
--- role with any of the game's admin tools, which is what the game shows
--- its own admin button by, **asked of this machine's copy of the player**,
--- so a server never takes a client's word. Never the global isAdmin(): it
--- is true for the one default admin role and on a client only
--- (pz_sewars DEV_GUIDE.md, *An admin is a role with a tool*). Single
--- player has no roles: the dev build, or the game run with -debug.
function U.admin(player)
    if not isClient() and not isServer() then
        return C.DevTools == true or (isDebugEnabled ~= nil and isDebugEnabled() == true)
    end
    if not player then return false end
    return U.try("admin", function()
        local role = player:getRole()
        return role ~= nil and role:hasAdminTool() == true
    end) == true
end

---------------------------------------------------------------------------
-- Telling the player
---------------------------------------------------------------------------
--- What a stop is called: a town's own name on the map's routes, a text
--- key on the test line.
function U.stopName(stop)
    if not stop then return "?" end
    if stop.name then return stop.name end
    return getText(stop.key)
end

--- What a train is called: its name on the map's routes, and the test
--- line's train is the test train.
function U.trainName(train)
    if train and train.name then return train.name end
    return getText("IGUI_TRN_TestTrain")
end

function U.note(player, text, r, g, b)
    if not player or not text then return end
    U.try("haloNote", function()
        player:setHaloNote(text, r or 255, g or 210, b or 90, 300)
    end)
end

return U
