require "ElectricRestoration/ER_Core"
require "ElectricRestoration/ER_Service"
require "ElectricRestoration/ER_Requirements"
require "ElectricRestoration/ER_Network"
ER.Server=ER.Server or {}
local S=ER.Server;local C=ER.Core
local function hour() return getGameTime():getWorldAgeHours() end
function S.data()
 local d=ModData.getOrCreate(ER.DATA_KEY)
 if not d.initialized then C.initialize(d,ZombRand(2147483645)+1,hour()) end
 ER.Service.update(d)
 return d
end
function S.send(player)
 local data=S.data();local state={}
 for k,v in pairs(data) do state[k]=v end
 if data.originalService then
  state.online=true;state.networkReady=true;state.originalRemainingDays=ER.Service.remaining(data)
  state.machines={};state.terminals={};state.selected={};state.dispatch={repaired=true,condition=100,revision=data.dispatch.revision}
  for i,m in ipairs(data.machines) do state.machines[i]={id=i,condition=100,wearFactor=m.wearFactor,revision=m.revision} end
  for _,id in ipairs(ER.TERMINALS) do state.terminals[id]={repaired=true,tested=true,condition=100,revision=data.terminals[id].revision} end
  for _,r in ipairs(ER.REGIONS) do state.selected[r.id]=true end
 end
 state.manualRead=player and player:getModData().ERManualRead==true
 state.serverHour=hour();state.networkReady=data.originalService or (ER.Network.job==nil and ER.Network.error==nil)
 if isServer() then sendServerCommand(player,"ER","state",state) else ER.State=state end
end
local function result(player,key)
 if isServer() then sendServerCommand(player,"ER","result",{key=key}) else player:Say(getText("IGUI_ER_"..key)) end
 S.send(player)
end
local function broadcast()
 ModData.transmit(ER.DATA_KEY)
 if isServer() then local ps=getOnlinePlayers();for i=0,ps:size()-1 do S.send(ps:get(i)) end
 elseif getPlayer() then S.send(getPlayer()) end
end
local function network()
 local data=S.data();if not data.originalService and C.plantReady(data) then data.localCommissioned=true end
 if data.originalService or data.commissioned or data.localCommissioned then ER.Network.sync(data,data.online) end
end
function S.updatePower()
 if isClient() then return end
 local data=S.data()
 if S.phaseApplied~=data.originalService then
  S.phaseApplied=data.originalService;network();broadcast()
 end
 if data.originalService then
  local options=getSandboxOptions()
  if options:getElecShutModifier()~=data.originalElecShutModifier then
   options:set("ElecShutModifier",data.originalElecShutModifier)
   if options.toLua then options:toLua() end
   if SandboxVars then SandboxVars.ElecShutModifier=data.originalElecShutModifier end
   if isServer() and GameServer and GameServer.sendOptionsToClients then GameServer.sendOptionsToClients() end
  end
  return
 end
 if not data.commissioned and not data.localCommissioned then return end
 local enabled=(C.plantReady(data) or (data.online and C.runningReady(data) and C.demand(data)>0)) and ER.Network.job==nil and ER.Network.error==nil
 if S.applied==enabled then return end
 local options=getSandboxOptions();options:set("ElecShutModifier",enabled and 1000000 or -1)
 if options.toLua then options:toLua() end
 if SandboxVars then SandboxVars.ElecShutModifier=enabled and 1000000 or -1 end
 getWorld():setHydroPowerOn(enabled)
 if isServer() and GameServer and GameServer.sendOptionsToClients then GameServer.sendOptionsToClients() end
 S.applied=enabled;broadcast()
