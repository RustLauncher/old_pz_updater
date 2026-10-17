require "TimedActions/ISBaseTimedAction"
require "HalloweenEvent/EVHalloween_Items"
local Items=HalloweenEvent.Items
ISEVHalloweenConvertCoffinAction=ISBaseTimedAction:derive("ISEVHalloweenConvertCoffinAction")

function ISEVHalloweenConvertCoffinAction:isValid()
    return self.item and self.item:getFullType()==Items.legacyCoffinType
        and self.item:getContainer()==self.character:getInventory()
        and self.item:getInventory():getItems():size()==0
        and not self.character:isEquipped(self.item)
end
function ISEVHalloweenConvertCoffinAction:start()
    self:setActionAnim("Loot");self:setAnimVariable("LootPosition","Mid")
    self:setOverrideHandModels(nil,nil)
end
function ISEVHalloweenConvertCoffinAction:perform()
    ISBaseTimedAction.perform(self)
end
function ISEVHalloweenConvertCoffinAction:complete()
    if isClient() and not isServer() then return false end
    if not self:isValid() then return false end
    local inv=self.character:getInventory()
    local replacement=instanceItem(Items.coffinType)
    if not replacement or replacement:getWorldSprite()~="evh_coffins_01_0" then return false end
    -- No serialization class changes, automatic content moves, or client-side
    -- deletions. Build the furniture successfully before touching the old bag.
    replacement:setCondition(self.item:getCondition())
    replacement:setFavorite(self.item:isFavorite())
    replacement:copyModData(self.item:getModData())
    local added=inv:AddItem(replacement)
    if not added then return false end
    inv:DoRemoveItem(self.item)
    if isServer() then
        sendAddItemToContainer(inv,replacement)
        sendRemoveItemFromContainer(inv,self.item)
    end
    HalloweenEvent.log("ITEMS COFFIN_CONVERTED oldID="..tostring(self.item:getID())
        .." newID="..tostring(replacement:getID()).." empty=true nativeFurniture=true")
    return true
end
function ISEVHalloweenConvertCoffinAction:getDuration()
    return self.character:isTimedActionInstant() and 1 or 30
end
function ISEVHalloweenConvertCoffinAction:new(character,item)
    local o=ISBaseTimedAction.new(self,character)
    o.item=item;o.stopOnWalk=true;o.stopOnRun=true;o.maxTime=o:getDuration()
    return o
end
