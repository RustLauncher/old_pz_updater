require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISInventoryTransferUtil"
require "WaterRestoration/WR_Power"
local P=WR.Power
local function text(k) return getText("IGUI_WR_Gen_"..k) end
WR.GeneratorAction=ISBaseTimedAction:derive("WRGeneratorAction")
local A=WR.GeneratorAction
function A:isValid()
 if not P.near(self.character,self.target) then return false end
 return ((((WR.ClientState or {}).revisions or {}).generator or 0)==self.revision)
end
function A:start()
 self:setActionAnim(self.command=="fuelGenerator" and "refuelgascan" or "Loot")
 if self.item then self:setOverrideHandModels(self.item:getStaticModel(),nil) end
 self.character:faceLocation(self.target.x,self.target.y)
 self.sound=self.character:playSound(self.command=="fuelGenerator" and "GeneratorAddFuel" or (self.command=="startGenerator" and "GeneratorStarting" or "WR_ComputerRepair"))
end
function A:update() self.character:faceLocation(self.target.x,self.target.y) end
function A:stop() if self.sound then self.character:stopOrTriggerSound(self.sound) end;ISBaseTimedAction.stop(self) end
function A:apply()
 if self.applied then return end;self.applied=true
 local a={target="generator",x=self.target.x,y=self.target.y,z=0,expectedRevision=self.revision,itemId=self.item and self.item:getID()}
 if isClient() then sendClientCommand("WR",self.command,a) else WR.Server.handleCommand(self.command,self.character,a) end
end
function A:complete() self:apply();return true end
function A:perform() if self.sound then self.character:stopOrTriggerSound(self.sound) end;self:apply();ISBaseTimedAction.perform(self) end
function A:new(player,target,command,item)
 local o=ISBaseTimedAction.new(self,player);o.target=target;o.command=command;o.item=item
 o.revision=((((WR.ClientState or {}).revisions or {}).generator) or 0)
 o.maxTime=(command=="repairGenerator" or command=="serviceGenerator") and 450 or 100;o.stopOnWalk=true;o.stopOnRun=true;return o
end
WR.GeneratorPanel=ISPanel:derive("WRIndustrialGeneratorPanel")
local G=WR.GeneratorPanel
function G:close() self:removeFromUIManager();if G.instance==self then G.instance=nil end end
function G.queue(player,target,command)
 local self={player=player,target=target,close=function() if G.instance then G.instance:close() end end};local item
 if command=="fuelGenerator" then item=P.findFuel(self.player);if not item then WR.showResult(self.player,"NeedPetrol");return end end
 if command=="repairGenerator" or command=="serviceGenerator" then
  if not P.repairReady(self.player,command=="serviceGenerator") then WR.showResult(self.player,"GeneratorRequirements");return end
  item=self.player:getInventory():getFirstTypeRecurse("Wrench")
 end
 if item then
  if item:getContainer()~=self.player:getInventory() then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(self.player,item,item:getContainer(),self.player:getInventory())) end
  if self.player:getPrimaryHandItem()~=item then ISTimedActionQueue.add(ISEquipWeaponAction:new(self.player,item,25,true,false)) end
 end
 ISTimedActionQueue.add(A:new(self.player,self.target,command,item));self:close()
end
function G:createChildren() ISPanel.createChildren(self);self.buttons={} end
function G:isKeyConsumed(key) return key==Keyboard.KEY_ESCAPE end
function G:onKeyRelease(key) if key==Keyboard.KEY_ESCAPE then self:close() end end
function G:onRightMouseUp() self:close();return true end
function G:rounded(x,y,w,h,r,red,green,blue)
 self:drawRect(x+r,y,w-2*r,h,1,red,green,blue)
 for row=0,r-1 do
  local inset=r-math.sqrt(math.max(0,r*r-(r-row-.5)^2))
  self:drawRect(x+inset,y+row,w-2*inset,1,1,red,green,blue)
  self:drawRect(x+inset,y+h-row-1,w-2*inset,1,1,red,green,blue)
 end
 self:drawRect(x,y+r,w,h-2*r,1,red,green,blue)
