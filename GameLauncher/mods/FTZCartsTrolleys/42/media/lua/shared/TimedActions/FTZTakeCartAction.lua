-- FTZ Carts & Trolleys - pick a cart up from the ground straight into both hands.
-- Runs on the server in multiplayer (complete), like the game's own "take generator" action.
require "TimedActions/ISBaseTimedAction"

FTZTakeCartAction = ISBaseTimedAction:derive("FTZTakeCartAction")

function FTZTakeCartAction:isValid()
    local wo = self.worldItem
    if not wo or not wo:getSquare() or not wo:getItem() then return false end
    if not wo:getSquare():getWorldObjects():contains(wo) then return false end
    local mySq = self.character:getSquare()
    if mySq and wo:getSquare():isBlockedTo(mySq) then return false end
    return true
end

function FTZTakeCartAction:waitToStart()
    self.character:faceThisObject(self.worldItem)
    return self.character:shouldBeTurning()
end

function FTZTakeCartAction:update()
    self.character:faceThisObject(self.worldItem)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function FTZTakeCartAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function FTZTakeCartAction:stop()
    ISBaseTimedAction.stop(self)
end

function FTZTakeCartAction:perform()
    ISBaseTimedAction.perform(self)
end

function FTZTakeCartAction:complete()
    local wo = self.worldItem
    local sq = wo and wo:getSquare()
    local item = wo and wo:getItem()
    if not sq or not item then return false end

    if forceDropHeavyItems then forceDropHeavyItems(self.character) end

    sq:transmitRemoveItemFromSquare(wo)
    wo:removeFromWorld()
    wo:removeFromSquare()
    wo:setSquare(nil)
    item:setWorldItem(nil)
    item:setJobDelta(0.0)

    local inv = self.character:getInventory()
    inv:AddItem(item)
    sendAddItemToContainer(inv, item)
    if FTZCarts and FTZCarts.applyCapacity then FTZCarts.applyCapacity(item) end

    self.character:setPrimaryHandItem(item)
    self.character:setSecondaryHandItem(item)
    sendEquip(self.character)
    inv:setDrawDirty(true)
    return true
end

function FTZTakeCartAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 50
end

function FTZTakeCartAction:new(character, worldItem)
    local o = ISBaseTimedAction.new(self, character)
    o.worldItem = worldItem
    o.maxTime = o:getDuration()
    return o
end
