require "WaterRestoration/WR_Config"
function WR.isValveRepair(target,command) return target and target.kind=="valve" and command=="maintain" end
function WR.itemsOfType(inv,kind)
 local out={}
 local function visit(c)
  local items=c:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if item:getFullType()=="Base."..kind then out[#out+1]=item end
   if instanceof(item,"InventoryContainer") then visit(item:getInventory()) end
  end
 end
 visit(inv);return out
end
function WR.repairCost(target,command)
 local q=WR.getRequirements()
 if command=="repairCentral" then return q.centralScrap end
 if command=="repairPanel" then return q.panelScrap end
 if command=="repairStation" then return q.stationScrap end
 if command=="maintainStation" or (command=="maintain" and not WR.isValveRepair(target,command)) then return q.maintenanceScrap end
end
function WR.weldingTools(player)
 local inv=player:getInventory();local torch
 for _,item in ipairs(WR.itemsOfType(inv,"BlowTorch")) do
  if item:getCurrentUsesFloat()+.0001>=item:getUseDelta() then torch=item;break end
 end
 return torch,WR.itemsOfType(inv,"WeldingMask")[1]
end
function WR.canMaterials(player,target,command)
 local inv=player:getInventory();local q=WR.getRequirements()
 if WR.isValveRepair(target,command) then
  local torch,mask=WR.weldingTools(player)
  return player:getPerkLevel(Perks.MetalWelding)>=4 and #WR.itemsOfType(inv,"MetalBar")>=2 and torch~=nil and mask~=nil
 end
 local cost=WR.repairCost(target,command)
 if cost then return player:getPerkLevel(Perks.Electricity)>=q.electricity and player:getPerkLevel(Perks.Mechanics)>=q.mechanics
  and player:getPerkLevel(Perks.Strength)>=q.strength and inv:containsTypeRecurse("Screwdriver") and WR.countElectronicScrap(inv)>=cost end
 if command=="turnValve" then return WR.hasPipeWrench(player) end
 return true
end
function WR.requirementsText(player,target,command)
 local inv=player:getInventory();local q=WR.getRequirements();local lines={}
 local function count(key,have,need) lines[#lines+1]=getText(key).." "..have.." / "..need end
 local function yes(key,value) lines[#lines+1]=getText(key).." "..getText(value and "IGUI_WR_Yes" or "IGUI_WR_No") end
 if WR.isValveRepair(target,command) then
  local torch,mask=WR.weldingTools(player)
  count("IGUI_WR_MetalWelding",player:getPerkLevel(Perks.MetalWelding),4)
  count("IGUI_WR_MetalBars",#WR.itemsOfType(inv,"MetalBar"),2)
  yes("IGUI_WR_FueledTorch",torch~=nil);yes("IGUI_WR_WeldingMask",mask~=nil)
  yes("IGUI_WR_ManualRead",player:getModData().WRManualRead==true)
 elseif WR.repairCost(target,command) then
  count("IGUI_WR_Electricity",player:getPerkLevel(Perks.Electricity),q.electricity)
  count("IGUI_WR_Mechanics",player:getPerkLevel(Perks.Mechanics),q.mechanics)
  count("IGUI_WR_Strength",player:getPerkLevel(Perks.Strength),q.strength)
  count("IGUI_WR_ElectronicsScrap",WR.countElectronicScrap(inv),WR.repairCost(target,command))
  yes("IGUI_WR_Screwdriver",inv:containsTypeRecurse("Screwdriver"))
  yes("IGUI_WR_ManualRead",player:getModData().WRManualRead==true)
 elseif command=="turnValve" then yes("IGUI_WR_PipeWrench",WR.hasPipeWrench(player))
 elseif command=="activateStation" then return getText("IGUI_WR_StationActivationRequirements") end
 return table.concat(lines,"\n")
end
