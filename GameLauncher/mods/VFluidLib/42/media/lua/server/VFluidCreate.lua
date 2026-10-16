-- Spawn-time create hooks: Tank gives a part its item, FilledTank adds a rolled load and a
-- frozen designation, EmptyTankSlot leaves the slot for the mechanics window.

VFluid = VFluid or {}
VFluid.Create = VFluid.Create or {}

function VFluid.Create.Tank(vehicle, part)
	if not part then return end
	local item = VehicleUtils.createPartInventoryItem(part)
	if not item then return end
end

function VFluid.Create.FilledTank(vehicle, part)
	if not part then return end
	local item = VehicleUtils.createPartInventoryItem(part)
	if not item then return end
	if VFluid.vanillaRules and VFluid.vanillaRules() then
		local ct = part.getContainerContentType and part:getContainerContentType()
		if (ct == "Gasoline" or ct == "Gasoline Storage")
				and Vehicles and Vehicles.Create and Vehicles.Create.GasTank then
			pcall(Vehicles.Create.GasTank, vehicle, part)
		end
		return
	end
	local axis = VFluid.axisFor and VFluid.axisFor(vehicle, part)
	if not axis then return end
	VFluid.applySpawn(vehicle, part, axis)
end

function VFluid.Create.EmptyTankSlot(vehicle, part)
	return
end
