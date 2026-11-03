require "ElectricRestoration/ER_Config"
ER.Service=ER.Service or {}
local P=ER.Service
function P.day()
 local options=getSandboxOptions()
 return getGameTime():getWorldAgeHours()/24+((options.getTimeSinceApo and options:getTimeSinceApo() or 1)-1)*30
end
function P.update(data)
 local options=getSandboxOptions()
 if data.originalElecShutModifier==nil then data.originalElecShutModifier=options:getElecShutModifier() end
 -- Persist the transition: changing dates or loading a save never reinitializes repairs.
 if data.commissioned or data.localCommissioned or P.day()>=data.originalElecShutModifier then data.restorationStarted=true end
 data.originalService=data.restorationStarted~=true
 return data.originalService
end
function P.remaining(data) return math.max(0,(data.originalElecShutModifier or -1)-P.day()) end
