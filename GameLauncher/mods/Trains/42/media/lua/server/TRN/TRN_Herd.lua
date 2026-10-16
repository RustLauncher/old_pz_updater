if isClient() then return end

--[[ Trains -- animals aboard (DESIGN.md 12; the author, 2026-10-11: "the
    animal husbandry car should have animals in it - also how can we expect
    to get animals in and out of this?").

    Runs in single player and on any server. Two things:

      * **the livestock car's own animals** (H.stock): vanilla's, made as
        vanilla's own server makes one (IsoAnimal.new, addToWorld: its traps
        and its admin's command), tame, in a livestock zone laid over the
        room (H.zone) so that they know its troughs for theirs;
      * **in and out.** An animal small enough to pick up is a thing in its
        keeper's hands and goes wherever she goes: nothing here is needed
        for it. **An animal on a rope** cannot follow her through a car's
        door, because a door is a move of thousands of squares: so the
        server takes each one out of the world where it stands (H.take, as
        picking one up does: ISPickupAnimal) and makes it again where its
        keeper comes out (H.put, as the engine does for an animal taken out
        of a trailer: BaseVehicle.removeAnimalFromTrailer, a new animal of
        the same kind and breed and `copyFrom` the old), back on her rope.

    Where they come out has not streamed in when they are taken: the room
    is raised round whoever goes in, and the ground beside a train is
    loaded round whoever steps out. So between the two an animal is **held
    by the server, in memory**, for the second or two that takes (H.hold,
    H.tick), and set down beside its keeper wherever she is if its ground
    never comes. **A server that stops in that second or two loses it.**

    **None of this has been seen in the game**, and on a server least of
    all: that clients are told of an animal the server takes out of the
    world this way, and of one it makes, is not read. H.stats and the log
    say how many, each time.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Setup"

TRN = TRN or {}
local C, U = TRN.Config, TRN.Util

local H = {}
TRN.Herd = H

H.stats = { stocked = 0, zones = 0, taken = 0, put = 0, lost = 0, loosed = 0 }
H.waiting = {}          -- username -> { animals = {}, x, y, z, ux, uy, age }

--- True where a square is there to stand on.
local function floored(x, y, z)
    local sq = U.square(x, y, z)
    if not sq then return false end
    return U.try("herd.floor", function() return sq:getFloor() ~= nil end) == true
end

--- An animal of vanilla's, tame, made and put in the world. Returns it.
function H.make(x, y, z, kind, breed)
    return U.try("herd.make", function()
        local a = IsoAnimal.new(getCell(), math.floor(x), math.floor(y), math.floor(z), kind, breed)
        if not a then return nil end
        a:setWild(false)
        a:addToWorld()
        return a
    end)
end

--- The livestock zone over a room, laid once: an animal eats and drinks
--- from the troughs of the zone it stands in. True when one was made now.
function H.zone(room, name)
    local made = U.try("herd.zone", function()
        if DesignationZoneAnimal.getZone(room.x0, room.y0, room.z) then return false end
        DesignationZoneAnimal.new(name, room.x0, room.y0, room.z, room.x1 + 1, room.y1 + 1, true)
        return true
    end) == true
    if made then H.stats.zones = H.stats.zones + 1 end
    return made
end

--- Puts a room's animals in it: { dx, dy, animal, breed } each. Returns how many.
function H.stock(room, animals)
    local n = 0
    for _, a in ipairs(animals or {}) do
        if H.make(room.x0 + a.dx, room.y0 + a.dy, room.z, a.animal, a.breed) then n = n + 1 end
    end
    H.stats.stocked = H.stats.stocked + n
    return n
end

---------------------------------------------------------------------------
-- In and out, on a rope
---------------------------------------------------------------------------
--- How many animals a player has on a rope.
function H.led(player)
    return U.try("herd.led", function() return player:getAttachedAnimals():size() end) or 0
end

--- Lets go of every animal a player leads: each stays where it stands.
--- Returns how many.
function H.loose(player)
    local n = 0
    U.try("herd.loose", function()
        local list = player:getAttachedAnimals()
        for i = list:size() - 1, 0, -1 do
            local a = list:get(i)
            if a then
                list:remove(a)
                a:getData():setAttachedPlayer(nil)
                n = n + 1
            end
        end
    end)
    H.stats.loosed = H.stats.loosed + n
    return n
end

--- Takes the animals a player leads out of the world, `C.Herd.most` of them
--- at most; the rest are let go where they stand. Returns those taken.
function H.take(player)
    local out = {}
    U.try("herd.take", function()
        local list = player:getAttachedAnimals()
        for i = list:size() - 1, 0, -1 do
            local a = list:get(i)
            if a and #out < C.Herd.most then
                list:remove(a)
                a:getData():setAttachedPlayer(nil)
                a:removeFromWorld()
                a:removeFromSquare()
                a:setSquare(nil)
                out[#out + 1] = a
            end
        end
    end)
    H.loose(player)
    H.stats.taken = H.stats.taken + #out
    return out
end

--- Makes each animal again at x, y and along from it, on its keeper's rope.
--- Returns how many came through.
function H.put(animals, player, x, y, z, ux, uy)
    local n = 0
    for i, old in ipairs(animals) do
        local ax, ay = x + (ux or 0) * (i - 1) * C.Herd.spread, y + (uy or 0) * (i - 1) * C.Herd.spread
        if not floored(ax, ay, z) then ax, ay = x, y end
        local made = U.try("herd.put", function()
            local a = IsoAnimal.new(getCell(), math.floor(ax), math.floor(ay), math.floor(z), old:getAnimalType(),
                                    old:getBreed())
            if not a then return nil end
            a:copyFrom(old)
            a:addToWorld()
            return a
        end)
        if made then
            n = n + 1
            if player then
                U.try("herd.rope", function()
                    player:getAttachedAnimals():add(made)
                    made:getData():setAttachedPlayer(player)
                end)
            end
        else
            H.stats.lost = H.stats.lost + 1
            U.warnOnce("herd.lost", "an animal taken through a car's door could not be made again where it came out")
        end
    end
    H.stats.put = H.stats.put + n
    return n
end

--- Animals taken, kept until the place they come out at is there: x, y is
--- the first one's, and each after it is `ux, uy` further on.
function H.hold(who, animals, x, y, z, ux, uy)
    if #animals == 0 then return end
    local was = H.waiting[who]
    if was then
        -- Still holding some from the door before: they come out with these.
        for _, a in ipairs(was.animals) do animals[#animals + 1] = a end
    end
    H.waiting[who] = { animals = animals, x = x, y = y, z = z, ux = ux or 0, uy = uy or 0, age = 0 }
end

--- Sets down whatever is held whose ground has come; and beside its keeper,
--- wherever she is, whatever has waited too long. Called now and then.
function H.tick(every)
    for who, w in pairs(H.waiting) do
        local keeper = nil
        for _, p in ipairs(U.players()) do
            if U.username(p) == who then keeper = p end
        end
        w.age = w.age + (every or 1)
        if w.age > C.Herd.giveUp and keeper then
            local at = U.try("herd.keeper", function()
                return { x = keeper:getX(), y = keeper:getY(), z = math.floor(keeper:getZ()) }
            end)
            if at and floored(at.x, at.y, at.z) then
                w.x, w.y, w.z, w.ux, w.uy = at.x, at.y, at.z, 0, 0
                U.log("WARN herd: the ground %s's animals were to come out on never came; they are set down beside her",
                      tostring(who))
            end
        end
        if floored(w.x, w.y, w.z) then
            H.waiting[who] = nil
            local n = H.put(w.animals, keeper, w.x, w.y, w.z, w.ux, w.uy)
            U.log("herd: %d of %s's %d animal(s) came through, at %.1f,%.1f", n, tostring(who), #w.animals, w.x, w.y)
        end
    end
end

--- What this machine has done with animals, for TRN_Status().
function H.status()
    local held = 0
    for _, w in pairs(H.waiting) do held = held + #w.animals end
    U.log("status: herd: %d animal(s) put in stables, %d zone(s) laid; on a rope: %d taken through a door, %d set down, "
          .. "%d held now, %d lost, %d let go; the sandbox's Animals: %s, Lead: %s", H.stats.stocked, H.stats.zones,
          H.stats.taken, H.stats.put, held, H.stats.lost, H.stats.loosed, TRN.Setup.animals(),
          tostring(TRN.Setup.on("Lead")))
end

return H
