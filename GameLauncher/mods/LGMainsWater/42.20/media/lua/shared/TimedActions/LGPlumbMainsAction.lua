require "TimedActions/ISBaseTimedAction"
require "LGMainsWater/LGMainsWaterCore"

--- Modelled on ISPlumbItem -- same wrench, same sound, same duration -- but a
--- separate action alongside it, not a replacement. ISPlumbItem attaches a rain
--- collector barrel; this connects the fixture to the building's own supply.
LGPlumbMainsAction = ISBaseTimedAction:derive("LGPlumbMainsAction")

--- How far from the fixture the character may be when the action completes.
---
--- Not a sandbox option: nobody is meant to notice it, and an operator who tuned it
--- could only make it wrong. A timed action ends with the character stood at what
--- they are working on, so this is loose enough never to refuse a real one and tight
--- enough that a fabricated packet cannot name a sink on the other side of town.
local REACH = 8

function LGPlumbMainsAction:isValid()
    return self.character:isEquipped(self.wrench)
end

function LGPlumbMainsAction:update()
    self.character:faceThisObject(self.fixture)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function LGPlumbMainsAction:start()
    self.sound = self.character:playSound("RepairWithWrench")
end

function LGPlumbMainsAction:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function LGPlumbMainsAction:perform()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.perform(self)
end

--- Deliberately does not touch self.sound, and vanilla's ISPlumbItem does not
--- either. On a dedicated server this runs on an action object that never had
--- start() called on it: LuaTimedActionNew.start sends the action to the server
--- (because this class defines complete, so useCustomRemoteTimedActionSync stays
--- false), NetTimedAction.parse builds a *fresh* LGPlumbMainsAction there, and
--- NetTimedAction.perform calls straight into this function. self.sound is nil on
--- that copy, and stopOrTriggerSound takes a primitive long, so handing it nil
--- throws out of Kahlua while unboxing rather than being ignored. The sound is a
--- client-side matter and stop()/perform() above already deal with it.
function LGPlumbMainsAction:complete()
    local fixture = self.fixture
    local square = fixture and fixture:getSquare()
    if not square then return true end

    -- The gate again, here rather than only where the option was offered. In
    -- multiplayer this function is the write, and it runs on the server against
    -- an action the server rebuilt out of a packet -- the fixture came from the
    -- client. Not the whole of canPlumbToMains: its "already connected" half
    -- would reject a legitimate second attempt, and connecting something already
    -- connected does nothing anyway.
    if not LGMainsWater.isPlumbableFixture(fixture) then return true end
    if not LGMainsWater.isInSpawnedBuilding(square) then return true end

    -- And that the player is at the fixture, which is the one thing the two tests
    -- above cannot tell: both are properties of the fixture and neither is a
    -- property of whoever asked.
    --
    -- This matters more here than it looks, because isValid() is NOT re-run on the
    -- server. NetTimedAction.isValid() returns false unconditionally, so
    -- `self.character:isEquipped(self.wrench)` above is a client-side check only,
    -- and until this line the entire trust chain for a packet was two questions
    -- about the sink. A crafted one plumbed any map fixture in Knox County, with no
    -- wrench and no travel.
    --
    -- The wrench is deliberately NOT re-checked here. Doing so would refuse a
    -- legitimate action whenever the equip has not reached the server yet, which
    -- turns an abuse guard into a race, and the effect being guarded is "a sink now
    -- has water" rather than anything that can be duplicated or stolen.
    --
    -- Chebyshev, z ignored, and it FAILS OPEN on a character it cannot place -- the
    -- same trade the sibling mods make, for the same reason: a guard that can break
    -- the thing it guards is worse than no guard.
    local character = self.character
    if character and character.getX and character.getY then
        local px, py = character:getX(), character:getY()
        if type(px) == "number" and type(py) == "number" then
            local reach = math.max(math.abs(math.floor(px) - square:getX()),
                                   math.abs(math.floor(py) - square:getY()))
            if reach > REACH then return true end
        end
    end

    LGMainsWater.plumb(fixture)

    if buildUtil then
        buildUtil.setHaveConstruction(square, true)
    end

    return true
end

function LGPlumbMainsAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return 100
end

function LGPlumbMainsAction:new(character, fixture, wrench)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.fixture = fixture
    o.wrench = wrench
    o.maxTime = o:getDuration()
    return o
end
