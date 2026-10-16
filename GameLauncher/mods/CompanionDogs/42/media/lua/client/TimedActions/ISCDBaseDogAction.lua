require "TimedActions/ISBaseTimedAction"

ISCDBaseDogAction = ISBaseTimedAction:derive("ISCDBaseDogAction")

function ISCDBaseDogAction:isValid()
    return true
end

function ISCDBaseDogAction:waitToStart()
    if self.animal:isExistInTheWorld() then
        self.character:faceThisObject(self.animal)
    end
    return self.character:shouldBeTurning()
end

function ISCDBaseDogAction:update()
    if self.animal:isExistInTheWorld() then
        self.character:faceThisObject(self.animal)
    end
    self.cdTicks = (self.cdTicks or 0) + 1
    if self.cdTicks >= self.cdMaxTicks and not self.cdDone then
        self:doEffect()
        self:forceComplete()
    end
end

function ISCDBaseDogAction:start()
    self.animal:getBehavior():setBlockMovement(true)
    if self.animal:isExistInTheWorld() then
        self:setActionAnim(self.animal:getFeedByHandAnim())
        if self.handModelItem then
            self:setOverrideHandModels(self.handModelItem, nil)
        end
        self.character:faceThisObject(self.animal)
    end
    if self.soundName then
        self.sound = self.character:playSound(self.soundName)
    end
end

function ISCDBaseDogAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
end

local function release(self)
    self.animal:getBehavior():setBlockMovement(false)
    self:stopSound()
end

function ISCDBaseDogAction:stop()
    release(self)
    ISBaseTimedAction.stop(self)
end

function ISCDBaseDogAction:forceStop()
    release(self)
    ISBaseTimedAction.forceStop(self)
end

function ISCDBaseDogAction:perform()
    self:doEffect()
    release(self)
    ISBaseTimedAction.perform(self)
end

-- Sem complete(): o rawget do Kahlua sobe a metatable, entao definir aqui vaza pra toda subclasse
-- e o LuaTimedActionNew opta pelo net-action sync, q o dedicado rejeita (sem media/lua/client).

function ISCDBaseDogAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.cdDuration or 150
end

function ISCDBaseDogAction:doEffect() end
