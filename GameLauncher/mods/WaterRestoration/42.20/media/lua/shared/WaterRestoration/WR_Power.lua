require "WaterRestoration/WR_Config"
WR.Power=WR.Power or {}
local P=WR.Power
P.CAPACITY=80;P.MINIMUM=20;P.RATE=20/168 -- vanilla gas can holds 10 litres
function P.now() return getGameTime():getWorldAgeHours() end
function P.data(data)
 data.generator=data.generator or {repaired=false,running=false,fuel=0,condition=0,updatedAt=P.now()}
 return data.generator
end
function P.hours(g) return math.max(0,g.fuel or 0)/P.RATE end
function P.generatorAvailable(data)
 local g=data.generator
 return g~=nil and g.repaired==true and g.running==true and (g.fuel or 0)>0 and (g.condition or 0)>0
end
function P.gridAvailable(data)
 -- A regional grid must actually supply the water plant, not just Riverside
 -- or the electrical stations' independent service footprints.
 if ER and ER.Core and ER.regionAt then
  local client=isClient and isClient()
  local state
  if client then state=ER.State elseif ER.Server and ER.Server.data then state=ER.Server.data() end
  if state and state.initialized and not state.originalService then
   local region=ER.regionAt(WR.TARGETS.central.x,WR.TARGETS.central.y)
   local ready=client and state.networkReady~=false or
    (not client and ER.Network and ER.Network.job==nil and ER.Network.error==nil and ER.Server.applied~=false)
   return ready and region~=nil and ER.regionSupplied(state,region.id) or false
  end
  if client then
   if state and state.originalService then return true end
   return data.gridPower==true
  end
 end
 -- With Water Restoration alone, use the original utility grid until shutoff.
 if isClient and isClient() then return data.gridPower==true end
 local options=getSandboxOptions and getSandboxOptions()
 if options and options.getElecShutModifier then
  local day=P.now()/24+((options.getTimeSinceApo and options:getTimeSinceApo() or 1)-1)*30
  return day<options:getElecShutModifier()
 end
 return false
end
function P.available(data)
 return data.originalService==true or P.gridAvailable(data) or P.generatorAvailable(data)
end
function P.settle(data)
 local g=P.data(data);local now=P.now();local elapsed=math.max(0,now-(g.updatedAt or now))
 if g.running and not data.originalService then
  local used=math.min(elapsed,P.hours(g),math.max(0,g.condition or 0)*42*24/100);g.fuel=math.max(0,g.fuel-used*P.RATE)
  -- Generator service interval is longer than the plant's 21-day cycle.
  g.condition=math.max(0,(g.condition or 0)-used*100/(42*24))
  if g.fuel<=.00001 or g.condition<=0 then g.fuel=math.max(0,g.fuel);g.running=false end
 end
 g.updatedAt=now;return g
end
function P.target(object)
 local sq=object and object:getSquare();local sprite=object and object:getSprite();local name=sprite and sprite:getName()
 if not sq or sq:getZ()~=0 or math.abs(sq:getX()-8055)>12 or math.abs(sq:getY()-15363)>8 then return end
 if name=="industry_02_52" or name=="industry_02_53" then return {id="generator",kind="generator",x=sq:getX(),y=sq:getY(),z=0} end
end
function P.near(player,args)
 local x,y,z=tonumber(args.x),tonumber(args.y),tonumber(args.z)
 if not player or not x or not y or z~=0 or player:getZ()~=0 or (player:getX()-x)^2+(player:getY()-y)^2>9 then return false end
 local sq=getCell():getGridSquare(x,y,z);if not sq then return false end
 local objects=sq:getObjects()
 for i=0,objects:size()-1 do if P.target(objects:get(i)) then return true end end
 return false
end
function P.fuelItem(item)
 local f=item.getFluidContainer and item:getFluidContainer()
 if f and f:getAmount()>0 and f:isPureFluid(Fluid.Petrol) then return f end
end
function P.findFuel(player,id)
 local found
 local function visit(inv)
  local items=inv:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if (not id or item:getID()==id) and P.fuelItem(item) then found=item;return end
   if instanceof(item,"InventoryContainer") then visit(item:getInventory());if found then return end end
  end
 end
 visit(player:getInventory());return found
end
function P.repairReady(player,service)
 local inv=player:getInventory()
 return player:getModData().WRManualRead==true and player:getPerkLevel(Perks.Electricity)>=5 and player:getPerkLevel(Perks.Mechanics)>=5
  and inv:containsTypeRecurse("Screwdriver") and inv:containsTypeRecurse("Wrench")
  and WR.countElectronicScrap(inv)>=(service and 2 or 10) and #WR.itemsOfType(inv,"MetalBar")>=(service and 0 or 4)
end
function P.block(command,target,data)
 if data.originalService and (command=="repairCentral" or command=="repairPanel" or command=="activateWater" or command=="resyncWater" or command=="turnValve" or command=="maintain" or command=="repairStation" or command=="activateStation" or command=="maintainStation") then return "OriginalService" end
 if command=="turnValve" then
  for _,id in ipairs(WR.PANEL_IDS) do if not (data.panels or {})[id] then return "ComputersFirst" end end
 end
 if (command=="repairCentral" or command=="repairPanel" or command=="inspectPlant" or command=="activateWater" or command=="resyncWater"
  or command=="activateStation" or command=="inspectStation" or command=="repairStation" or command=="maintainStation" or command=="turnValve" or (command=="maintain" and target and target.kind~="valve")) and not P.available(data) then return "NoPlantPower" end
end
