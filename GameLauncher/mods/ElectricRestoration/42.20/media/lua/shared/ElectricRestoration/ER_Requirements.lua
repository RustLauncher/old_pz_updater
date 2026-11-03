require "ElectricRestoration/ER_Core"
ER.Requirements={}
local R=ER.Requirements
function R.items(inv,kind,out)
 out=out or {};local all=inv:getItems()
 for i=0,all:size()-1 do local item=all:get(i)
  if item:getFullType()=="Base."..kind then out[#out+1]=item end
  if instanceof(item,"InventoryContainer") then R.items(item:getInventory(),kind,out) end
 end
 return out
end
function R.node(data,t)
 if not t then return end
 return t.kind=="machine" and (data.machines or {})[t.index] or (t.id=="dispatch" and data.dispatch or (data.terminals or {})[t.id])
end
function R.check(player,data,t,command)
 local rows={};local ok=true
 local function add(key,have,need,ref)
  local pass=have>=need;rows[#rows+1]={key=key,have=have,need=need,ok=pass,ref=ref};if not pass then ok=false end
 end
 if data.originalService and (command=="repair" or command=="test" or command=="start" or command=="stop") then add("OriginalService",0,1);return false,rows end
 local node=R.node(data,t)
 if not node then add("Loading",0,1);return false,rows end
 local function tested(id)
  local v=(data.terminals or {})[id];add(id,v and v.tested and 1 or 0,1,id)
 end
 -- Gates apply to both the start and the commit of each operation.
 if command=="repair" or command=="test" then
  if t.kind=="machine" then tested("protection");tested("cooling")
  elseif t.id=="dispatch" then for _,id in ipairs(ER.TERMINALS) do tested(id) end
  else
   for i,id in ipairs(ER.TERMINALS) do if id==t.id and i>1 then tested(ER.TERMINALS[i-1]) end end
   if t.id=="regulation" then
    local ready=0;for _,m in ipairs(data.machines or {}) do if m.condition>=ER.MINIMUM then ready=ready+1 end end
    add("MachinesReady",ready,48)
   end
  end
 end
 if command=="repair" then
  add("NeedsService",node.condition<100 and 1 or 0,1)
  local inv=player:getInventory();local machine=t.kind=="machine"
  local read=data.manualRead
  if read==nil then read=player:getModData().ERManualRead==true end
  add("Manual",read and 1 or 0,1)
  add("Electricity",player:getPerkLevel(Perks.Electricity),machine and 8 or 7)
  if not machine then add("Mechanics",player:getPerkLevel(Perks.Mechanics),7);add("Strength",player:getPerkLevel(Perks.Strength),6) end
  add("Screwdriver",#R.items(inv,"Screwdriver"),1)
  if machine then add("Wrench",#R.items(inv,"Wrench"),1) end
  add("ElectronicsScrap",#R.items(inv,"ElectronicsScrap"),machine and 2 or (node.repaired and 2 or 10))
  if machine then add("MetalBar",#R.items(inv,"MetalBar"),2) end
 elseif command=="test" then
  add("RepairFirst",node.repaired and node.condition>=ER.MINIMUM and 1 or 0,1)
  add("NeedsTest",not node.tested and 1 or 0,1)
 elseif command=="start" then
  local machines=0
  for _,m in ipairs(data.machines or {}) do if m.condition>=ER.MINIMUM then machines=machines+1 end end
  add("MachinesMaintenance",machines,ER.MACHINE_COUNT)
  for _,id in ipairs(ER.TERMINALS) do
   local terminal=(data.terminals or {})[id] or {}
   add("TerminalStartup",terminal.repaired and terminal.tested and (terminal.condition or 0)>=ER.MINIMUM and 1 or 0,1,id)
  end
  local dispatch=data.dispatch or {}
  add("DispatchStartup",dispatch.repaired and (dispatch.condition or 0)>=ER.MINIMUM and 1 or 0,1)
  add("SelectRegions",ER.Core.demand(data)>0 and 1 or 0,1)
 end
 return ok,rows
end
function R.label(row)
 local label=getText("IGUI_ER_"..((row.key=="NeedsService" and not row.ok) and "NoRepairNeeded" or row.key))
 if row.ref then local t=ER.TARGETS[row.ref];return label.." / "..t.x..", "..t.y end
 return label
end
function R.missing(rows)
 local parts={}
 for _,r in ipairs(rows or {}) do if not r.ok then
  local value=R.label(r)
  if r.need>1 or r.key=="Screwdriver" or r.key=="Wrench" then value=value.." "..r.have.." / "..r.need end
  parts[#parts+1]=value
 end end
 return table.concat(parts,"; ")
end
