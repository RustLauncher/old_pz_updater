require "Vehicles/VehicleDistributions"
local distributionTable = VehicleDistributions[1]

VehicleDistributions.TrailerWaterSmallTrunk = {
   rolls = 2,
   items ={
      "Hammer", 1,
      "Wrench", 3,
      "PipeWrench", 3,
      "PlasticCup", 5,
      "WaterBottleEmpty", 4,
      "BucketEmpty", 3,
      "BlowTorch", 2,
      "RotatorsB42.WaterTrailerTankFilter2", 0.5,
      "RotatorsB42.TShirt_RotatorsBlack", 2,
   },
   junk = {
      rolls = 1,
      items = {
         "PopBottleEmpty", 3,
         "PopEmpty", 3,
         "WaterBottleEmpty", 3,
         "WhiskeyEmpty", 1,
      }
   }
}

VehicleDistributions.TrailerWaterBigTrunk = {
   rolls = 2,
   items ={
      "Hammer", 2,
      "Wrench", 5,
      "LugWrench", 6,
      "PipeWrench", 6,
      "TirePump", 1,
      "BlowTorch", 3,
      "RotatorsB42.WaterTrailerTankFilter2", 0.5,
      "RotatorsB42.TShirt_RotatorsBlack", 0.5,
   },
   junk = {
      rolls = 1,
      items = {
         "PopBottleEmpty", 4,
         "PopEmpty", 4,
         "WaterBottleEmpty", 4,
         "WhiskeyEmpty", 1,
      }
   }
}

VehicleDistributions.WaterTrailerSmallBox = {
   TruckBed = VehicleDistributions.TrailerWaterSmallTrunk;
   TrunkLeft = VehicleDistributions.TrailerWaterSmallTrunk;
   --TrunkRight = VehicleDistributions.TrailerWaterSmallTrunk;
}

VehicleDistributions.WaterTrailerBigBox = {
   TruckBed = VehicleDistributions.TrailerWaterBigTrunk;
}

distributionTable["TrailerWaterSmall"] = { Normal = VehicleDistributions.WaterTrailerSmallBox; }
distributionTable["TrailerWaterBig"] = { Normal = VehicleDistributions.WaterTrailerBigBox; }
