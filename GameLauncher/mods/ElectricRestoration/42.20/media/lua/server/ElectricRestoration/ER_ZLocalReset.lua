require "ElectricRestoration/ER_Server"
local expectedWorld="gg - Electric Restoration"
local marker="ER_reset_test_world.txt"
local function correctWorld()
 local name=tostring(getWorld():getWorld());return name==expectedWorld or name=="Sandbox/"..expectedWorld
end
local function installLinkReset()
 if not WR or not WR.Laptop or WR.Laptop.electricResetInstalled then return end
 local L=WR.Laptop;local previous=L.data
 L.data=function(item)
  local d=previous(item)
  if correctWorld() then
   local token=ER.Server.data().testResetToken
   if token and d.electricResetToken~=token then
    d.links=d.links or {};d.links.electric=nil;d.electricResetToken=token;d.revision=(d.revision or 0)+1
   end
  end
  return d
 end
 L.electricResetInstalled=true
 local player=getPlayer()
 if player then L.walk(player:getInventory(),function(item) if L.isLaptop(item) then L.data(item) end end) end
end
Events.OnGameStart.Add(function()
 if isClient() or not correctWorld() then return end
 local reader=getFileReader(marker,false);local request
 if reader then request=reader:readLine();reader:close() end
 if request and request:match("^pending:") then
  local token=request:sub(9);local data=ER.Server.data()
  if data.testResetToken~=token then
   for key in pairs(data) do data[key]=nil end
   ER.Core.initialize(data,ZombRand(2147483645)+1,getGameTime():getWorldAgeHours())
   data.testResetToken=token;data.commissioned=true;data.online=false
   local player=getPlayer();if player then player:getModData().ERManualRead=false end
   ER.Network.key=nil;ER.Network.sync(data,false);ER.Server.applied=nil;ER.Server.updatePower()
   ModData.transmit(ER.DATA_KEY);if player then ER.Server.send(player) end
  end
  local writer=getFileWriter(marker,true,false);writer:write("completed:"..token.."\n");writer:close()
  print("[ElectricRestoration] one-time test reset completed")
 end
 installLinkReset()
end)
