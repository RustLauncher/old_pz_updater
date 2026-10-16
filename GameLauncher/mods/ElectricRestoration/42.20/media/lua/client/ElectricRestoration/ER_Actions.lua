require "ElectricRestoration/ER_Core"
require "ElectricRestoration/ER_Requirements"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISInventoryTransferUtil"
function ER.request(command,target,extra)
 local args=extra or {};local player=args.player or getPlayer();args.player=nil
 if target then args.target=target.id;args.x=target.x;args.y=target.y;args.z=target.z end
 if isClient() then sendClientCommand("ER",command,args) elseif ER.Server then ER.Server.command(command,player,args) end
end
ER.Action=ISBaseTimedAction:derive("ERRepairAction")
local A=ER.Action
function A:isValid()
 if self.command=="manual" then return self.item and self.character:getInventory():contains(self.item) end
 local t=self.target
 if self.character:getZ()~=t.z or (self.character:getX()-t.x)^2+(self.character:getY()-t.y)^2>9 then return false end
 local state=ER.State or {};local node=t.kind=="machine" and (state.machines or {})[t.index] or (t.id=="dispatch" and state.dispatch or (state.terminals or {})[t.id])
 return node and node.revision==self.expected and ER.Requirements.check(self.character,state,t,self.command)
end
function A:start()
 if self.command=="manual" then
  self.item:setJobType(getText("IGUI_ER_Read"));self.item:setJobDelta(0)
  self:setAnimVariable("ReadType","book");self:setOverrideHandModels(nil,self.item)
  self:setActionAnim(CharacterActionAnims.Read);self.character:setReading(true)
  self.character:reportEvent("EventRead");self.character:playSound("OpenBook");return
 end
 if self.target then self.character:faceLocation(self.target.x,self.target.y) end
 self:setActionAnim(self.command=="manual" and "Read" or "Loot")
 if self.tool then self:setOverrideHandModels(self.tool:getStaticModel(),nil) end
 if self.command=="repair" then self.sound=self.character:playSound("GeneratorRepair") end
end
function A:update()
 if self.item then self.item:setJobDelta(self:getJobDelta()) end
 if self.target then self.character:faceLocation(self.target.x,self.target.y) end
end
function A:cleanup()
 if self.sound then self.character:stopOrTriggerSound(self.sound);self.sound=nil end
 if self.item then self.character:setReading(false);self.item:setJobDelta(0);self.character:playSound("CloseBook") end
end
function A:stop() self:cleanup();ISBaseTimedAction.stop(self) end
function A:apply()
 if self.applied then return end;self.applied=true
 ER.request(self.command,self.target,{expected=self.expected,player=self.character})
end
function A:complete() self:apply();return true end
function A:perform() self:cleanup();self:apply();ISBaseTimedAction.perform(self) end
function A:new(player,target,command,expected,tool)
 local o=ISBaseTimedAction.new(self,player);o.target=target;o.command=command;o.expected=expected;o.tool=tool
 o.maxTime=command=="manual" and 800 or (command=="repair" and 450 or 180);o.stopOnWalk=true;o.stopOnRun=true;return o
end
function ER.queue(player,target,command)
 local state=ER.State or {};local expected;local tool
 if target then
  local ok,rows=ER.Requirements.check(player,state,target,command)
  if not ok then player:Say(ER.Requirements.missing(rows));return false end
 end
 if target then
  local node=target.kind=="machine" and (state.machines or {})[target.index] or (target.id=="dispatch" and state.dispatch or (state.terminals or {})[target.id])
  if not node then return end;expected=node.revision
  if command=="repair" then
   tool=player:getInventory():getFirstTypeRecurse(target.kind=="machine" and "Wrench" or "Screwdriver")
   if not tool then player:Say(getText("IGUI_ER_Materials"));return end
   if tool:getContainer()~=player:getInventory() then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player,tool,tool:getContainer(),player:getInventory())) end
   if player:getPrimaryHandItem()~=tool then ISTimedActionQueue.add(ISEquipWeaponAction:new(player,tool,25,true,false)) end
  end
 end
 local action=A:new(player,target,command,expected,tool)
 if command=="manual" then
  local item=ER.Requirements.items(player:getInventory(),"ERManual")[1]
  if not item then player:Say(getText("IGUI_ER_NeedManual"));return false end
  if item:getContainer()~=player:getInventory() then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player,item,item:getContainer(),player:getInventory())) end
  action.item=item
 end
 ISTimedActionQueue.add(action);return true
end
