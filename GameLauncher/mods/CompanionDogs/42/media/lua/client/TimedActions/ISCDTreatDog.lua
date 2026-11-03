require "TimedActions/ISCDBaseDogAction"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDTreatDog = ISCDBaseDogAction:derive("ISCDTreatDog")

function ISCDTreatDog:isValid()
    return self.character:getInventory():containsRecursive(self.bandage)
end

function ISCDTreatDog:doEffect()
    if self.cdDone then return end
    self.cdDone = true
    self.animal:getBehavior():setBlockMovement(false)
    local inv = self.character:getInventory()
    if not inv:containsRecursive(self.bandage) then
        return
    end
    local args = { bandageId = self.bandage:getID() }
    if self.disinfect and inv:containsRecursive(self.disinfect) then
        args.disinfectId = self.disinfect:getID()
    end
    CompanionDogs.request("vettreat", self.animal, args, self.character)
end

function ISCDTreatDog:new(character, animal, bandage, disinfect)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.bandage = bandage
    o.disinfect = disinfect
    o.handModelItem = bandage
    o.soundName = "PutItemInBag"
    local frac = 1 - CD.VET_TREAT_DOCTOR_CUT * character:getPerkLevel(Perks.Doctor)
    if frac < CD.VET_TREAT_MIN_FRAC then
        frac = CD.VET_TREAT_MIN_FRAC
    end
    o.cdMaxTicks = math.floor(CD.VET_TREAT_TICKS * frac)
    o.cdDuration = o.cdMaxTicks * 2
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
