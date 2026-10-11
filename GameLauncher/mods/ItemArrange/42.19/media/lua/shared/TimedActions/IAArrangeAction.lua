require "TimedActions/ISBaseTimedAction"

IAArrangeAction = ISBaseTimedAction:derive("IAArrangeAction")

local CLIENT_DELAY_FOR_MULTI_TRANSACTION = 10
-- keep only one instance of this action so we can queue item to transfer and avoid ton of instance when moving lot of items.

function IAArrangeAction:isValid()
    if not self.item then
        return false
    end
    if not self.dropSquare or not self.srcContainer then
        return false
    end
    if self.character:getSquare():isSomethingTo(self.dropSquare) then
        return false
    end
    if not IA.CheckSpace(self.dropSquare, self.item) then
        return false
    end

    return true
end

function IAArrangeAction:stopLoopingSound()
    if self.loopSound then
        self.character:getEmitter():stopSound(self.loopSound)
        self.loopSound = nil
	end
end

function IAArrangeAction:update()

    self.item:setJobDelta(self.action:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.LightWork)

end

function IAArrangeAction:waitToStart()
    if not isClient() then
        return false
    else
        local timePassed = getTimestampMs() - self.startTime
        return timePassed < CLIENT_DELAY_FOR_MULTI_TRANSACTION
    end
end

function IAArrangeAction:start()
    self:setActionAnim("Loot")
    self.loopSound = self.character:getEmitter():playSound("RummageInInventory")
end

function IAArrangeAction:stop()
    self:stopLoopingSound()
    self.item:setJobDelta(0.0)
    if self.action then
        self.action:setLoopedAction(false)
    end
    ISBaseTimedAction.stop(self)
end

function IAArrangeAction:perform()

    if isServer() then
        return
    end

    self:stopLoopingSound()
    self.item:setJobDelta(0.0)

    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)

    ISInventoryPage.renderDirty = true
end

function IAArrangeAction:complete()
    self.srcContainer:DoRemoveItem(self.item)
    sendRemoveItemFromContainer(self.srcContainer, self.item)
    self.dropSquare:AddWorldInventoryItem(self.item, 0.5, 0.5, 0.0)
    IA.ArrangeItems(self.dropSquare)
    return true
end

function IAArrangeAction:getTimeDelta()
    return 0
end

function IAArrangeAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end

    local time = 120
    local w = self.item:getActualWeight()
    if w > 3 then 
        w = 3
    end
    time = time * (w)

    if self.srcContainer == self.character:getInventory() then
        time = time * 0.1
    elseif self.srcContainer:isInCharacterInventory(self.character) then
        -- Unpack -> drop
    else
        time = time * 0.2
    end

    if self.character:hasTrait(CharacterTrait.DEXTROUS) then
        time = time * 0.5
    end
    if self.character:hasTrait(CharacterTrait.ALL_THUMBS) or self.character:isWearingAwkwardGloves() then
        time = time * 2.0
    end

    return time
end

function IAArrangeAction:new (character, item, srcContainer, dropSquare)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.item = item
    o.srcContainer = srcContainer
    o.dropSquare = dropSquare
    o.startTime = getTimestampMs()
    o.maxTime = o:getDuration()
    return o
end


