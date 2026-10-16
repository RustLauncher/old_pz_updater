require "WaterRestoration/WR_Config"
-- Base-map service areas only. Rectangles are half-open and deliberately disjoint.
WR.REGIONS={
 {id="south",name="Rosewood / March Ridge",x=7267,y=12507,cities={"Rosewood","March Ridge"},areas={{4800,10000,9500,16000},{9500,11500,11000,14000}}},
 {id="riverside",name="Riverside / Fallas Lake",x=6746,y=6843,cities={"Riverside","Fallas Lake","Scenic Grove Trailer Park"},areas={{4800,4800,9500,10000}}},
 {id="irvington",name="Irvington / Echo Creek",x=2565,y=12542,cities={"Irvington","Echo Creek"},areas={{0,10000,4800,16000}}},
 {id="brandenburg",name="Ekron / Brandenburg",x=3538,y=6100,cities={"Ekron","Brandenburg","Bright Valley Trailer Park","Coalfield"},areas={{0,4800,4800,10000}}},
 {id="muldraugh",name="Muldraugh / West Point",x=10276,y=8744,cities={"Muldraugh","West Point","Dixie Trailer Park"},areas={{9500,5500,14500,11500}}},
 {id="louisville",name="Louisville / Valley Station",x=11990,y=1447,cities={"Louisville","Valley Station"},areas={{11000,0,16000,5500}}},
}
WR.REGION_BY_ID={}
for _,region in ipairs(WR.REGIONS) do WR.REGION_BY_ID[region.id]=region end
function WR.regionAt(x,y)
 for _,region in ipairs(WR.REGIONS) do
  for _,a in ipairs(region.areas) do if x>=a[1] and y>=a[2] and x<a[3] and y<a[4] then return region end end
 end
end
function WR.cityRegion(city)
 for _,r in ipairs(WR.REGIONS) do for _,name in ipairs(r.cities) do if name==city.name then return r end end end
 return WR.regionAt(city.x,city.y)
end
function WR.stationCondition(station,day)
 if not station or not station.repaired then return 0 end
 if not station.activated then return 100 end
 return math.max(0,math.min(100,100*(1-(day-(station.servicedAt or day))/WR.getRequirements().maintenanceDays)))
end
function WR.regionSupplied(data,id,day,plantEnabled)
 if data.originalService then return true end
 local s=(data.regions or {})[id]
 if plantEnabled==nil then
  if data.networkReady==false then return false end
  plantEnabled=data.waterActive
 end
 return plantEnabled==true and s~=nil and s.activated==true and WR.stationCondition(s,day)>0
end
-- Actual NoWater zones are consulted by IsoObject.isWaterInfinite/getReserveWaterAmount.
-- No sprite edits or invented water reservoirs; wells/external tanks keep vanilla behavior.
WR.Network=WR.Network or {}
local N=WR.Network
local function desired(data,plantEnabled)
 if plantEnabled==nil then plantEnabled=data.waterActive end
 local day=data.serverDay or getGameTime():getWorldAgeHours()/24
 if data.originalService then return "original-service",false,{} end
 local key="v3";local any=false;local supply={}
 for _,r in ipairs(WR.REGIONS) do
  local on=WR.regionSupplied(data,r.id,day,plantEnabled)
  supply[r.id]=on;key=key..(on and "1" or "0");any=any or on
 end
 return key,any,supply
end
function N.sync(data,plantEnabled)
 local world=getWorld and getWorld();local meta=world and world:getMetaGrid()
 if not meta then return false,"Meta grid not ready" end
 local key,any,supply=desired(data,plantEnabled)
 if N.job and N.job.key==key and N.job.meta==meta then return true,false end
 if not N.job and N.key==key and N.meta==meta then return true,any end
 -- Explicit cursors survive event callbacks without suspended Lua coroutines.
 N.key=nil;N.error=nil
 N.job={key=key,any=any,supply=supply,world=world,meta=meta,
  phase="scan",scan=0,stale={},index=1,created=0}
 print("[WaterRestoration] regional network queued "..key)
 return true,false
