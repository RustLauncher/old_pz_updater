require "WaterRestoration/WR_Config"
WR.Service=WR.Service or {}
local P=WR.Service
function P.day()
 local options=getSandboxOptions()
 return getGameTime():getWorldAgeHours()/24+((options.getTimeSinceApo and options:getTimeSinceApo() or 1)-1)*30
end
function P.update(data)
 local options=getSandboxOptions()
 if data.originalWaterShutModifier==nil then data.originalWaterShutModifier=options:getWaterShutModifier() end
 -- Persist the transition: changing dates or loading a save never reinitializes repairs.
 if data.wasActivated or P.day()>=data.originalWaterShutModifier then data.restorationStarted=true end
 data.originalService=data.restorationStarted~=true
 return data.originalService
end
function P.remaining(data) return math.max(0,(data.originalWaterShutModifier or -1)-P.day()) end
