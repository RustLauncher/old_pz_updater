-- VFluid owns the propane unit system. Most trailers spawn empty; a minority
-- contain a modest find, while VehicleEasyUse starts them half full.

if not (VFluid and VFluid.updateVehicle) then return end

VFluid.updateVehicle("TrailerPropane", { spawn = {
	["800PropaneTank"] = function(vehicle, part, axis, capacity, rand)
		if SandboxVars.VehicleEasyUse then return capacity / 2 end
		if rand(100) < 20 then return rand(40, 160) end
		return 0
	end,
} })
