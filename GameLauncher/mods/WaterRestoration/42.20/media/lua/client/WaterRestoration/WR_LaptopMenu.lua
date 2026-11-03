require "WaterRestoration/WR_LaptopPanel"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "ISUI/ISInventoryPaneContextMenu"
local L=WR.Laptop
function L.request(player,item,command,show)
 local args={id=item:getID(),show=show==true}
 local world=item:getWorldItem();local sq=world and world:getSquare()
 if sq then args.x=sq:getX();args.y=sq:getY();args.z=sq:getZ() end
 if isClient() then sendClientCommand("WRLaptop",command,args)
 elseif L.handle then L.handle(command,player,args) end
end
function L.receive(player,item,args)
 if not item then return end
 if (args.data.revision or 0)<(L.data(item).revision or 0) then return end
 local wasOn=L.data(item).powered
 item:getModData().WRLaptop=args.data;L.visual(item)
 local message=args.error or args.notice
 if message then
  L.messageTimes=L.messageTimes or {};local key=tostring(item:getID())..":"..message;local now=getTimestampMs()
  if not L.messageTimes[key] or now-L.messageTimes[key]>3000 then player:Say(getText(message));L.messageTimes[key]=now end
 end
 local panel=L.Panel.instance
 if panel and panel.item:getID()==item:getID() then
  if not args.data.opened then panel:close()
  elseif not wasOn and args.data.powered then
   panel.bootUntil=getTimestampMs()+1500
   if panel.preferences.audio then player:playSound("WR_ConsoleBoot") end
  end
 end
 if args.show and not args.error then L.Panel.open(player,item) end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~="WRLaptop" or command~="state" then return end
 local player=getPlayer();if not player then return end
 local item=L.find(player,args.id,args.x,args.y,args.z)
 if not item and L.Panel.instance and L.Panel.instance.item:getID()==args.id then item=L.Panel.instance.item end
 if item then L.receive(player,item,args) end
end)
WRLaptopAction=ISBaseTimedAction:derive("WRLaptopAction")
local Action=WRLaptopAction
function Action:isValid()
 return L.find(self.character,self.item:getID(),self.x,self.y,self.z)~=nil
end
function Action:start() self:setActionAnim("Loot");self.character:reportEvent("EventLootItem") end
function Action:apply()
 if self.applied then return end
 self.applied=true
 L.request(self.character,self.item,self.command,self.command=="open")
end
function Action:complete() self:apply();return true end
function Action:perform()
 self:apply()
 ISBaseTimedAction.perform(self)
end
function Action:new(player,item,command)
 local o=ISBaseTimedAction.new(self,player);o.item=item;o.command=command
 o.maxTime=command=="batteries" and 120 or 35;o.stopOnWalk=true;o.stopOnRun=true
 local world=item:getWorldItem();local sq=world and world:getSquare()
 if sq then o.x=sq:getX();o.y=sq:getY();o.z=sq:getZ() end
 return o
end
local function action(player,item,command)
 if not item:getWorldItem() then ISInventoryPaneContextMenu.transferIfNeeded(player,item) end
 ISTimedActionQueue.add(Action:new(player,item,command))
end
local function addOptions(player,context,item)
 L.visual(item);local d=L.data(item);local hours=L.remaining(d)
 if not d.opened then context:addOption(getText("IGUI_WR_Release_Text47"),player,action,item,"open")
 else
  context:addOption(d.powered and hours>0 and getText("IGUI_WR_Release_Text48") or getText("IGUI_WR_Release_Text49"),player,
   function(p,i) L.request(p,i,"on",true) end,item)
  context:addOption(d.powered and hours>0 and getText("IGUI_WR_Release_Text50") or getText("IGUI_WR_Release_Text51"),player,action,item,"close")
 end
 if d.powered then context:addOption(getText("IGUI_WR_Release_Text52"),player,action,item,"off") end
 if hours<=0 then context:addOption(getText("IGUI_WR_Release_Text53"),player,action,item,"batteries") end
end
Events.OnFillInventoryObjectContextMenu.Add(function(index,context,entries)
 local player=getSpecificPlayer(index)
 for _,entry in ipairs(entries or {}) do
  if instanceof(entry,"InventoryItem") then
   if L.isLaptop(entry) then addOptions(player,context,entry);return end
  elseif type(entry)=="table" and entry.items then
   for _,item in ipairs(entry.items) do if L.isLaptop(item) then addOptions(player,context,item);return end end
  end
 end
end)
Events.OnFillWorldObjectContextMenu.Add(function(index,context,objects,test)
 if test then return end
 local player=getSpecificPlayer(index);local seen={}
 for _,object in ipairs(objects or {}) do local sq=object:getSquare()
  if sq and not seen[sq] then
   seen[sq]=true;local world=sq:getWorldObjects()
   for i=0,world:size()-1 do local item=world:get(i):getItem()
    if L.isLaptop(item) and L.find(player,item:getID(),sq:getX(),sq:getY(),sq:getZ()) then addOptions(player,context,item);return end
   end
  end
 end
end)
Events.OnGameStart.Add(function()
 local player=getPlayer();if player then L.walk(player:getInventory(),function(item) if L.isLaptop(item) then L.visual(item) end end) end
end)
