-- The restored propane trailer uses the normal vehicle-zone system and remains
-- deliberately rare: it is primarily a collection vessel, not free fuel.

require "VehicleZoneDefinition"

VehicleZoneDistribution = VehicleZoneDistribution or {}

local function add(zoneName, chance)
	local zone = VehicleZoneDistribution[zoneName]
	if not zone then
		zone = {}
		VehicleZoneDistribution[zoneName] = zone
	end
	zone.vehicles = zone.vehicles or {}
	zone.vehicles["PropaneTrailer.TrailerPropane"] = {
		index = -1,
		spawnChance = chance,
	}
end

add("fossoil", 2)
add("farm", 2)
add("trailerpark", 1)
add("parkingstall", 0.5)
