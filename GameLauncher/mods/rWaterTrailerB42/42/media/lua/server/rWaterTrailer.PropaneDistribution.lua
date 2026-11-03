-- Propane-themed trunk loot at lower rates than the vanilla propane truck.

require "Vehicles/VehicleDistributions"

local distributionTable = VehicleDistributions[1]

VehicleDistributions.PropaneTrailerTrunk = {
	rolls = 2,
	items = {
		"PropaneTank", 40,
		"PropaneTank", 20,
		"RubberHose", 20,
		"PipeWrench", 10,
		"Wrench", 10,
		"Gloves_LeatherGloves", 10,
	},
	junk = {
		rolls = 1,
		items = {},
	},
}

VehicleDistributions.PropaneTrailerBox = {
	TruckBed = VehicleDistributions.PropaneTrailerTrunk;
}

distributionTable["TrailerPropane"] = {
	Normal = VehicleDistributions.PropaneTrailerBox;
}
