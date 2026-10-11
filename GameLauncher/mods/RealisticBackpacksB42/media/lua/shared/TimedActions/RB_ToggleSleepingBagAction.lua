require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISClothingExtraAction"

RB_ToggleSleepingBagAction = ISBaseTimedAction:derive("RB_ToggleSleepingBagAction")

local PACKED_SLEEPING_BAG = "Base.SleepingBag_Green_Packed"

local ATTACH_TARGETS = {
    ["Base.Assault_Backpack"] = "Base.Assault_Backpack_Mattress",
    ["Base.Assault_Backpack_Black"] = "Base.Assault_Backpack_Mattress_Black",
    ["Base.Assault_Backpack_Green"] = "Base.Assault_Backpack_Mattress_Green",
    ["Base.Assault_Backpack_Camo"] = "Base.Assault_Backpack_Mattress_Camo",
    ["Base.Assault_Backpack_Pidoras"] = "Base.Assault_Backpack_Mattress_Pidoras",
}

local DETACH_TARGETS = {}
for backpackType, sleepingBagType in pairs(ATTACH_TARGETS) do
    DETACH_TARGETS[sleepingBagType] = backpackType
end

local function stopActionSound(action)
    if action.sound and action.character:getEmitter():isPlaying(action.sound) then
        action.character:stopOrTriggerSound(action.sound)
    end
    action.sound = nil
end

function RB_ToggleSleepingBagAction:isValid()
    if not self.item or self.item:isBroken() then
        return false
    end

    if self.item:getFullType() ~= self.sourceType then
        return false
    end

    local inventory = self.character:getInventory()
    if self.item:getContainer() ~= inventory then
        return false
    end

    if self.attach and not inventory:getFirstTypeRecurse(PACKED_SLEEPING_BAG) then
        return false
    end

    return true
end

function RB_ToggleSleepingBagAction:waitToStart()
    return false
end

function RB_ToggleSleepingBagAction:update()
    if self.item then
        self.item:setJobDelta(self:getJobDelta())
    end
end

function RB_ToggleSleepingBagAction:start()
    if isClient() then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end
    if not self.item then
        return
    end

    self.wasWorn = self.character:getClothingItem_Back() == self.item
    self.wasPrimary = self.character:getPrimaryHandItem() == self.item
    self.wasSecondary = self.character:getSecondaryHandItem() == self.item

    self.item:setJobType(self.jobType)
    self.item:setJobDelta(0.0)
    self:setActionAnim("PackSack")
    self.sound = self.character:playSound("CraftPackUnpack")
end

function RB_ToggleSleepingBagAction:serverStart()
    self.wasWorn = self.character:getClothingItem_Back() == self.item
    self.wasPrimary = self.character:getPrimaryHandItem() == self.item
    self.wasSecondary = self.character:getSecondaryHandItem() == self.item
end

function RB_ToggleSleepingBagAction:stop()
    stopActionSound(self)
    if self.item then
        self.item:setJobDelta(0.0)
    end
    ISBaseTimedAction.stop(self)
end

function RB_ToggleSleepingBagAction:perform()
    stopActionSound(self)
    if self.item then
        self.item:setJobDelta(0.0)
    end
    ISBaseTimedAction.perform(self)
end

function RB_ToggleSleepingBagAction:complete()
    if not self:isValid() then
        return false
    end

    local inventory = self.character:getInventory()
    local newItem = instanceItem(self.targetType)
    if not newItem then
        print("[RealisticBackpacksB42] Could not create conversion target: " .. tostring(self.targetType))
        return false
    end

    if self.attach then
        local sleepingBag = inventory:getFirstTypeRecurse(PACKED_SLEEPING_BAG)
        if not sleepingBag or not sleepingBag:getContainer() then
            return false
        end

        local sleepingBagContainer = sleepingBag:getContainer()
        sleepingBagContainer:Remove(sleepingBag)
        sendRemoveItemFromContainer(sleepingBagContainer, sleepingBag)
    end

    self.character:removeFromHands(self.item)
    self.character:removeWornItem(self.item, false)

    -- This is the same Build 42 routine used by vanilla clothing transformations.
    -- For InventoryContainer items it transfers every contained item with takeItemsFrom().
    ISClothingExtraAction:createItemNew(self.item, newItem)

    inventory:Remove(self.item)
    sendRemoveItemFromContainer(inventory, self.item)
    inventory:AddItem(newItem)
    sendAddItemToContainer(inventory, newItem)

    if not self.attach then
        local sleepingBag = inventory:AddItem(PACKED_SLEEPING_BAG)
        if sleepingBag then
            sendAddItemToContainer(inventory, sleepingBag)
        end
    end

    if self.wasWorn and newItem:canBeEquipped() ~= "" then
        self.character:setWornItem(newItem:canBeEquipped(), newItem)
        sendClothing(self.character, newItem:canBeEquipped(), newItem)
    else
        if self.wasPrimary then
            self.character:setPrimaryHandItem(newItem)
        end
        if self.wasSecondary then
            self.character:setSecondaryHandItem(newItem)
        end
        if self.wasPrimary or self.wasSecondary then
            sendEquip(self.character)
        end
    end

    if not isServer() then
        local inventoryPage = getPlayerInventory(self.character:getPlayerNum())
        if inventoryPage then
            inventoryPage:refreshBackpacks()
        end
    end
    syncVisuals(self.character)
    triggerEvent("OnClothingUpdated", self.character)

    return true
end

function RB_ToggleSleepingBagAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return self.attach and 50 or 25
end

function RB_ToggleSleepingBagAction:new(character, item, attach)
    local action = ISBaseTimedAction.new(self, character)
    action.item = item
    action.attach = attach == true
    action.sourceType = item:getFullType()
    action.targetType = action.attach and ATTACH_TARGETS[action.sourceType] or DETACH_TARGETS[action.sourceType]
    if isServer() then
        action.jobType = ""
    else
        action.jobType = getText(action.attach and "ContextMenu_RB_AttachSleepingBag" or "ContextMenu_RB_DetachSleepingBag")
    end
    action.maxTime = action:getDuration()
    action.stopOnWalk = true
    action.stopOnRun = true
    action.stopOnAim = true
    return action
end
