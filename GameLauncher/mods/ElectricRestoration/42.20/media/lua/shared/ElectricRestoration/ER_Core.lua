require "ElectricRestoration/ER_Config"
ER.Core=ER.Core or {}
local C=ER.Core
function C.initialize(data,seed,hour)
 if data.initialized then return data end
 assert(type(seed)=="number" and seed>=1,"server seed required")
 data.seed=seed;data.version=1;data.machines={};data.terminals={};data.selected={}
 local n=seed%2147483647
 local function random() n=(n*48271)%2147483647;return n/2147483647 end
 -- A shuffled quota prevents unlucky worlds with most machinery broken.
 local goodCount=25+math.floor(random()*11)
 local order={};for i=1,ER.MACHINE_COUNT do order[i]=i end
 for i=ER.MACHINE_COUNT,2,-1 do local j=1+math.floor(random()*i);order[i],order[j]=order[j],order[i] end
 local good={};for i=1,goodCount do good[order[i]]=true end
 for i=1,ER.MACHINE_COUNT do
  local condition=good[i] and (76+math.floor(random()*20)) or (35+math.floor(random()*40))
  data.machines[i]={id=i,condition=condition,wearFactor=.85+random()*.3,revision=0}
 end
 data.initialGoodCount=goodCount
 for _,id in ipairs(ER.TERMINALS) do data.terminals[id]={repaired=false,tested=false,condition=0,revision=0} end
 data.dispatch={repaired=false,condition=0,revision=0};data.selectionRevision=0
 data.commissioned=false;data.online=false;data.lastHour=hour;data.initialized=true
 -- Emergency reserves supply control terminals only, never the regional grid.
 data.controlSupply="emergency_reserve"
 return data
end
function C.demand(data)
 local total=0
 for _,r in ipairs(ER.REGIONS) do if data.selected[r.id] then total=total+r.demand end end
 return total
end
function C.loadFactor(data)
 local load=C.demand(data);return load>0 and (.6+.4*load) or 0
end
function C.plantReady(data,minimum)
 minimum=minimum or ((data.commissioned or data.localCommissioned) and 50 or ER.MINIMUM)
 for _,id in ipairs(ER.TERMINALS) do local t=data.terminals[id];if not t.repaired or not t.tested or t.condition<minimum then return false end end
 if #data.machines~=ER.MACHINE_COUNT then return false end
 for _,m in ipairs(data.machines) do if m.condition<minimum then return false end end
 return true
end
function C.ready(data)
 return data.dispatch.repaired and data.dispatch.condition>=ER.MINIMUM and C.plantReady(data,ER.MINIMUM)
end
function C.runningReady(data)
 return data.dispatch.repaired and data.dispatch.condition>=50 and C.plantReady(data,50)
end
function C.activeRegions(data)
 if data.originalService then return #ER.REGIONS end
 local count=0
 if data.online and data.networkReady~=false and C.runningReady(data) then
  for _,r in ipairs(ER.REGIONS) do if data.selected[r.id] then count=count+1 end end
 end
 return count
end
function C.settle(data,hour)
 local elapsed=math.max(0,hour-data.lastHour)
 if not data.originalService and data.online and elapsed>0 then
  local rate=50/(ER.LIFE_DAYS*24)*C.loadFactor(data)
  -- Stop accrual at the first safety trip, including large time jumps.
  local runningHours=math.min(elapsed,C.hoursUntilService(data))
  for _,m in ipairs(data.machines) do m.condition=math.max(0,m.condition-rate*runningHours*m.wearFactor) end
  for _,t in pairs(data.terminals) do t.condition=math.max(0,t.condition-rate*runningHours) end
  data.dispatch.condition=math.max(0,data.dispatch.condition-rate*runningHours)
  if runningHours<elapsed or not C.runningReady(data) then data.online=false;data.trip="equipment" end
 end
 data.lastHour=hour
end
function C.hoursUntilService(data)
 local rate=50/(ER.LIFE_DAYS*24)*C.loadFactor(data)
 if rate<=0 then return math.huge end
 local hours=math.max(0,data.dispatch.condition-50)/rate
 for _,t in pairs(data.terminals) do hours=math.min(hours,math.max(0,t.condition-50)/rate) end
 for _,m in ipairs(data.machines) do hours=math.min(hours,math.max(0,m.condition-50)/(rate*m.wearFactor)) end
 return hours
end
function C.selection(data,selection,expected,hour)
 if expected~=data.selectionRevision then return false,"stale" end
 local known={};for _,r in ipairs(ER.REGIONS) do known[r.id]=true end
 for id,value in pairs(selection) do if not known[id] or type(value)~="boolean" then return false,"invalid" end end
 C.settle(data,hour)
 data.selected={};for id,value in pairs(selection) do if value then data.selected[id]=true end end
 data.selectionRevision=data.selectionRevision+1
 -- Saving a dispatch plan never energizes it implicitly.
 data.online=false
 return true
end
function C.start(data,hour)
 C.settle(data,hour)
 if not C.ready(data) or C.demand(data)<=0 then return false end
 data.commissioned=true;data.online=true;data.trip=nil;return true
end
function C.repairMachine(data,id,expected,hour)
 C.settle(data,hour)
 local m=data.machines[id]
 if not m or m.revision~=expected or m.condition>=100 then return false,"stale" end
 m.condition=math.min(100,m.condition+25);m.revision=m.revision+1;return true
end
function ER.regionSupplied(data,id,day,enabled)
 if data.originalService then return true end
 return (enabled==nil and data.online or enabled)==true and data.selected[id]==true and C.runningReady(data)
end
