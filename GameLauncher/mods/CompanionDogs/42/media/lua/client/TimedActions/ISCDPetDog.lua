require "TimedActions/ISCDBaseDogAction"

ISCDPetDog = ISCDBaseDogAction:derive("ISCDPetDog")

function ISCDPetDog:isValid()
    return self.animal:isExistInTheWorld()
end

function ISCDPetDog:start()
    self.animal:getBehavior():setBlockMovement(true)
    if self.animal:isExistInTheWorld() then
        self:setOverrideHandModels(nil, nil)
        self.character:setVariable("AnimalSizeX", 0.01)
        local data = self.animal:getData()
        local range = data:getMaxSize() - data:getMinSize()
        local current = data:getSize() - data:getMinSize()
        if current <= 0.001 then
            current = 0.001
        end
        if range > 0 then
            self.character:setVariable("AnimalSizeY", current / range)
        end
        self.character:setVariable("petanimal", true)
        local pose = "raccoonboar"
        if self.animal:isBaby() then pose = "raccoonkit"
        elseif self.animal:isFemale() then pose = "raccoonsow" end
        self.character:setVariable("animal", pose)
        self.character:faceThisObject(self.animal)
        CompanionDogs.playAnimalSound(self.animal, CompanionDogs.breedVoice(self.animal, "pet"))
    end
end

local function clearPetAnim(self)
    self.character:setVariable("petanimal", false)
end

function ISCDPetDog:stop()
    clearPetAnim(self)
    ISCDBaseDogAction.stop(self)
end

function ISCDPetDog:forceStop()
    clearPetAnim(self)
    ISCDBaseDogAction.forceStop(self)
end

function ISCDPetDog:perform()
    clearPetAnim(self)
    ISCDBaseDogAction.perform(self)
end

function ISCDPetDog:doEffect()
    if self.cdDone then return end
    self.cdDone = true
    clearPetAnim(self)
    self.animal:getBehavior():setBlockMovement(false)
    CompanionDogs.request("pet", self.animal, nil, self.character)
end

function ISCDPetDog:new(character, animal)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.cdMaxTicks = 150
    o.cdDuration = 300
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
