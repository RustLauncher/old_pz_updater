require "TimedActions/ISBaseTimedAction"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDFillDish = ISBaseTimedAction:derive("ISCDFillDish")

function ISCDFillDish:isValid()
    if not self.item then return true end
    return self.character:getInventory():containsRecursive(self.item)
end

function ISCDFillDish:start()
    self:setActionAnim(CD.FEED_BY_HAND_ANIM)
    if self.item then
        self:setOverrideHandModels(self.item, nil)
    end
    self.sound = self.character:playSound("PutItemInBag")
end

function ISCDFillDish:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
end

function ISCDFillDish:doFill()
    if self.cdDone then return end
    self.cdDone = true
    if self.item and not self.character:getInventory():containsRecursive(self.item) then return end
    local args = { x = self.x, y = self.y, z = self.z, dishId = self.dishId }
    if self.item then
        args[self.argKey or "foodId"] = self.item:getID()
    end
    CD.request(self.command, nil, args, self.character)
end

function ISCDFillDish:update()
    self.cdTicks = (self.cdTicks or 0) + 1
    if self.cdTicks >= self.cdMaxTicks and not self.cdDone then
        self:doFill()
        self:forceComplete()
    end
end

function ISCDFillDish:forceStop()
    self:stopSound()
    ISBaseTimedAction.forceStop(self)
end

function ISCDFillDish:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function ISCDFillDish:perform()
    self:doFill()
    self:stopSound()
    ISBaseTimedAction.perform(self)
end

-- Sem complete(): ver ISCDBaseDogAction.

function ISCDFillDish:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return 150
end

function ISCDFillDish:new(character, x, y, z, item, command, argKey, dishId)
    local o = ISBaseTimedAction.new(self, character)
    o.x, o.y, o.z = x, y, z
    o.item = item
    o.dishId = dishId
    o.command = command or "dishaddfood"
    o.argKey = argKey or "foodId"
    o.maxTime = o:getDuration()
    o.cdMaxTicks = 75
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