end
function G.addContext(context,player,target)
 if (WR.ClientState or {}).originalService then return end
 local g=(WR.ClientState or {}).generator or {}
 local function option(label,command,enabled,tip)
  local o=context:addOption(text(label),player,function(p,t,c) G.queue(p,t,c) end,target,command)
  o.notAvailable=not enabled
  if tip then local tooltip=ISWorldObjectContextMenu.addToolTip();tooltip.description=tip;o.toolTip=tooltip end
 end
 local function repairTip(service)
  local inv=player:getInventory();local lines={}
  local function row(key,have,need)
   local ok=type(have)=="boolean" and have or type(have)=="number" and have>=need
   local value=type(have)=="boolean" and getText(have and "IGUI_WR_Yes" or "IGUI_WR_No") or tostring(have).." / "..need
   lines[#lines+1]=(ok and " <RGB:0.6,0.9,0.6> " or " <RGB:1,0.4,0.4> ")..getText(key).." "..value
  end
  row("IGUI_WR_Electricity",player:getPerkLevel(Perks.Electricity),5)
  row("IGUI_WR_Mechanics",player:getPerkLevel(Perks.Mechanics),5)
  row("IGUI_WR_ElectronicsScrap",WR.countElectronicScrap(inv),service and 2 or 10)
  if not service then row("IGUI_WR_MetalBars",#WR.itemsOfType(inv,"MetalBar"),4) end
  row("IGUI_WR_Screwdriver",inv:containsTypeRecurse("Screwdriver"))
  row("IGUI_WR_Gen_Wrench",inv:containsTypeRecurse("Wrench"))
  row("IGUI_WR_ManualRead",player:getModData().WRManualRead==true)
  return table.concat(lines," <LINE> ")
 end
 if not g.repaired then option("Repair","repairGenerator",P.repairReady(player,false),repairTip(false))
 else
  option("Fuel","fuelGenerator",not g.running and (g.fuel or 0)<80 and P.findFuel(player)~=nil,text("RefuelHelp"))
  if g.running then option("Stop","stopGenerator",true)
  else option("Start","startGenerator",(g.fuel or 0)>=20 and (g.condition or 0)>0,getText("IGUI_WR_Result_GeneratorMinimum")) end
  if (g.condition or 0)<99.99 then option("Service","serviceGenerator",not g.running and P.repairReady(player,true),repairTip(true)) end
 end
end
function G:label(t,x,y,font,r,g,b) self:drawText(t,x,y,r or .86,g or .87,b or .88,1,font or UIFont.Small) end
function G:prerender()
 ISPanel.prerender(self)
 local state=WR.ClientState or {};local g=state.generator or {};local fuel=g.fuel or 0;local condition=g.condition or 0
 self:rounded(10,10,self.width-20,self.height-20,24,.48,.50,.52)
 self:rounded(13,13,self.width-26,self.height-26,22,.28,.30,.32)
 self:rounded(22,67,self.width-44,360,16,.16,.18,.20)
 for _,x in ipairs({20,self.width-28}) do for _,y in ipairs({28,self.height-36}) do self:drawRect(x,y,8,8,1,.64,.64,.51);self:drawRect(x+1,y+3,6,2,1,.16,.18,.14) end end
 self:label(text("Title"),38,28,UIFont.Medium);self:label("IG-80 / AUXILIARY POWER",38,51)
 -- Analog dial: 240-degree scale, individual ticks and a red start threshold.
 local cx,cy,r=220,250,137
 for i=0,180 do local a=math.rad(150+i*240/180);local x=cx+math.cos(a)*r;local y=cy+math.sin(a)*r
  self:drawRect(x,y,3,3,1,.64,.67,.70)
 end
 for i=0,16 do local a=math.rad(150+i*15);local color=i<=4 and {.85,.34,.23} or {.78,.80,.82}
  for d=120,134 do self:drawRect(cx+math.cos(a)*d,cy+math.sin(a)*d,2,2,1,color[1],color[2],color[3]) end
 end
 local a=math.rad(150+240*math.min(1,fuel/P.CAPACITY));for d=0,112 do self:drawRect(cx+math.cos(a)*d,cy+math.sin(a)*d,3,3,1,.94,.66,.27) end
 self:drawRect(cx-6,cy-6,12,12,1,.72,.75,.78)
 self:label(text("Empty"),64,330);self:label(text("Full"),304,330)
 self:label(string.format("%02d / 80 L",math.floor(fuel)),169,303,UIFont.Medium)
 self:label(text("Minimum"),72,365)
 -- Small Casio-style LCD is embedded in the physical panel.
 self:rounded(423,109,309,130,12,.08,.09,.10);self:rounded(433,119,289,110,6,.57,.62,.55)
 self:label(text("Remaining"),447,129,nil,.13,.19,.10)
 local hours=P.hours({fuel=fuel});self:label(string.format("%02d d  %02d h",math.floor(hours/24),math.floor(hours%24)),447,160,UIFont.Large,.10,.16,.08)
 self:label(text("Consumption"),447,203,nil,.13,.19,.10)
 local on=g.running and fuel>0 and condition>0
 self:drawRect(428,269,14,14,1,on and .35 or .6,on and .83 or .2,.2)
 self:label(text(on and "Running" or "Stopped"),454,267,UIFont.Medium)
 self:label(text("Condition").." "..math.floor(condition).."%",428,305)
 self:drawRect(428,331,292,11,1,.06,.08,.06);self:drawRect(430,333,288*condition/100,7,1,.48,.68,.35)
 self:label(text(g.repaired and "Ready" or "Broken"),428,362)

end
function G:update()
 ISPanel.update(self)
 if not P.near(self.player,self.target) then self:close();return end
 if getTimestampMs()-(self.lastRefresh or 0)>3000 then
  if isClient() then sendClientCommand("WR","requestState",{}) else WR.Server.sendState(self.player) end
  self.lastRefresh=getTimestampMs()
 end
end
function G.open(player,target)
 if G.instance then G.instance:close() end
 local o=G:new((getCore():getScreenWidth()-790)/2,(getCore():getScreenHeight()-448)/2,790,448)
 o.player=player;o.target=target;o.wantKeyEvents=true;o.backgroundColor={r=0,g=0,b=0,a=0};o.borderColor={r=0,g=0,b=0,a=0};o:initialise();o:instantiate();o:addToUIManager();G.instance=o
end
