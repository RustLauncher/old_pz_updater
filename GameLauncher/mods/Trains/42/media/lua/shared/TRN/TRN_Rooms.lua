--[[ Trains -- where the inside of each car is (DESIGN.md 3.4, 5.2).

    The inside of a car is a room that never moves, in a cell off the edge of
    the map. This file is only where: arithmetic, the same on every machine.
    TRN_Build raises a room on the server; TRN_Inside is a client's player
    going in and out.

    Each car of each train has its own room, with black between them: the
    cars do not join (the author, 2026-10-08). A room lies along x. Its
    **front** end, toward the car ahead, is its west end; its **rear** is
    east; its **side** door, the one that opens at a stop, is in its south
    wall.

        x0 ......................... x0 + len - 1
     y0   . s . s . s . s . s . .      s  seats (a coach)
     y0+1 . s . s . s . s . s . .
     y0+2 F . . . . . . . . . . R      F  where the front door puts you; R the rear
     y0+3 . s . s . . . s . s . .         the aisle is the middle row
     y0+4 . s . s . S . s . s . .      S  where the side door puts you
]]

require "TRN/TRN_Config"
require "TRN/TRN_Setup"
require "TRN/TRN_Util"

TRN = TRN or {}
local C = TRN.Config

local R = {}
TRN.Rooms = R

--- Which map cell the first train's rooms are in: the mod's own
--- (C.Rooms.cell), or the host's (sandbox RoomsX, RoomsY; SERVERS.md, *If
--- another mod's map is in the way*). Never on the game's own map, nor
--- past what the engine has for a world: held to C.Rooms.cellLeast and
--- cellMost. The same on every machine, as the sandbox is.
function R.cellX()
    local G, Su = C.Rooms, TRN.Setup
    return TRN.Util.clamp(math.floor(Su.num("RoomsX", G.cell.x)), G.cellLeast.x, G.cellMost.x)
end

function R.cellY()
    local G, Su = C.Rooms, TRN.Setup
    return TRN.Util.clamp(math.floor(Su.num("RoomsY", G.cell.y)), G.cellLeast.y, G.cellMost.y)
end

--- True while the rooms are where the mod's own empty map is under them.
function R.atHome()
    return R.cellX() == C.Rooms.cell.x and R.cellY() == C.Rooms.cell.y
end

--- Where the rooms are, as one word: when it changes, every room there was
--- is somewhere else (TRN_Build.sweepOld).
function R.where()
    return R.cellX() .. "," .. R.cellY()
end

--- The room of car `car` (1 is the front) of the train numbered `index`
--- (0 for the first train there is).
function R.room(index, car)
    local G = C.Rooms
    -- Six to a row, and a train has C.Rooms.rows rows: its seventh car's room is
    -- under its first's. (They were all in one row, and the seventh would
    -- have stood outside the cell.)
    -- And each train has a cell of its own, east of the last (C.Rooms.trains).
    local col, row = TRN.Util.mod(car - 1, G.perRow), math.floor((car - 1) / G.perRow)
    local x0 = (R.cellX() + index) * G.cellSize + G.offset + col * G.pitch
    local y0 = R.cellY() * G.cellSize + G.offset + row * G.pitch
    return { x0 = x0, y0 = y0, x1 = x0 + G.len - 1, y1 = y0 + G.wid - 1, z = G.z, index = index, car = car }
end

--- Where a door of a room puts somebody: the middle of a square, x, y.
function R.spot(room, door)
    local G = C.Rooms
    local aisle = room.y0 + math.floor(G.wid / 2) + 0.5
    if door == "front" then return room.x0 + 0.5, aisle end
    if door == "rear" then return room.x1 + 0.5, aisle end
    if door == "side" then return room.x0 + math.floor(G.len / 2) - 0.5, room.y1 + 0.5 end
    return (room.x0 + room.x1 + 1) / 2, aisle
end

--- True when x, y is inside a room's walls.
function R.within(room, x, y)
    return x >= room.x0 and x < room.x1 + 1 and y >= room.y0 and y < room.y1 + 1
end

--- True anywhere in the ground set aside for the rooms: inside one, or in
--- the black between them. Nobody should ever be there outside a room.
function R.ground(x, y)
    local G = C.Rooms
    local cx, cy = R.cellX() * G.cellSize, R.cellY() * G.cellSize
    return x >= cx and x < cx + G.cellSize * G.trains and y >= cy and y < cy + G.cellSize
end

--- Whose room a square is, or would be: the train's number and the car's,
--- for a square inside a room's walls or on the ring they stand on; nil in
--- the black between rooms. Every car's of every train's, built or not.
function R.slot(x, y)
    local G = C.Rooms
    local index = math.floor((x - R.cellX() * G.cellSize) / G.cellSize)
    if index < 0 or index >= G.trains then return nil end
    local dx = x - ((R.cellX() + index) * G.cellSize + G.offset) + 1
    local dy = y - (R.cellY() * G.cellSize + G.offset) + 1
    if dx < 0 or dy < 0 then return nil end
    local col, line = math.floor(dx / G.pitch), math.floor(dy / G.pitch)
    if col >= G.perRow or line >= G.rows then return nil end
    if dx - col * G.pitch >= G.len + 2 or dy - line * G.pitch >= G.wid + 2 then return nil end
    return index, line * G.perRow + col + 1
end

--- The number of a train among a state's routes, from 0, or nil.
function R.indexOf(routes, trainId)
    local n = 0
    for _, route in ipairs(routes) do
        for _, train in ipairs(route.trains) do
            -- A train says which cell is its own: that is never its place
            -- in a list, which changes when a test line is laid or taken up.
            if train.id == trainId then return train.room or n end
            n = n + 1
        end
    end
    return nil
end

return R
