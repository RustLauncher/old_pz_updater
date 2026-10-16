require "WaterRestoration/WR_Power"
local A={}
function A.stop()
 if A.emitter then A.emitter:stopAll();local world=getWorld();if world then world:returnOwnershipOfEmitter(A.emitter) end end
 A.emitter=nil;A.sound=nil
end
function A.update()
 if A.emitter then A.emitter:tick() end
 local p=getPlayer();local state=WR.ClientState or {}
 if not p or state.originalService or not WR.Power.generatorAvailable(state) then A.stop();return end
 local dx,dy=p:getX()-8055,p:getY()-15363;local distance=math.sqrt(dx*dx+dy*dy+(p:getZ()*4)^2)
 if distance>65 then A.stop();return end
 local world=getWorld();if not world then return end
 if not A.emitter then A.emitter=world:getFreeEmitter(8055.5,15363.5,0);if not A.emitter then return end;world:takeOwnershipOfEmitter(A.emitter) end
 if not A.sound or not A.emitter:isPlaying(A.sound) then A.sound=A.emitter:playSoundLooped("GeneratorLoop") end
 if A.sound then A.emitter:setVolume(A.sound,.55*math.max(0,1-distance/65)) end
end
Events.OnTick.Add(A.update)
Events.OnMainMenuEnter.Add(A.stop)
Events.OnGameStart.Add(A.stop)
