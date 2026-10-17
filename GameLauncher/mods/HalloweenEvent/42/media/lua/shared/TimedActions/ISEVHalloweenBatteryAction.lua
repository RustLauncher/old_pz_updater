-- B42 timed action: perform clears the client queue; complete mutates items on
-- the authoritative side. It never turns a partially used battery into a full one.
require "TimedActions/ISBaseTimedAction"
require "HalloweenEvent/EVHalloween_ItemFunctions"
ISEVHalloweenBatteryAction = ISBaseTimedAction:derive("ISEVHalloweenBatteryAction")

function ISEVHalloweenBatteryAction:isValid()
    local inventory = self.character:getInventory()
    return self.lantern and self.battery
        and self.lantern:getFullType() == HalloweenEvent.Items.lanternType
        and self.battery:getFullType() == "Base.Battery"
        and self.lantern:getContainer() == inventory
        and self.battery:getContainer() == inventory
        and self.battery:getCurrentUsesFloat() > 0
end

function ISEVHalloweenBatteryAction:update()
    if not isServer() then self.lantern:setJobDelta(self:getJobDelta()) end
end

function ISEVHalloweenBatteryAction:start()
    self.lantern:setJobType(HalloweenEvent.text("ReplaceBattery"))
    self:setActionAnim("Loot")
    self:setAnimVariable("LootPosition", "Mid")
    self:setOverrideHandModels(nil, nil)
end

function ISEVHalloweenBatteryAction:stop()
    self.lantern:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function ISEVHalloweenBatteryAction:perform()
    self.lantern:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function ISEVHalloweenBatteryAction:complete()
    if isClient() and not isServer() then return false end
    if not self:isValid() then return false end
    local inventory = self.character:getInventory()
    HalloweenEvent.Items.Functions.stepFuel(self.lantern,getGameTime():getWorldAgeHours())
    local oldCharge = math.max(0, math.min(1, self.lantern:getCurrentUsesFloat()))
    local newCharge = math.max(0, math.min(1, self.battery:getCurrentUsesFloat()))
    -- Prepare the returned battery before removing anything.
    local returned
    if oldCharge > 0.0001 then
        returned = instanceItem("Base.Battery")
        if not returned then return false end
        returned:setCurrentUsesFloat(oldCharge)
    end
    self.lantern:setActivated(false)
    inventory:DoRemoveItem(self.battery)
    self.lantern:setCurrentUsesFloat(newCharge)
    self.lantern:setJobDelta(0)
    if returned then inventory:AddItem(returned) end
    if isServer() then
        sendRemoveItemFromContainer(inventory, self.battery)
        if returned then sendAddItemToContainer(inventory, returned) end
        sendItemStats(self.lantern)
    end
    HalloweenEvent.Items.Functions.state(self.lantern).lastHours=getGameTime():getWorldAgeHours()
    HalloweenEvent.Items.Functions.visual(self.lantern)
    if HalloweenEvent.Items.Runtime then HalloweenEvent.Items.Runtime.publish(self.lantern,self.character) end
    HalloweenEvent.log("ITEMS BATTERY_REPLACED charge=" .. tostring(newCharge)
        .. " returnedCharge=" .. tostring(oldCharge))
    return true
end

function ISEVHalloweenBatteryAction:getDuration()
    return self.character:isTimedActionInstant() and 1 or 80
end

function ISEVHalloweenBatteryAction:new(character, lantern, battery)
    local o = ISBaseTimedAction.new(self, character)
    o.lantern = lantern
    o.battery = battery
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
