require "WaterRestoration/WR_Laptop"
require "WaterRestoration/WR_Server"
require "WaterRestoration/WR_LaptopSites"
local L=WR.Laptop
local function reply(player,item,errorMessage,show,notice)
 local d=L.data(item)
 if syncItemModData then syncItemModData(player,item) end
 local args={id=item:getID(),data=d,error=errorMessage,notice=notice,show=show,x=nil,y=nil,z=nil}
 local world=item:getWorldItem();local sq=world and world:getSquare()
 if sq then args.x=sq:getX();args.y=sq:getY();args.z=sq:getZ() end
 if isServer() then sendServerCommand(player,"WRLaptop","state",args)
 elseif L.receive then L.receive(player,item,args) end
end
function L.handle(command,player,args)
 if not player or type(args)~="table" then return end
 print("[WaterRestoration] laptop command="..tostring(command).." id="..tostring(args.id))
 local item=L.find(player,tonumber(args.id),tonumber(args.x),tonumber(args.y),tonumber(args.z))
 if not item then print("[WaterRestoration] laptop item not accessible");return end
 local d=L.settle(item);local err;local show=false;local notice
 if command=="pairWater" then
  local t=WR.TARGETS.central;local data=WR.Server.getData()
  if player:getZ()~=t.z or (player:getX()-t.x)^2+(player:getY()-t.y)^2>9 or (not data.originalService and not data.centralRepaired) or not WR.Power.available(data) then err="IGUI_WR_Link_AtCentral"
  elseif not d.opened or not d.powered or d.hours<=0 then err="IGUI_WR_Link_PowerLaptop"
  elseif (d.links or {}).water then notice="IGUI_WR_Link_AlreadyPaired"
  else d.links=d.links or {};d.links.water=true;notice="IGUI_WR_Link_Paired" end
 elseif command=="open" then d.opened=true;show=true
 elseif command=="close" then d.powered=false;d.opened=false
 elseif command=="off" then d.powered=false
 elseif command=="batteries" then
  if d.powered then err="IGUI_WR_Release_Text54"
  elseif (d.hours or 0)>0 and (d.cells or 0)>0 then err="IGUI_WR_Release_Text55"
  else
   local batteries={}
   L.walk(player:getInventory(),function(b)
    if b:getFullType()=="Base.Battery" and b:getCurrentUsesFloat()>=(1-(b.getUseDelta and b:getUseDelta() or .007)-.001) then batteries[#batteries+1]=b end
   end)
   if #batteries<4 then err="IGUI_WR_Release_Text56"
   else
    for i=1,4 do local b=batteries[i];local c=b:getContainer()
     if isServer() then sendRemoveItemFromContainer(c,b) end
     c:Remove(b)
    end
    d.cells=4;d.hours=L.HOURS
    print("[WaterRestoration] laptop installed four batteries; charge=168h")
   end
  end
 elseif command=="on" or command=="use" then
  if not d.opened then err="IGUI_WR_Laptop_OpenFirst"
  elseif d.cells~=4 or d.hours<=0 then err="IGUI_WR_Release_Text57"
  else d.powered=true;show=command=="on" or args.show==true end
 elseif command~="status" then return end
 if command~="status" and command~="use" then d.revision=(d.revision or 0)+1 end
 d.updatedAt=L.now();L.visual(item)
 if not err and d.powered then WR.Server.sendState(player) end
 reply(player,item,err,show,notice)
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module=="WRLaptop" then L.handle(command,player,args) end
end)
Events.EveryHours.Add(function()
 if isClient() then return end
 local function update(player)
  if not player then return end
  L.walk(player:getInventory(),function(item)
   if L.isLaptop(item) and L.data(item).powered then L.settle(item);reply(player,item) end
  end)
 end
 if isServer() then
  local players=getOnlinePlayers();for i=0,players:size()-1 do update(players:get(i)) end
 else update(getPlayer()) end
end)
-- Spawn once in a real office container, including already-existing saves.
local function spawn(square)
 if isClient() or not square then return end
 local data=WR.Server.getData();data.laptopSites=data.laptopSites or {};data.laptopRolls=data.laptopRolls or {}
 local a=WR.OFFICE_AREA;local x,y,z=square:getX(),square:getY(),square:getZ()
 local site
 if x>=a.minX and x<=a.maxX and y>=a.minY and y<=a.maxY and z>=a.minZ and z<=a.maxZ then
  if data.laptopSpawned then return end
  site="central"
 else
  for _,area in ipairs(L.MILITARY_SITES) do
   if x>=area.minX and x<=area.maxX and y>=area.minY and y<=area.maxY and z>=0 and z<=2 then site=area.id;break end
  end
  if not site or data.laptopSites[site] then return end
 end
 local objects=square:getObjects()
 for i=0,objects:size()-1 do local object=objects:get(i)
  for n=0,object:getContainerCount()-1 do local c=object:getContainerByIndex(n)
   local name=string.lower(tostring(c:getType() or ""))
   if name:find("desk") or name:find("filing") or name:find("office") or name:find("counter") or name:find("shel") or (site~="central" and (name:find("military") or name:find("crate") or name:find("locker"))) then
    if data.laptopRolls[site]==false then return end
    if data.laptopRolls[site]==nil then
     data.laptopRolls[site]=ZombRand(100)<(site=="central" and 40 or 30)
     ModData.transmit(WR.DATA_KEY)
     print("[WaterRestoration] laptop chance at "..site.." success="..tostring(data.laptopRolls[site]))
     if not data.laptopRolls[site] then return end
    end
    local laptop=c:AddItem(L.ITEM)
    if laptop then
     L.onCreate(laptop);data.laptopSites[site]=true
     if site=="central" then data.laptopSpawned=true end
     if isServer() then sendAddItemToContainer(c,laptop) end
     for b=1,4 do local battery=c:AddItem("Base.Battery")
      if isServer() and battery then sendAddItemToContainer(c,battery) end
     end
     ModData.transmit(WR.DATA_KEY)
     print("[WaterRestoration] military laptop spawned at site "..site.." position "..x..","..y..","..z)
     return
    end
   end
  end
 end
end
Events.LoadGridsquare.Add(spawn)
Events.EveryOneMinute.Add(function()
 if isClient() then return end
 local data=WR.Server.getData()
 if data.laptopSpawned or (data.laptopRolls and data.laptopRolls.central==false) then return end
 local a=WR.OFFICE_AREA
 for z=a.minZ,a.maxZ do for x=a.minX,a.maxX do for y=a.minY,a.maxY do
  spawn(getCell():getGridSquare(x,y,z))
  if WR.Server.getData().laptopSpawned then return end
 end end end
end)
