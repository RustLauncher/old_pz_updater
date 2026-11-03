require "WaterRestoration/WR_Config"
WR.PlantAmbience=WR.PlantAmbience or {}
local A=WR.PlantAmbience
-- A distributed ambience over the plant grounds, anchored inside the installation.
A.bounds={minX=7970,maxX=8090,minY=15235,maxY=15390,fade=95}
function A.gainAt(x,y,z)
 local b=A.bounds;local sx=math.max(b.minX,math.min(b.maxX,x));local sy=math.max(b.minY,math.min(b.maxY,y))
 local distance=math.sqrt((x-sx)^2+(y-sy)^2+(z*4)^2)
 local t=math.max(0,1-distance/b.fade)
 return t*t*(3-2*t),sx,sy
end
function A.stop()
 if A.emitter then
  if A.sound then A.emitter:stopSound(A.sound) end
  local world=getWorld();if world then world:returnOwnershipOfEmitter(A.emitter) end
 end
 A.emitter=nil;A.sound=nil
end
function A.beginStartup()
 A.stop()
 A.startupAt=getTimestampMs()
 A.lastTick=nil
end
function A.indoorGain(player)
 local sq=player and player:getSquare()
 if not sq then return 1 end
 if sq:getRoom() or (sq.isOutside and not sq:isOutside()) then return .5 end
 return 1
end
function A.update()
 -- takeOwnershipOfEmitter removes it from IsoWorld's automatic update list.
 -- Owned emitters need a tick every frame, including between position updates.
 if A.emitter then A.emitter:tick() end
 local now=getTimestampMs()
 if A.lastTick and now-A.lastTick<200 then return end
 A.lastTick=now
 local player=getPlayer();local state=WR.ClientState or {}
 if not player or not state.waterActive then A.stop();return end
 local transition=1
 if A.startupAt then
  local elapsed=now-A.startupAt
  if elapsed<12000 then A.stop();return end
  transition=math.min(1,(elapsed-12000)/2000)
  if elapsed>=14000 then A.startupAt=nil end
 end
 local gain,x,y=A.gainAt(player:getX(),player:getY(),player:getZ())
 if gain<=0 then A.stop();return end
 local world=getWorld();if not world then return end
 if not A.emitter then
  A.emitter=world:getFreeEmitter(x+.5,y+.5,0)
  if not A.emitter then return end
  world:takeOwnershipOfEmitter(A.emitter)
 end
 A.emitter:setPos(x+.5,y+.5,0)
 if not A.sound or not A.emitter:isPlaying(A.sound) then
  A.sound=A.emitter:playSoundLooped("WR_PlantWaterAmbient")
  A.emitter:tick()
 end
 if A.sound then A.emitter:setVolume(A.sound,gain*.5355*transition*A.indoorGain(player)) end
end
Events.OnTick.Add(A.update)
Events.OnMainMenuEnter.Add(function() A.stop();A.startupAt=nil end)
Events.OnGameStart.Add(function() A.stop();A.lastTick=nil;A.startupAt=nil end)