end
local function plan(job)
 local meta=job.meta
 local minX,minY=math.max(-256,meta:getMinX()*256),math.max(0,meta:getMinY()*256)
 local maxX,maxY=math.min(20224,(meta:getMaxX()+1)*256),math.min(18176,(meta:getMaxY()+1)*256)
 local xs,ys={[minX]=true,[maxX]=true},{[minY]=true,[maxY]=true}
 for _,r in ipairs(WR.REGIONS) do for _,a in ipairs(r.areas) do
  for _,x in ipairs({a[1],a[3]}) do if x>minX and x<maxX then xs[x]=true end end
  for _,y in ipairs({a[2],a[4]}) do if y>minY and y<maxY then ys[y]=true end end
 end end
 local xx,yy={},{};for x in pairs(xs) do xx[#xx+1]=x end;for y in pairs(ys) do yy[#yy+1]=y end
 table.sort(xx);table.sort(yy)
 job.xx=xx;job.yy=yy;job.i=1;job.j=1;job.x=xx[1];job.y=yy[1]
 job.phase=job.any and "create" or "done"
 print("[WaterRestoration] regional bounds "..minX..","..minY.." to "..maxX..","..maxY)
end
local function step(job)
 local meta=job.meta
 if job.phase=="scan" then
  local zones=meta:getZones()
  for n=1,128 do
   if job.scan>=zones:size() then job.phase="remove";return end
   local z=zones:get(job.scan);job.scan=job.scan+1
   if string.sub(tostring(z:getName()),1,13)=="WR_Regional__" then job.stale[#job.stale+1]=z end
  end
 elseif job.phase=="remove" then
  local z=job.stale[job.index]
  if z then meta:removeZone(z);job.index=job.index+1 else plan(job) end
 elseif job.phase=="create" then
  local xx,yy=job.xx,job.yy
  if job.i>=#xx then job.phase="done";return end
  local x,y=job.x,job.y
  local w=math.min(256-x%256,xx[job.i+1]-x)
  local h=math.min(256-y%256,yy[job.j+1]-y)
  assert(w>0 and h>0,"Invalid regional zone dimensions")
  local region=WR.regionAt(x,y)
  if (not region or not job.supply[region.id]) and
     (not meta.getCellData or meta:getCellData(math.floor(x/256),math.floor(y/256))) then
   assert(job.world:registerZone("WR_Regional__"..x.."_"..y,"NoWater",x,y,0,w,h),"NoWater zone rejected")
   job.created=job.created+1
  end
  job.y=y+h
  if job.y>=yy[job.j+1] then
   job.y=yy[job.j];job.x=x+w
   if job.x>=xx[job.i+1] then
    job.j=job.j+1;job.x=xx[job.i]
    if job.j>=#yy then job.j=1;job.i=job.i+1;job.x=xx[job.i] end
    job.y=yy[job.j]
   end
  end
 end
end
function N.update()
 local job=N.job;if not job then return end
 for i=1,8 do
  local ok,err=pcall(step,job)
  if not ok then
   N.job=nil;N.key=nil;N.error=tostring(err)
   print("[WaterRestoration] ERROR regional network: "..N.error);return
  end
  if job.phase=="done" then
   N.key=job.key;N.meta=job.meta;N.job=nil
   print("[WaterRestoration] regional network ready "..N.key.." zones="..job.created)
   if WR.Server and WR.Server.refreshNetwork then WR.Server.refreshNetwork() end
   return
  end
 end
end
if Events and Events.OnTick then Events.OnTick.Add(N.update) end

-- Only an actual console object qualifies; never search a wall/floor's square for it.
function WR.isConsoleObject(object)
 if not object then return false end
 local sprite=object:getSprite();local props=sprite and sprite:getProperties()
 local name=props and props:get("CustomName")
 if name=="Terminal" or name=="Computer" then return true end
 -- Verified against the installed Tiles2x atlas: industrial electrical control faces.
 local id=tonumber((sprite and sprite:getName() or ""):match("^industry_02_(%d+)$"))
 local panels={[163]=true,[164]=true,[165]=true,[168]=true,[169]=true,[170]=true,[171]=true,[172]=true,[175]=true}
 return id~=nil and panels[id]==true
end
function WR.stationTargetObject(object)
 if not WR.isConsoleObject(object) then return nil end
 local square=object:getSquare()
 if not square or not square:getRoom() or square:getZ()<0 or square:getZ()>2 then return nil end
 for _,r in ipairs(WR.REGIONS) do
  if math.abs(square:getX()-r.x)<=40 and math.abs(square:getY()-r.y)<=40 then
   return {id=r.id,kind="distributor",x=square:getX(),y=square:getY(),z=square:getZ()}
  end
 end
end
-- Server independently checks that the submitted tile really contains a console.
function WR.stationTarget(square)
 if not square then return nil end
 local objects=square:getObjects()
 for i=0,objects:size()-1 do
  local target=WR.stationTargetObject(objects:get(i))
  if target then return target end
 end
end
