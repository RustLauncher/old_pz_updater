require "WaterRestoration/WR_Server"
require "WaterRestoration/WR_Power"
require "WaterRestoration/WR_ProgressJournal"
local S=WR.Server;local P=WR.Power
local base=S.handleCommand
local mutations={repairCentral=true,repairPanel=true,turnValve=true,maintain=true,repairStation=true,activateStation=true,maintainStation=true,activateWater=true,resyncWater=true}
local function result(player,code)
 if isServer() then sendServerCommand(player,"WR","result",{message=code}) else WR.showResult(player,code) end
 S.sendState(player)
end
local function save() if S.saveProgressJournal then S.saveProgressJournal() end end
local function restoreIfSuspended(data)
 if not data.powerSuspended or not data.wasActivated or not P.available(data) then return false end
 for _,id in ipairs(WR.ALL_IDS) do if WR.condition(data,id,P.now()/24)<=0 then return false end end
 data.waterActive=true;data.maintenanceRequired=false;data.powerSuspended=false
 S.applyWaterState(true,data);return true
end
local function tick()
 if isClient() then return end
 local data=S.getData();local previousGrid=data.gridPower;local was=P.available(data);P.settle(data)
 data.gridPower=P.gridAvailable(data)
 local changed=previousGrid~=data.gridPower
 if data.originalService then
  if changed then S.broadcastState() end
  save();return
 end
 if (was or data.waterActive) and not P.available(data) then
  data.powerSuspended=data.waterActive==true or data.powerSuspended==true;data.waterActive=false
  S.applyWaterState(false,data);changed=true
 elseif restoreIfSuspended(data) then changed=true end
 if changed then S.broadcastState() end
 save()
end
local function consume(player,kind,count)
 local items=kind=="ElectronicsScrap" and WR.getElectronicScrap(player:getInventory()) or WR.itemsOfType(player:getInventory(),kind)
 for i=1,count do local item=items[i];local inv=item:getContainer()
  if isServer() then sendRemoveItemFromContainer(inv,item) end;inv:Remove(item)
 end
end
function S.handleCommand(command,player,args)
 args=type(args)=="table" and args or {};tick()
 local data=S.getData();local revision=data.revisions[args.target or "central"] or 0
 if data.originalService and (mutations[command] or command=="repairGenerator" or command=="serviceGenerator" or command=="fuelGenerator" or command=="startGenerator" or command=="stopGenerator") then return result(player,"OriginalService") end
 if (mutations[command] or command=="repairGenerator" or command=="serviceGenerator" or command=="fuelGenerator" or command=="startGenerator" or command=="stopGenerator")
  and args.expectedRevision~=nil and args.expectedRevision~=revision then return result(player,"EquipmentChanged") end
 if command=="inspectGenerator" or command=="repairGenerator" or command=="serviceGenerator" or command=="fuelGenerator" or command=="startGenerator" or command=="stopGenerator" then
  if not P.near(player,args) then return result(player,"InvalidAction") end
  local g=P.data(data)
  if command=="inspectGenerator" then
   S.sendState(player)
   if isServer() then sendServerCommand(player,"WR","openGenerator",{x=args.x,y=args.y,z=0})
   elseif WR.GeneratorPanel then WR.GeneratorPanel.open(player,{id="generator",kind="generator",x=args.x,y=args.y,z=0}) end
   return
  elseif command=="repairGenerator" or command=="serviceGenerator" then
   local service=command=="serviceGenerator"
   if g.running or (not service and g.repaired) or (service and (not g.repaired or g.condition>=99.99)) then return result(player,"InvalidAction") end
   if not P.repairReady(player,service) then return result(player,"GeneratorRequirements") end
   consume(player,"ElectronicsScrap",service and 2 or 10);if not service then consume(player,"MetalBar",4) end
   g.repaired=true;g.condition=100;result(player,"GeneratorRepaired")
  elseif command=="fuelGenerator" then
   if not g.repaired or g.running or g.fuel>=P.CAPACITY-.001 then return result(player,"StopToRefuel") end
   local item=P.findFuel(player,tonumber(args.itemId));local fluid=item and P.fuelItem(item)
   if not fluid then return result(player,"NeedPetrol") end
   local amount=math.min(fluid:getAmount(),P.CAPACITY-g.fuel)
   fluid:adjustAmount(fluid:getAmount()-amount);item:syncItemFields();g.fuel=g.fuel+amount
   result(player,"GeneratorFueled")
  elseif command=="startGenerator" then
   if g.running or not g.repaired or g.condition<=0 or g.fuel<P.MINIMUM-.0001 then return result(player,"GeneratorMinimum") end
   g.running=true;g.updatedAt=P.now()
   if data.powerSuspended and data.wasActivated then
    local healthy=true;for _,id in ipairs(WR.ALL_IDS) do if WR.condition(data,id,P.now()/24)<=0 then healthy=false end end
    if healthy then data.waterActive=true;data.maintenanceRequired=false;S.applyWaterState(true,data) end
   end
   data.powerSuspended=false;result(player,"GeneratorStarted")
  elseif command=="stopGenerator" then
   if not g.running then return result(player,"InvalidAction") end
   g.running=false
   if not P.available(data) then
    data.powerSuspended=data.waterActive==true or data.powerSuspended==true;data.waterActive=false
    S.applyWaterState(false,data)
   end
   result(player,"GeneratorStopped")
  end
  data.revisions.generator=(data.revisions.generator or 0)+1;S.broadcastState();save();return
 end
 local target=WR.TARGETS[args.target];local blocked=P.block(command,target,data)
 if blocked then return result(player,blocked) end
 if mutations[command] then
  -- Commands execute serially on the server. Compare the actual equipment state
  -- before/after; advance only that equipment's revision after a real change.
  local id=args.target or "central";local region=data.regions[id]
  local function fingerprint() return tostring(data.centralRepaired)..":"..tostring(data.panels[id])..":"..tostring(data.valves[id])..":"..tostring(data.servicedAt[id])..":"..tostring(data.waterActive)..":"..(region and (tostring(region.repaired)..":"..tostring(region.activated)..":"..tostring(region.servicedAt)) or "") end
  local before=fingerprint();base(command,player,args)
  if before~=fingerprint() then data.revisions[id]=revision+1;S.broadcastState();save() end
 else return base(command,player,args) end
end
Events.EveryOneMinute.Add(tick)
Events.OnInitGlobalModData.Add(tick)
Events.OnGameStart.Add(function()
 if isClient() then return end
 tick();local data=S.getData()
 if not P.available(data) and data.waterActive then data.powerSuspended=true;data.waterActive=false;S.refreshNetwork();save() end
end)
