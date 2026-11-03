local distributionTable = VehicleDistributions[1]

VehicleDistributions.M911gunrack = {
    rolls = 1,
    items = {
    	"Shotgun", 150,
    }
}

VehicleDistributions.M911GloveBox = {
    rolls = 1,
    items = {
        "Base.M911Magazine", 60,
        "Base.Pen", 4,
        "Base.Pencil", 4,
        "Base.Cigarettes", 5,
        "Base.Lighter", 5,
        "Base.Matches", 3,
        "Base.Tissue", 2,
    },
    junk = ClutterTables.GloveBoxJunk,
}

VehicleDistributions.M911Trunk = {
    rolls = 2,
    items ={
	"Base.TShirt_OshkoshGray", 5,
	"Base.TShirt_OshkoshBlack", 5,
	"Base.TShirt_bknht", 3,
	"Base.Hoodie_OshkoshBlack", 5,
	"Base.Hoodie_OshkoshGray", 5,
	"Base.EngineParts", 10,
    }
}

VehicleDistributions.M911Toolbox = {
    rolls = 2,
    items ={
	"Base.Axe", 6,
	"Base.Crowbar", 3,
	"Base.Hammer", 5,
	"Base.BlowTorch", 3,
	"Base.Sledgehammer", 2,
	"Base.Screwdriver", 7,
	"Base.Saw", 5,
	"Base.Torch", 5,
	"Base.PetrolCan", 9,
	"Base.Jack", 6,
	"Base.TirePump", 8,
	"Base.Wrench", 8,
	"Base.Extinguisher", 5,
	"Base.CarBatteryCharger", 2,
	"Base.EngineParts", 2,
	"Base.LugWrench", 7,
    }
}

VehicleDistributions.M911Trailers = {
    rolls = 3,
    items ={
	"Base.Axe", 6,
	"Base.Crowbar", 3,
	"Base.Hammer", 5,
	"Base.Sledgehammer", 2,
	"Base.Screwdriver", 7,
	"Base.Saw", 5,
	"Base.Jack", 6,
	"Base.TirePump", 8,
	"Base.Wrench", 8,
	"Base.LugWrench", 7,
    }
}

VehicleDistributions.M911distro = {

	GloveBox = VehicleDistributions.M911GloveBox;
	M911Trunk = VehicleDistributions.M911Trunk;
    M127TrunkFront = VehicleDistributions.M911Trunk;
    M127TrunkRear = VehicleDistributions.M911Trunk;
    M128Trunk = VehicleDistributions.M911Trunk;
    M129Trunk = VehicleDistributions.M911Trunk;
    M747Trunk = VehicleDistributions.M911Trunk;
	M911Toolbox = VehicleDistributions.M911Toolbox;
    M967Trunk1 = VehicleDistributions.M911Toolbox;
    M967Trunk2 = VehicleDistributions.M911Toolbox;
    M967Trunk3 = VehicleDistributions.M911Toolbox;
    TruckBed = VehicleDistributions.M911Trailers;
    DAMNGunrack = VehicleDistributions.M911gunrack,
}

distributionTable["82oshkoshM911"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["82oshkoshM911B"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["82oshkoshM911Burnt"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["TrailerM127stake"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["TrailerM128van"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["TrailerM129van"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["TrailerM747lowbed"] = { Normal = VehicleDistributions.M911distro; }
distributionTable["TrailerM967tanker"] = { Normal = VehicleDistributions.M911distro; }