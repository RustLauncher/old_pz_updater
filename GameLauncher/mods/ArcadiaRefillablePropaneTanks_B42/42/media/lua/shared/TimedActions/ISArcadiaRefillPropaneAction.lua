require "TimedActions/ISBaseTimedAction"
require "ArcadiaRefillablePropane_Shared"

ISArcadiaRefillPropaneAction = ISBaseTimedAction:derive("ISArcadiaRefillPropaneAction")

function ISArcadiaRefillPropaneAction:resolveItem()
    if not self.itemId or not self.character then return nil end
    local requestedId = tonumber(self.itemId)
    local items = self.character:getInventory():getAllEvalRecurse(function(item)
        return item and item:getID() == requestedId
    end)
    if items and not items:isEmpty() then return items:get(0) end
    return nil
end

function ISArcadiaRefillPropaneAction:isValid()
    if not self.object or self.object:getObjectIndex() == -1 then return false end
    if not ArcadiaRefillablePropane.isDepotObject(self.object) then return false end
    if not ArcadiaRefillablePropane.isPlayerAdjacent(self.character, self.object) then
        return false
    end

    self.item = self:resolveItem()
    if not self.item or
        not self.character:getInventory():containsRecursive(self.item) then
        return false
    end
    if self.direction == "item_to_depot" then
        return ArcadiaRefillablePropane.isPropaneSourceItem(self.item) and
            ArcadiaRefillablePropane.getDepotMissingUnits(self.object) >
                ArcadiaRefillablePropane.MIN_TRANSFER
    end
    return ArcadiaRefillablePropane.getMissingUnits(self.item) >
            ArcadiaRefillablePropane.MIN_TRANSFER and
        ArcadiaRefillablePropane.getStoredAmount(self.object) >
            ArcadiaRefillablePropane.MIN_TRANSFER
end

function ISArcadiaRefillPropaneAction:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function ISArcadiaRefillPropaneAction:start()
    self.item = self:resolveItem()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    if self.item then
        self.item:setJobType(getText(
            self.direction == "item_to_depot" and
                "UI_RPT_StoreAction" or "UI_RPT_RefillAction"
        ))
        self.item:setJobDelta(0.0)
    end
    self.sound = self.character:playSound("TransferLiquid")
end

function ISArcadiaRefillPropaneAction:update()
    self.character:faceThisObject(self.object)
    if self.item then self.item:setJobDelta(self:getJobDelta()) end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISArcadiaRefillPropaneAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.stop(self)
end

function ISArcadiaRefillPropaneAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.perform(self)
end

function ISArcadiaRefillPropaneAction:complete()
    local server = ArcadiaRefillablePropaneServer
    if not server then return false end
    if self.direction == "item_to_depot" and server.completeItemToDepot then
        return server.completeItemToDepot(
            self.character,
            self.object,
            self.itemId
        )
    end
    if not server.completeTimedAction then return false end
    return server.completeTimedAction(
        self.character,
        self.object,
        self.itemId
    )
end

function ISArcadiaRefillPropaneAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local item = self.item or self:resolveItem()
    local amount = 0
    if item and self.direction == "item_to_depot" then
        amount = math.min(
            ArcadiaRefillablePropane.getItemStoredUnits(item),
            ArcadiaRefillablePropane.getDepotMissingUnits(self.object)
        )
    elseif item then
        amount = math.min(
            ArcadiaRefillablePropane.getMissingUnits(item),
            ArcadiaRefillablePropane.getStoredAmount(self.object)
        )
    end
    return math.min(300, math.max(60, 60 + (amount * 1.5)))
end

function ISArcadiaRefillPropaneAction:new(character, object, item, direction)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.object = object
    action.item = item
    action.itemId = item and item:getID() or nil
    action.direction = direction or "depot_to_item"
    action.maxTime = action:getDuration()
    return action
end
