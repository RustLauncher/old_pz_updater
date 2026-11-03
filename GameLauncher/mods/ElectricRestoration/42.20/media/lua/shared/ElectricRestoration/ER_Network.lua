require "ElectricRestoration/ER_Core"
ER.Network=ER.Network or {}
local N=ER.Network
local function desired(data,plantEnabled)
 if plantEnabled==nil then plantEnabled=data.online end
 if data.originalService then return "original-service",false,{},false end
 local day=data.serverDay or getGameTime():getWorldAgeHours()/24
 local localPower=ER.Core.plantReady(data)
 local key="v4"..(localPower and "P" or "-");local any=localPower;local supply={}
 for _,r in ipairs(ER.REGIONS) do
  local on=ER.regionSupplied(data,r.id,day,plantEnabled)
  supply[r.id]=on;key=key..(on and "1" or "0");any=any or on
 end
 return key,any,supply,localPower
end
function N.sync(data,plantEnabled)
 local world=getWorld and getWorld();local meta=world and world:getMetaGrid()
 if not meta then return false,"Meta grid not ready" end
 local key,any,supply,localPower=desired(data,plantEnabled)
 if N.job and N.job.key==key and N.job.meta==meta then return true,false end
 if not N.job and N.key==key and N.meta==meta then return true,any end
 -- Explicit cursors survive event callbacks without suspended Lua coroutines.
 N.key=nil;N.error=nil
 N.job={key=key,any=any,supply=supply,localPower=localPower,world=world,meta=meta,
  phase="scan",scan=0,stale={},index=1,created=0}
 print("[ElectricRestoration] regional network queued "..key)
 return true,false
end
local function plan(job)
 local meta=job.meta
 local minX,minY=math.max(-256,meta:getMinX()*256),math.max(0,meta:getMinY()*256)
 local maxX,maxY=math.min(20224,(meta:getMaxX()+1)*256),math.min(18176,(meta:getMaxY()+1)*256)
 local xs,ys={[minX]=true,[maxX]=true},{[minY]=true,[maxY]=true}
 for _,r in ipairs(ER.REGIONS) do for _,a in ipairs(r.areas) do
  for _,x in ipairs({a[1],a[3]}) do if x>minX and x<maxX then xs[x]=true end end
  for _,y in ipairs({a[2],a[4]}) do if y>minY and y<maxY then ys[y]=true end end
 end end
 for _,a in ipairs(ER.PLANT_AREAS) do
  for _,x in ipairs({a[1],a[3]}) do if x>minX and x<maxX then xs[x]=true end end
  for _,y in ipairs({a[2],a[4]}) do if y>minY and y<maxY then ys[y]=true end end
 end
 local xx,yy={},{};for x in pairs(xs) do xx[#xx+1]=x end;for y in pairs(ys) do yy[#yy+1]=y end
 table.sort(xx);table.sort(yy)
 job.xx=xx;job.yy=yy;job.i=1;job.j=1;job.x=xx[1];job.y=yy[1]
 job.phase=job.any and "create" or "done"
 print("[ElectricRestoration] regional bounds "..minX..","..minY.." to "..maxX..","..maxY)
end
local function step(job)
 local meta=job.meta
 if job.phase=="scan" then
  local zones=meta:getZones()
  for n=1,128 do
   if job.scan>=zones:size() then job.phase="remove";return end
   local z=zones:get(job.scan);job.scan=job.scan+1
   if string.sub(tostring(z:getName()),1,13)=="ER_Regional__" then job.stale[#job.stale+1]=z end
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
  local region=ER.regionAt(x,y)
  if not (job.localPower and ER.inPlant(x,y)) and (not region or not job.supply[region.id]) and
     (not meta.getCellData or meta:getCellData(math.floor(x/256),math.floor(y/256))) then
   assert(job.world:registerZone("ER_Regional__"..x.."_"..y,"NoPower",x,y,0,w,h),"NoPower zone rejected")
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
   print("[ElectricRestoration] ERROR regional network: "..N.error);return
  end
  if job.phase=="done" then
   N.key=job.key;N.meta=job.meta;N.job=nil
   print("[ElectricRestoration] regional network ready "..N.key.." zones="..job.created)
   if ER.Server and ER.Server.refreshNetwork then ER.Server.refreshNetwork() end
   return
  end
 end
end
if Events and Events.OnTick then Events.OnTick.Add(N.update) end