end
local function items(inv,kind,out)
 out=out or {};local all=inv:getItems()
 for i=0,all:size()-1 do local item=all:get(i)
  if item:getFullType()=="Base."..kind then out[#out+1]=item end
  if instanceof(item,"InventoryContainer") then items(item:getInventory(),kind,out) end
 end
 return out
end
local function consume(inv,kind,count)
 local found=items(inv,kind)
 for i=1,count do local item=found[i];local c=item:getContainer()
  if isServer() then sendRemoveItemFromContainer(c,item) end;c:Remove(item)
 end
end
local function affordable(player,t,service)
 local inv=player:getInventory();local machine=t.kind=="machine"
 return player:getModData().ERManualRead==true and player:getPerkLevel(Perks.Electricity)>=(machine and 8 or 7)
  and (machine or (player:getPerkLevel(Perks.Mechanics)>=7 and player:getPerkLevel(Perks.Strength)>=6))
  and inv:containsTypeRecurse("Screwdriver") and (not machine or inv:containsTypeRecurse("Wrench"))
  and #items(inv,"ElectronicsScrap")>=(machine and 2 or (service and 2 or 10))
  and (not machine or #items(inv,"MetalBar")>=2)
end
function S.command(command,player,args)
 if not player then return end;args=type(args)=="table" and args or {}
 local data=S.data();C.settle(data,hour())
 if command=="state" then S.send(player);return end
 if data.originalService and command~="manual" and command~="inspect" and command~="pairLaptop" then return result(player,"OriginalService") end
 if command=="manual" then
  if not player:getInventory():containsTypeRecurse("ERManual") then return result(player,"NeedManual") end
  player:getModData().ERManualRead=true;if player.transmitModData then player:transmitModData() end;return result(player,"ManualRead")
 end
 local x,y,z=tonumber(args.x),tonumber(args.y),tonumber(args.z)
 if not x or not y or z~=0 or player:getZ()~=0 or (player:getX()-x)^2+(player:getY()-y)^2>9 then return result(player,"TooFar") end
 local t=ER.targetAt(x,y,z,args.target);if not t then return result(player,"Invalid") end
 data.locations=data.locations or {};data.locations[t.id]={x=x,y=y,z=z}
 if command=="inspect" then
  if t.id=="protection" and S.ensureManual then S.ensureManual() end
  S.send(player)
  if isServer() then sendServerCommand(player,"ER","open",t) elseif ER.Panel then ER.Panel.open(player,t,false) end
  return
 end
 if command=="pairLaptop" then
  local linkNode=t.id=="dispatch" and data.dispatch or (t.kind=="terminal" and data.terminals[t.id])
  if not linkNode or (not data.originalService and not linkNode.repaired) or not WR or not WR.Laptop then return result(player,"RepairFirst") end
  local item=WR.Laptop.find(player,tonumber(args.itemId))
  if not item then return result(player,"BringLaptop") end
  local d=WR.Laptop.settle(item)
  if not d.opened or not d.powered or d.hours<=0 then return result(player,"BringLaptop") end
  d.links=d.links or {}
  if d.links.electric then return result(player,"AlreadyLinked") end
  d.links.electric=true;d.revision=(d.revision or 0)+1
  if syncItemModData then syncItemModData(player,item) end
  if isServer() then sendServerCommand(player,"WRLaptop","state",{id=item:getID(),data=d,show=false})
  elseif WR.Laptop.receive then WR.Laptop.receive(player,item,{data=d,show=false}) end
  return result(player,"Linked")
 end
 local node=t.kind=="machine" and data.machines[t.index] or (t.id=="dispatch" and data.dispatch or data.terminals[t.id])
 if command=="regions" then
  if t.id~="dispatch" or not data.dispatch.repaired or type(args.selected)~="table" then return result(player,"Invalid") end
  local ok=C.selection(data,args.selected,args.expected,hour());if not ok then return result(player,"Stale") end
  data.dispatch.revision=data.dispatch.revision+1
  network();S.updatePower();broadcast();return
 end
 if args.expected~=node.revision then return result(player,"Stale") end
 if command=="repair" or command=="test" or command=="start" then
  local ok,rows=ER.Requirements.check(player,data,t,command)
  if not ok then
   if isServer() then sendServerCommand(player,"ER","requirements",{rows=rows}) else player:Say(ER.Requirements.missing(rows)) end
   S.send(player);return
  end
 end
 if command=="repair" then
  if node.condition>=100 then return result(player,"Invalid") end
  local service=node.repaired==true
  if not affordable(player,t,service) then return result(player,"Materials") end
  if t.kind=="machine" and (not data.terminals.protection.tested or not data.terminals.cooling.tested) then return result(player,"Auxiliaries") end
  if t.id=="dispatch" then for _,id in ipairs(ER.TERMINALS) do if not data.terminals[id].tested then return result(player,"Sequence") end end end
  consume(player:getInventory(),"ElectronicsScrap",t.kind=="machine" and 2 or (service and 2 or 10))
  if t.kind=="machine" then consume(player:getInventory(),"MetalBar",2);C.repairMachine(data,t.index,node.revision,hour())
  else node.repaired=true;node.condition=100;node.revision=node.revision+1 end
  result(player,"Repaired")
 elseif command=="test" then
  if t.kind~="terminal" or not node.repaired or node.condition<75 or node.tested then return result(player,"Sequence") end
  local prev
  for i,id in ipairs(ER.TERMINALS) do if id==t.id then prev=ER.TERMINALS[i-1] end end
  if prev and not data.terminals[prev].tested then return result(player,"Sequence") end
  if t.id=="regulation" then for _,m in ipairs(data.machines) do if m.condition<75 then return result(player,"MachinesPending") end end end
  node.tested=true;node.revision=node.revision+1;result(player,"Tested")
 elseif command=="start" then
  if t.id~="dispatch" or not C.start(data,hour()) then return result(player,"NotReady") end
  node.revision=node.revision+1;result(player,"Started")
 elseif command=="stop" then
  if t.id~="dispatch" then return result(player,"Invalid") end
  data.online=false;node.revision=node.revision+1;result(player,"Stopped")
 else return end
 network();S.updatePower();broadcast()
end
Events.OnClientCommand.Add(function(module,command,player,args) if module=="ER" then S.command(command,player,args) end end)
Events.OnInitGlobalModData.Add(function() S.data();network();S.updatePower() end)
Events.OnTick.Add(S.updatePower)
Events.EveryOneMinute.Add(function() if isClient() then return end;local d=S.data();local online=d.online;C.settle(d,hour());if online~=d.online then network();broadcast() end end)

-- Place the physical book inside the entrance guard hut's furniture.
-- Version 4 relocates the manual to the actual guard booth without touching player items.
function S.ensureManual()
 if isClient() then return end
 local data=S.data();if data.manualSpawnVersion==4 then return end
 local cell=getCell();if not cell then return end
 local candidates={};local floors={}
 for x=14730,14736 do for y=4080,4086 do
  local sq=cell:getGridSquare(x,y,0)
  if sq then
   if sq.getWorldObjects then
    local worldItems=sq:getWorldObjects()
    for i=0,worldItems:size()-1 do local item=worldItems:get(i):getItem()
     if item and item:getFullType()=="Base.ERManual" then data.manualSpawnVersion=4;data.manualSpawned=true;ModData.transmit(ER.DATA_KEY);return end
    end
   end
   if sq.getFloor and sq:getFloor() and sq:isFree(false) and (sq:getRoom() or not sq:isOutside()) then floors[#floors+1]=sq end
   local objects=sq:getObjects()
   for i=0,objects:size()-1 do local obj=objects:get(i)
    local count=obj.getContainerCount and obj:getContainerCount() or 0
    for j=0,count-1 do local container=obj:getContainerByIndex(j)
     if container then
      if container:containsTypeRecurse("ERManual") then
       data.manualSpawnVersion=4;data.manualSpawned=true;ModData.transmit(ER.DATA_KEY);return
      end
      local kind=tostring(container:getType())
      local preferred=kind=="locker" or kind=="counter" or kind=="desk" or kind=="shelves" or kind=="filingcabinet"
      if preferred then candidates[#candidates+1]={container=container,square=sq,kind=kind} end
     end
    end
   end
  end
 end end
 table.sort(candidates,function(a,b)
  return (a.square:getX()-14733)^2+(a.square:getY()-4083)^2 < (b.square:getX()-14733)^2+(b.square:getY()-4083)^2
 end)
 local target=candidates[1]
 if not target then
  table.sort(floors,function(a,b) return (a:getX()-14733)^2+(a:getY()-4083)^2 < (b:getX()-14733)^2+(b:getY()-4083)^2 end)
  if not floors[1] then return end
  target={square=floors[1],kind="floor"}
 end
 local item
 if target.container then item=target.container:AddItem("Base.ERManual")
 else item=target.square:AddWorldInventoryItem("Base.ERManual",.5,.5,0) end
 if item then
  if isServer() and target.container then sendAddItemToContainer(target.container,item) end
  data.manualSpawned=true;data.manualSpawnVersion=4
  data.manualLocation={x=target.square:getX(),y=target.square:getY(),z=0,container=target.kind}
  ModData.transmit(ER.DATA_KEY)
 end
end
local manualCheckPending=true
Events.LoadGridsquare.Add(function(sq)
 if sq and math.abs(sq:getX()-14733)<=4 and math.abs(sq:getY()-4083)<=4 then manualCheckPending=true end
end)
Events.OnTick.Add(function() if manualCheckPending and not isClient() then manualCheckPending=false;S.ensureManual() end end)
Events.EveryOneMinute.Add(S.ensureManual)
