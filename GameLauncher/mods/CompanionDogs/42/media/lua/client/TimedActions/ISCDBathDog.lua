require "TimedActions/ISCDBaseDogAction"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDBathDog = ISCDBaseDogAction:derive("ISCDBathDog")

function ISCDBathDog:isValid()
    return self.character:getInventory():containsRecursive(self.item)
end

function ISCDBathDog:doEffect()
    if self.cdDone then return end
    self.cdDone = true
    self.animal:getBehavior():setBlockMovement(false)
    if not self.character:getInventory():containsRecursive(self.item) then
        return
    end
    CompanionDogs.request("vetbath", self.animal, { itemId = self.item:getID() }, self.character)
end

function ISCDBathDog:new(character, animal, item)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.item = item
    o.handModelItem = item
    o.soundName = "PutItemInBag"
    local frac = 1 - CD.VET_TREAT_DOCTOR_CUT * character:getPerkLevel(Perks.Doctor)
    if frac < CD.VET_TREAT_MIN_FRAC then
        frac = CD.VET_TREAT_MIN_FRAC
    end
    o.cdMaxTicks = math.floor(CD.VET_BATH_TICKS * frac)
    o.cdDuration = o.cdMaxTicks * 2
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
