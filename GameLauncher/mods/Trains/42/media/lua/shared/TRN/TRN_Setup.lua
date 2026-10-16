--[[ Trains -- what a host has set (SERVERS.md).

    Everywhere: the sandbox's page is the same on every machine, so every
    machine reads a host's choices for itself and comes to the same trains.
    Nothing here is sent.

    A setting is read through this file and nowhere else. Each is one of
    two kinds, and SERVERS.md says which of every one:

      * **what the trains are**: which lines run, which stops they call at,
        how many trains, what a train is made of, what it is called. These
        go into the routes (TRN_Time.network), and `Su.stamp` is the one
        string that changes when any of them does: the routes are built
        again when it has.
      * **what is allowed and what is shown**: the cord, a flag, the plates,
        the map. Asked where the thing is done.

    A host's own lines are not a setting: an admin lays them in the game
    and they are saved with the world (TRN_Server, `lines`).
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"

TRN = TRN or {}
local C, U = TRN.Config, TRN.Util

local Su = {}
TRN.Setup = Su

--- One of the sandbox's numbers, or `default` where it is not set: a world
--- made before the option was.
function Su.num(name, default)
    local v = U.try("setup:" .. name, function()
        return SandboxVars and SandboxVars.Trains and SandboxVars.Trains[name]
    end)
    if type(v) ~= "number" or v ~= v then return default end
    return v
end

--- One of the sandbox's lines of text, with the blanks at its ends gone.
function Su.text(name)
    local v = U.try("setup:" .. name, function()
        return SandboxVars and SandboxVars.Trains and SandboxVars.Trains[name]
    end)
    if type(v) ~= "string" then return "" end
    return (v:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- True for a yes-or-no setting that says yes: 1, or not set.
function Su.on(name)
    return Su.num(name, 1) == 1
end

--- A line of text as a list: split at commas, blanks at the ends of each
--- gone, nothing kept that is empty.
function Su.list(text)
    local out = {}
    for part in string.gmatch(text or "", "[^,]+") do
        local word = part:gsub("^%s+", ""):gsub("%s+$", "")
        if word ~= "" then out[#out + 1] = word end
    end
    return out
end

---------------------------------------------------------------------------
-- What the trains are
---------------------------------------------------------------------------
--- The fastest a train goes at the peak of its ease.
function Su.top()
    return U.clamp(Su.num("TopSpeed", C.TopSpeed), C.TopFloor, C.TopCeil)
end

--- How long every train stands at a stop.
function Su.dwell()
    return math.max(10, Su.num("Dwell", C.Dwell))
end

--- True for one of the map's own lines that the host has running.
function Su.runs(id)
    if id == "circle" then return Su.on("Circle") end
    if id == "louisville" then return Su.on("Louisville") end
    return true
end

--- True for a stop the trains call at: all of them, or the towns only. A
--- halt is a stop the generator put between two towns to keep the runs
--- even (tools/gen_rails.py), and is named for it.
function Su.calls(stop)
    if Su.num("Halts", 1) ~= 2 then return true end
    return string.find(stop.name or "", " Halt", 1, true) == nil
end

--- How many stops apart a loop's trains are: 1 a train to every stop, 2
--- to every second one, and so on. Nil is one train on the line and no
--- more.
function Su.every()
    local fleet = Su.num("Fleet", 1)
    if fleet >= 5 then return nil end
    return math.max(1, math.floor(fleet))
end

--- What a rolled train is made of: one of C.Roll.lengths.
function Su.length()
    local n = math.floor(Su.num("Length", 1))
    if not C.Roll.lengths[n] then n = 1 end
    return n
end

--- How many empty boxcars a rolled train has, as well as whatever its dice
--- gave it: coupled on behind the rest, before the rear locomotive.
function Su.empties()
    return U.clamp(math.floor(Su.num("Empties", C.Roll.empties)), 0, C.Roll.emptiesMost)
end

--- The cars the host wrote for every train, front first, or nil where the
--- trains are rolled. A word that is no kind of car is left out, and said
--- once in the log; a train of nothing is no train, so then it is rolled.
function Su.consist()
    local text = Su.text("Consist")
    if text == "" then return nil end
    if Su.parsed and Su.parsedFrom == text then return Su.parsed or nil end
    local cars = {}
    for _, word in ipairs(Su.list(string.lower(text))) do
        if C.Cars[word] and #cars < C.Rooms.perRow * C.Rooms.rows then
            cars[#cars + 1] = { kind = word }
        else
            U.warnOnce("setup.consist:" .. word, "the sandbox's Consist names '%s', which is no kind of car, or is past "
                       .. "the %d a train may be: left out", word, C.Rooms.perRow * C.Rooms.rows)
        end
    end
    -- A locomotive at the rear faces back, as the rolled trains' do.
    if #cars > 1 and cars[#cars].kind == "loco" then cars[#cars].flip = true end
    Su.parsedFrom, Su.parsed = text, (#cars > 0) and cars or false
    return Su.parsed or nil
end

--- The names the host wrote, in the order the trains are numbered.
function Su.names()
    local text = Su.text("Names")
    if Su.named and Su.namedFrom == text then return Su.named end
    Su.namedFrom, Su.named = text, Su.list(text)
    return Su.named
end

--- What train number `n` is called: the host's name for it, or the mod's,
--- or `fallback`.
function Su.name(n, fallback)
    return Su.names()[n] or C.Names[n] or fallback
end

--- Everything above that decides what the routes are, as one string: the
--- routes are built again when it changes (TRN_Time.routes). Worked out at
--- most once a second: it is asked for every frame.
function Su.stamp()
    local now = U.nowMs()
    if Su.stamped and Su.stampAt and now - Su.stampAt < 1000 and now >= Su.stampAt then return Su.stamped end
    Su.stampAt = now
    Su.stamped = table.concat({ Su.num("Circle", 1), Su.num("Louisville", 1), Su.num("Halts", 1), Su.num("Fleet", 1),
                                Su.length(), Su.text("Consist"), Su.text("Names"), Su.empties() }, "|")
    return Su.stamped
end

--- What decides which car is which in a train: when this changes, every
--- car's room is somebody else's, and they are all forgotten (TRN_Build).
--- **Not how many empties**: those are coupled on behind what a train has,
--- each with a room of its own that nothing else ever has (TRN_Time.roll),
--- so more of them or fewer moves nobody's things.
function Su.cars()
    return Su.length() .. "|" .. string.lower(Su.text("Consist"))
end

---------------------------------------------------------------------------
-- Whose a train is (TRN_Claims)
---------------------------------------------------------------------------
--- How many trains a player may make their own. None: nobody owns a train.
function Su.claims()
    return U.clamp(math.floor(Su.num("Claims", C.Claims.each)), 0, C.Claims.limit)
end

---------------------------------------------------------------------------
-- What a car comes with
---------------------------------------------------------------------------
--- One of a setting's three ways: the first where it is nonsense.
local function way(n)
    n = math.floor(n)
    if n < 1 or n > 3 then n = 1 end
    return n
end

--- The greenhouse car: "tended" (sown, and looked after), "sown" (and its
--- riders' to look after), or "bare" (soil and nothing in it).
function Su.garden()
    return ({ "tended", "sown", "bare" })[way(Su.num("Garden", 1))]
end

--- The livestock car: "kept" (animals, fed and watered while somebody is
--- aboard), "stocked" (animals, and its riders' to keep), or "none".
function Su.animals()
    return ({ "kept", "stocked", "none" })[way(Su.num("Animals", 1))]
end

return Su
