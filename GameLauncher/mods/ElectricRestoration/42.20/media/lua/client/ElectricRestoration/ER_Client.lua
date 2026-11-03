require "ElectricRestoration/ER_Panel"
require "ElectricRestoration/ER_Network"
ER.State=ER.State or {}
Events.OnServerCommand.Add(function(module,command,args)
 if module~="ER" then return end
 if command=="state" then ER.State=args;if args.originalService or args.commissioned or args.localCommissioned then ER.Network.sync(args,args.online) end
 elseif command=="open" then ER.Panel.open(getPlayer(),args,false)
 elseif command=="requirements" then getPlayer():Say(ER.Requirements.missing(args.rows))
 elseif command=="result" then getPlayer():Say(getText("IGUI_ER_"..args.key)) end
end)
Events.OnGameStart.Add(function() ER.request("state") end)
Events.OnFillWorldObjectContextMenu.Add(function(index,context,objects,test)
 if test then return end
 local player=getSpecificPlayer(index);local target
 for _,o in ipairs(objects or {}) do target=ER.resolve(o);if target then break end end
 if not target then return end
 context:addOption(getText("IGUI_ER_Inspect"),player,function(p,t) ER.request("inspect",t,{player=p}) end,target)
 if (target.id=="dispatch" or target.kind=="terminal") and WR and WR.Laptop then
  local item;WR.Laptop.walk(player:getInventory(),function(i) if not item and WR.Laptop.isLaptop(i) then item=i end end)
  if item then
   local linked=(WR.Laptop.data(item).links or {}).electric
   local o=context:addOption(getText("IGUI_ER_"..(linked and "AlreadyLinked" or "Link")),player,function(p,t,i) ER.request("pairLaptop",t,{player=p,itemId=i:getID()}) end,target,item)
   o.notAvailable=linked==true
  end
 end
end)
Events.OnFillInventoryObjectContextMenu.Add(function(index,context,entries)
 local player=getSpecificPlayer(index);if player:getModData().ERManualRead then return end
 for _,entry in ipairs(entries or {}) do
  local all=instanceof(entry,"InventoryItem") and {entry} or entry.items or {}
  for _,item in ipairs(all) do if item:getFullType()=="Base.ERManual" then context:addOption(getText("IGUI_ER_Read"),player,function(p) ER.queue(p,nil,"manual") end);return end end
 end
end)
function ER.openLaptopMonitor(player,item)
 if not (WR.Laptop.data(item).links or {}).electric then player:Say(getText("IGUI_ER_NeedLink"));return end
 ER.request("state",nil,{player=player});ER.Panel.open(player,ER.TARGETS.dispatch,true,item)
end

require "ElectricRestoration/ER_LaptopApp"

require "ElectricRestoration/ER_Ambience"
