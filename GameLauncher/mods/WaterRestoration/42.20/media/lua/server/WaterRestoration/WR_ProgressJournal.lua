require "WaterRestoration/WR_Server"
-- Small per-save mission journal survives a crash before the normal world save.
local function path()
 return "WR_progress_"..tostring(getWorld():getWorld()):gsub("[^%w_-]","_")..".txt"
end
local function fields(data)
 local out={centralRepaired=data.centralRepaired,waterActive=data.waterActive,wasActivated=data.wasActivated,
 activatedAt=data.activatedAt,recoveredLaptopFix=data.recoveredLaptopFix}
 for _,id in ipairs(WR.PANEL_IDS) do out["panel_"..id]=data.panels[id] end
 for _,id in ipairs(WR.VALVE_IDS) do out["valve_"..id]=data.valves[id] end
 for _,id in ipairs(WR.ALL_IDS) do out["service_"..id]=data.servicedAt[id] end
 for _,r in ipairs(WR.REGIONS) do local s=data.regions[r.id]
  out["region_"..r.id.."_repaired"]=s.repaired;out["region_"..r.id.."_activated"]=s.activated
  out["region_"..r.id.."_service"]=s.servicedAt
 end
 local g=WR.Power.data(data)
 for _,k in ipairs({"repaired","running","fuel","condition","updatedAt"}) do out["generator_"..k]=g[k] end
 out.powerSuspended=data.powerSuspended
 return out
end
local function save()
 if isClient() then return end
 local writer=getFileWriter(path(),true,false);if not writer then return end
 for key,value in pairs(fields(WR.Server.getData())) do writer:write(key.."="..tostring(value).."\n") end
 writer:close()
end
WR.Server.saveProgressJournal=save
local function restore()
 if isClient() then return end
 local data=WR.Server.getData();local reader=getFileReader(path(),false);local values={}
 if reader then
  local line=reader:readLine()
  while line do local k,v=line:match("^([%w_]+)=(.+)$")
   if k then
    if v=="true" then values[k]=true elseif v=="false" then values[k]=false else values[k]=tonumber(v) end
   end
   line=reader:readLine()
  end
  reader:close()
  local g=WR.Power.data(data)
  for _,k in ipairs({"repaired","running","fuel","condition","updatedAt"}) do if values["generator_"..k]~=nil then g[k]=values["generator_"..k] end end
  if values.powerSuspended~=nil then data.powerSuspended=values.powerSuspended end
  WR.Power.settle(data)
  if data.waterActive and not WR.Power.available(data) then data.waterActive=false;data.powerSuspended=true end
  for _,k in ipairs({"centralRepaired","waterActive","wasActivated","activatedAt","recoveredLaptopFix"}) do
   if values[k]~=nil then data[k]=values[k] end
  end
  for _,id in ipairs(WR.PANEL_IDS) do if values["panel_"..id]~=nil then data.panels[id]=values["panel_"..id] end end
  for _,id in ipairs(WR.VALVE_IDS) do if values["valve_"..id]~=nil then data.valves[id]=values["valve_"..id] end end
  for _,id in ipairs(WR.ALL_IDS) do if values["service_"..id] then data.servicedAt[id]=values["service_"..id] end end
  for _,r in ipairs(WR.REGIONS) do local s=data.regions[r.id]
   for _,k in ipairs({"repaired","activated"}) do if values["region_"..r.id.."_"..k]~=nil then s[k]=values["region_"..r.id.."_"..k] end end
   s.servicedAt=values["region_"..r.id.."_service"] or s.servicedAt
  end
 end
 if data.waterActive and not WR.Power.available(data) then data.waterActive=false;data.powerSuspended=true end
 if data.wasActivated then
  data.maintenanceDueAt=WR.nextService(data)
  if getGameTime():getWorldAgeHours()/24>=data.maintenanceDueAt then data.waterActive=false;data.maintenanceRequired=true end
 end
 WR.Server.refreshNetwork();save()
end
local original=WR.Server.handleCommand
WR.Server.handleCommand=function(...)
 local result=original(...);save();return result
end
Events.OnGameStart.Add(function()
 restore()
 local player=getPlayer();if player and WR.Server.getData().wasActivated then player:getModData().WRManualRead=true end
end)
Events.EveryOneMinute.Add(save)
