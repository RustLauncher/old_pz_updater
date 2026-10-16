require "ElectricRestoration/ER_Core"
ER.Ambience=ER.Ambience or {}
local A=ER.Ambience
A.volume=.22
A.indoorMultiplier=.35
function A.indoorGain(player)
 local sq=player and player:getSquare()
 return sq and (sq:getRoom() or (sq.isOutside and not sq:isOutside())) and A.indoorMultiplier or 1
end
function A.gainAt(x,y,z)
 local nearest,bx,by=math.huge,nil,nil
 for _,b in ipairs(ER.PLANT_AREAS) do
  local px=math.max(b[1],math.min(b[3]-1,x));local py=math.max(b[2],math.min(b[4]-1,y))
  local distance=math.sqrt((x-px)^2+(y-py)^2+(z*4)^2)
  if distance<nearest then nearest=distance;bx=px;by=py end
 end
 local t=math.max(0,1-nearest/80)
 return t*t*(3-2*t),bx,by
end
function A.stop()
 if A.emitter then
  A.emitter:stopAll()
  local world=getWorld();if world then world:returnOwnershipOfEmitter(A.emitter) end
 end
 A.emitter=nil;A.sound=nil;A.phase=nil
end
function A.update()
 if A.emitter then A.emitter:tick() end
 local now=getTimestampMs()
 if A.lastTick and now-A.lastTick<100 then return end
 A.lastTick=now
 local player=getPlayer();local data=ER.State or {}
 if not player or not data.initialized then A.stop();return end
 local ready=data.originalService or ER.Core.plantReady(data)
 local gain,x,y=A.gainAt(player:getX(),player:getY(),player:getZ())
 if ready and A.previousReady==false and gain>0 then A.startupAt=now end
 A.previousReady=ready
 if not ready then A.stop();A.startupAt=nil;return end
 if gain<=0 then A.stop();A.startupAt=nil;return end
 local world=getWorld();if not world then return end
 if not A.emitter then
  A.emitter=world:getFreeEmitter(x+.5,y+.5,0)
  if not A.emitter then return end
  world:takeOwnershipOfEmitter(A.emitter)
 end
 A.emitter:setPos(x+.5,y+.5,0)
 local starting=A.startupAt and now-A.startupAt<3000
 local phase=starting and "startup" or "ambient"
 if phase~=A.phase then
  if A.sound then A.emitter:stopSound(A.sound) end
  A.sound=nil;A.phase=phase
 end
 if not A.sound or (not starting and not A.emitter:isPlaying(A.sound)) then
  if starting then A.sound=A.emitter:playSound("ER_PlantStartup")
  else A.sound=A.emitter:playSoundLooped("ER_PlantAmbient") end
  A.emitter:tick()
 end
 local volume=starting and .30 or A.volume
 if A.sound then A.emitter:setVolume(A.sound,volume*gain*A.indoorGain(player)) end
end
function A.reset() A.stop();A.previousReady=nil;A.startupAt=nil;A.lastTick=nil end
Events.OnTick.Add(A.update)
Events.OnMainMenuEnter.Add(A.reset)
Events.OnGameStart.Add(A.reset)
