require "Vehicles/Vehicles"

rWaterTrailer = rWaterTrailer or {}
rWaterTrailer.Vehicle = rWaterTrailer.Vehicle or {
	Create = {},
	ContainerAccess = {}
}

local OPTIONAL_ACCESSORY_CHANCE = 50

function rWaterTrailer.Vehicle.Create.OptionalPart(vehicle, part)
	if ZombRand(100) < OPTIONAL_ACCESSORY_CHANCE then
		VehicleUtils.createPartInventoryItem(part)
	end
end

function rWaterTrailer.Vehicle.Create.OptionalDoor(vehicle, part)
	if ZombRand(100) < OPTIONAL_ACCESSORY_CHANCE then
		Vehicles.Create.Door(vehicle, part)
	end
end

function rWaterTrailer.Vehicle.Create.WaterTank(vehicle, part)
	local invItem = VehicleUtils.createPartInventoryItem(part)

	if not invItem then
		return
	end

	local water = 0
	local chance =
	{
		anyWater = ZombRand(30, 70),
		cleanWater = 5,
		minWater = ZombRand(3, part:getContainerCapacity()/3),
		maxWater = ZombRand(part:getContainerCapacity()/3, part:getContainerCapacity()/2),
		easyUseWater = ZombRand(part:getContainerCapacity()/2, part:getContainerCapacity())
	}

	if SandboxVars.VehicleEasyUse then
		water = chance.easyUseWater
	elseif ZombRand(100) <= chance.anyWater then
		water = ZombRand(chance.minWater, chance.maxWater)
	end

	part:setContainerContentAmount(PZMath.roundToInt(water))
	part:getModData().Tainted = ZombRand(100) > chance.cleanWater

	if getDebug() then
		print(string.format("rWaterTrailer.Vehicle.CreateTank : %s water %d/%d", part:getModData().Tainted and "tainted" or "clean", part:getContainerContentAmount(), part:getContainerCapacity()))
	end
end

function rWaterTrailer.Vehicle.ContainerAccess.TrunkRight(vehicle, part, chr)
	if chr:getVehicle() then return false end
	if not vehicle:isInArea(part:getArea(), chr) then return false end
	local TrunkDoorRight = vehicle:getPartById("TrunkDoorRight")
	if TrunkDoorRight and TrunkDoorRight:getDoor() then
		if not TrunkDoorRight:getInventoryItem() then return true end
		if not TrunkDoorRight:getDoor():isOpen() then return false end
	end
	return true
end

function rWaterTrailer.Vehicle.ContainerAccess.TrunkLeft(vehicle, part, chr)
	if chr:getVehicle() then return false end
	if not vehicle:isInArea(part:getArea(), chr) then return false end
	local TrunkDoorLeft = vehicle:getPartById("TrunkDoorLeft")
	if TrunkDoorLeft and TrunkDoorLeft:getDoor() then
		if not TrunkDoorLeft:getInventoryItem() then return true end
		if not TrunkDoorLeft:getDoor():isOpen() then return false end
	end
	return true
end
