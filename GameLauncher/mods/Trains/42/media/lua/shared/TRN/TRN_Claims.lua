--[[ Trains -- whose train it is (DESIGN.md 5.8, SERVERS.md).

    Everywhere, and it only reads. A player aboard a train may make it
    their own, up to as many as the host allows (sandbox `Claims`, one as
    the mod comes; none, and nobody owns anything). Its owner may then:

      * **lock a car**, or every car: nobody else goes in by its doors;
      * **close the train**: nobody else boards it, and anybody else aboard
        is put off the next time it stands;
      * give it up.

    An admin passes every lock and may end anybody's claim.

    **The server decides all of it** (TRN_Server: `claim`, `unclaim`,
    `lock`, `close`, and the checks in `board` and `enter`). The claims are
    part of the state and go to every client with it, so that a menu can
    grey what would be refused and say whose the train is:

        state.claims[train id] = { who = username, closed = true or nil,
                                   cars = { s<slot> = true }, made = <Setup.cars()> }

    **A lock is on a car's slot, not its place** (TRN_Time.slotOf): more
    empties or fewer move no lock. And it is kept with what the trains were
    made of when it was set (`made`): when a host changes that, every car is
    another car, and a lock written for the old ones is nobody's.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Setup"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"

TRN = TRN or {}
local U, K = TRN.Util, TRN.Clock

local Cl = {}
TRN.Claims = Cl

--- How many trains a player may own here. None: nobody owns a train, and
--- whatever was claimed is in nobody's way.
function Cl.most()
    return TRN.Setup.claims()
end

--- The claim on a train, or nil: nobody's, or the host has no owning.
function Cl.of(trainId)
    if Cl.most() < 1 then return nil end
    local s = K.state
    local c = s and s.claims and trainId and s.claims[trainId] or nil
    if type(c) ~= "table" or type(c.who) ~= "string" then return nil end
    return c
end

--- Every train this player owns, by its id, in order. One that is not
--- running now (the host thinned the fleet) is still theirs, and counts.
function Cl.owned(who)
    local out = {}
    local s = K.state
    if not who or not s or type(s.claims) ~= "table" or Cl.most() < 1 then return out end
    for id, c in pairs(s.claims) do
        if type(c) == "table" and c.who == who then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

--- What a car's lock is kept under: its slot.
function Cl.key(slot)
    return "s" .. string.format("%d", slot)
end

--- True for a car its train's owner has locked.
function Cl.locked(trainId, slot)
    local c = Cl.of(trainId)
    if not c or not slot or type(c.cars) ~= "table" or c.made ~= TRN.Setup.cars() then return false end
    return c.cars[Cl.key(slot)] == true
end

--- True where any car of this train is locked.
function Cl.anyLocked(trainId)
    local c = Cl.of(trainId)
    if not c or type(c.cars) ~= "table" or c.made ~= TRN.Setup.cars() then return false end
    for _, on in pairs(c.cars) do
        if on == true then return true end
    end
    return false
end

--- True for a train its owner has closed to everybody else.
function Cl.closed(trainId)
    local c = Cl.of(trainId)
    return c ~= nil and c.closed == true
end

--- True for somebody a train's locks are not for: its owner, an admin, or
--- anybody where it is nobody's. **Asked of this machine's copy of the
--- player** (TRN_Util.admin): the server asks its own.
function Cl.free(player, trainId)
    local c = Cl.of(trainId)
    if not c or c.who == U.username(player) then return true end
    return U.admin(player)
end

return Cl
