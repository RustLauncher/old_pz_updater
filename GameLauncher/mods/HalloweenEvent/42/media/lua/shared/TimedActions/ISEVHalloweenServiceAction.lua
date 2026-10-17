require "TimedActions/ISBaseTimedAction"
require "HalloweenEvent/EVHalloween_ItemFunctions"
local F=HalloweenEvent.Items.Functions
ISEVHalloweenServiceAction=ISBaseTimedAction:derive("ISEVHalloweenServiceAction")

function ISEVHalloweenServiceAction:isValid()
    local inv=self.character:getInventory()
    if not self.item or self.item:getContainer()~=inv then return false end
    local ft=self.item:getFullType()
    if self.mode=="RemoveBulb" then return ft==HalloweenEvent.Items.lanternType and F.state(self.item).bulbLife>0 end
    if not self.supply or self.supply:getContainer()~=inv then return false end
    if self.mode=="Bulb" then
        return ft==HalloweenEvent.Items.lanternType and self.supply:getFullType():match("^Base%.LightBulb")~=nil
            and self.supply:getCondition()>0
    end
    return self.mode=="Candle" and F.isCandle(self.item) and self.supply:getFullType()=="Base.Candle"
        and self.supply:getCurrentUsesFloat()>0
end
function ISEVHalloweenServiceAction:update() if not isServer() then self.item:setJobDelta(self:getJobDelta()) end end
function ISEVHalloweenServiceAction:start()
    self.item:setJobType(self.mode=="Candle" and HalloweenEvent.text("ReplaceCandle") or HalloweenEvent.text("ServiceBulb"))
    self:setActionAnim("Loot");self:setAnimVariable("LootPosition","Mid");self:setOverrideHandModels(nil,nil)
end
function ISEVHalloweenServiceAction:stop() self.item:setJobDelta(0);ISBaseTimedAction.stop(self) end
function ISEVHalloweenServiceAction:perform() self.item:setJobDelta(0);ISBaseTimedAction.perform(self) end
function ISEVHalloweenServiceAction:complete()
    if isClient() and not isServer() then return false end
    if not self:isValid() then return false end
    local inv=self.character:getInventory()
    F.stepFuel(self.item,getGameTime():getWorldAgeHours())
    local state=F.state(self.item)
    local returned
    if self.mode=="RemoveBulb" or self.mode=="Bulb" then
        if state.bulbLife>0 then
            returned=instanceItem(state.bulbType or "Base.LightBulb")
            if not returned then return false end
            returned:setCondition(math.floor(returned:getConditionMax()*state.bulbLife))
        end
        state.bulbLife=self.mode=="RemoveBulb" and 0 or self.supply:getCondition()/math.max(1,self.supply:getConditionMax())
        if self.supply then state.bulbType=self.supply:getFullType() end
    else
        -- Preserve remaining wax on both sides of a swap.
        local charge=F.charge(self.item)
        if charge>0 then
            returned=instanceItem("Base.Candle");if not returned then return false end
            returned:setCurrentUsesFloat(charge)
        end
        F.setCharge(self.item,self.supply:getCurrentUsesFloat())
    end
    self.item:setActivated(false);state.lastHours=getGameTime():getWorldAgeHours()
    if self.supply then inv:DoRemoveItem(self.supply) end
    if returned then inv:AddItem(returned) end
    if isServer() then
        if self.supply then sendRemoveItemFromContainer(inv,self.supply) end
        if returned then sendAddItemToContainer(inv,returned) end
    end
    F.visual(self.item)
    if HalloweenEvent.Items.Runtime then HalloweenEvent.Items.Runtime.publish(self.item,self.character) end
    HalloweenEvent.log("ITEMS LIGHT_SERVICE type="..self.item:getFullType().." mode="..self.mode
        .." bulb="..tostring(state.bulbLife).." charge="..tostring(F.charge(self.item)))
    return true
end
function ISEVHalloweenServiceAction:getDuration() return self.character:isTimedActionInstant() and 1 or 80 end
function ISEVHalloweenServiceAction:new(character,item,mode,supply)
    local o=ISBaseTimedAction.new(self,character)
    o.item,o.mode,o.supply=item,mode,supply;o.stopOnWalk=true;o.stopOnRun=true;o.maxTime=o:getDuration()
    return o
end
