if VehicleZoneDistribution then
    ---CostumesVan---
    
    -- Definir la camioneta "CostumesVan" en diferentes zonas de spawn
    VehicleZoneDistribution.parkingstall.vehicles["Base.CostumesVan"] = {index = -1, spawnChance = 1};
    VehicleZoneDistribution.bad.vehicles["Base.CostumesVan"] = {index = -1, spawnChance = 1};
    VehicleZoneDistribution.trailerpark.vehicles["Base.CostumesVan"] = {index = -1, spawnChance = 1};
    VehicleZoneDistribution.junkyard.vehicles["Base.CostumesVan"] = {index = -1, spawnChance = 1};
    
    -- Definir los atributos especiales de la camioneta "CostumesVan" para spawn
    local specialVehicle = {};
    specialVehicle["Base.CostumesVan"] = {index = -1, spawnChance = 1};

    VehicleZoneDistribution.CostumesVan = {};
    VehicleZoneDistribution.CostumesVan.vehicles = specialVehicle;
    VehicleZoneDistribution.CostumesVan.spawnRate = 1;
    VehicleZoneDistribution.CostumesVan.chanceToSpawnBurnt = 0;
    VehicleZoneDistribution.CostumesVan.baseVehicleQuality = 1.1;
    VehicleZoneDistribution.CostumesVan.chanceToPartDamage = 0;
    VehicleZoneDistribution.CostumesVan.chanceToSpawnKey = 70;
    VehicleZoneDistribution.CostumesVan.chanceToSpawnSpecial = 100;
    VehicleZoneDistribution.CostumesVan.chanceToSpawnNormal = 0;
    VehicleZoneDistribution.CostumesVan.specialCar = true;
end