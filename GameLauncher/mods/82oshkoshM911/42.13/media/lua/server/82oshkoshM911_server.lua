require "DAMN_Parts";
require "DAMN_Spawns";

--***********************************************************
--**                   KI5 / bikinihorst                   **
--***********************************************************

DAMN.Parts:processConfigV2("M911", {
    ["Bullbar"] = {
		partId = "DAMNBumperFront",
		itemToModel = {
			["Base.M911Bullbar0"] = "Bullbar0",
            ["Base.M911Bullbar1"] = "Bullbar1",
		},
		default = "random",
	},
    ["WindshieldArmor"] = {
		partId = "DAMNWindshieldArmor",
		itemToModel = {
			["Base.M911WindshieldArmor"] = "WindshieldArmor",
		},
	},
	["DoorFrontLeftArmor"] = {
		partId = "DAMNFrontLeftArmor",
		itemToModel = {
			["Base.M911CarFrontDoorArmor"] = "DoorFrontLeftArmor",
		},
	},
	["DoorFrontRightArmor"] = {
		partId = "DAMNFrontRightArmor",
		itemToModel = {
			["Base.M911CarFrontDoorArmor"] = "DoorFrontRightArmor",
		},
	},
    ["WindshieldRearArmor"] = {
		partId = "DAMNWindshieldRearArmor",
		itemToModel = {
			["Base.M911WindshieldRearArmor"] = "WindshieldRearArmor",
		},
	},
    ["SpareTire"] = {
		partId = "DAMNSpareTire",
		itemToModel = {
			["runFlat.LargeTire"] = "SpareTire",
		},
        default = "trve_random",
		noPartChance = 10,
	},
    ["Mudflaps"] = {
		partId = "DAMNMudflaps",
		itemToModel = {
			["Base.M911Mudflaps"] = "Mudflaps",
		},
        default = "trve_random",
		noPartChance = 35,
	},
});

DAMN.Spawns:add("Base.82oshkoshM911", 10304, 9635, {
    direction = IsoDirections.W, 
    chance = 50,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 12505, 4129, {
    direction = IsoDirections.S, 
    chance = 40,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 13760, 5681, {
    direction = IsoDirections.N, 
    chance = 28,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 10354, 9405, {
    direction = IsoDirections.S, 
    chance = 33,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 10159, 12781, {
    direction = IsoDirections.N, 
    chance = 20,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 10094, 11197, {
    direction = IsoDirections.W, 
    chance = 70,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911", 8157, 11475, {
    direction = IsoDirections.N, 
    chance = 60,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM127stake", 10105, 11196, {
    direction = IsoDirections.W, 
    chance = 100,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM127stake", 10340, 9268, {
    direction = IsoDirections.S, 
    chance = 80,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM127stake", 10344, 9268, {
    direction = IsoDirections.S, 
    chance = 50,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM128van", 10264, 9250, {
    direction = IsoDirections.N, 
    chance = 30,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM129van", 10356, 9677, {
    direction = IsoDirections.W, 
    chance = 20,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM129van", 10027, 10927, {
    direction = IsoDirections.N, 
    chance = 80,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM129van", 8168, 11353, {
    direction = IsoDirections.S, 
    chance = 70,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM128van", 8172, 11353, {
    direction = IsoDirections.S, 
    chance = 60,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM747lowbed", 8176, 11353, {
    direction = IsoDirections.S, 
    chance = 50,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM747lowbed", 12708, 5775, {
    direction = IsoDirections.S, 
    chance = 58,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM747lowbed", 14114, 5469, {
    direction = IsoDirections.E, 
    chance = 64,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM967tanker", 12134, 1628, {
    direction = IsoDirections.E, 
    chance = 90,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM967tanker", 12084, 1400, {
    direction = IsoDirections.S, 
    chance = 100,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM967tanker", 12078, 1401, {
    direction = IsoDirections.S, 
    chance = 90,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM127stake", 12072, 1271, {
    direction = IsoDirections.S, 
    chance = 100,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM128van", 12076, 1271, {
    direction = IsoDirections.S, 
    chance = 90,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.TrailerM129van", 12080, 1271, {
    direction = IsoDirections.S, 
    chance = 100,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911B", 5712, 12432, {
    direction = IsoDirections.W, 
    chance = 95,
    sandboxVar = "AllowOinkerSpawns",
});

DAMN.Spawns:add("Base.82oshkoshM911B", 13638, 4071, {
    direction = IsoDirections.E, 
    chance = 95,
    sandboxVar = "AllowOinkerSpawns",
});

function M911.ContainerAccess.TruckBed2(vehicle, part, chr)
	if chr:getVehicle() then return false end
	if not vehicle:isInArea(part:getArea(), chr) then return false end
	local TruckBed2 = vehicle:getPartById("TrunkDoor2")
	if TruckBed2 and TruckBed2:getDoor() then
		if not TruckBed2:getInventoryItem() then return true end
		if not TruckBed2:getDoor():isOpen() then return false end
	end
	--
	return true
end

function M911.ContainerAccess.TruckBed3(vehicle, part, chr)
	if chr:getVehicle() then return false end
	if not vehicle:isInArea(part:getArea(), chr) then return false end
	local TruckBed3 = vehicle:getPartById("TrunkDoor3")
	if TruckBed3 and TruckBed3:getDoor() then
		if not TruckBed3:getInventoryItem() then return true end
		if not TruckBed3:getDoor():isOpen() then return false end
	end
	--
	return true
end