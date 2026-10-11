require 'Items/ProceduralDistributions'

local function insertDist(distName, item, weight)
    if ProceduralDistributions and ProceduralDistributions.list and ProceduralDistributions.list[distName] and ProceduralDistributions.list[distName].items then
        table.insert(ProceduralDistributions.list[distName].items, item)
        table.insert(ProceduralDistributions.list[distName].items, weight)
    end
end

local function insertJunkDist(distName, item, weight)
    if ProceduralDistributions and ProceduralDistributions.list and ProceduralDistributions.list[distName] and ProceduralDistributions.list[distName].junk and ProceduralDistributions.list[distName].junk.items then
        table.insert(ProceduralDistributions.list[distName].junk.items, item)
        table.insert(ProceduralDistributions.list[distName].junk.items, weight)
    end
end

-- Glass Panes
insertDist("CabinetFactoryTools", "ImprovisedGlass.GlassPane", 4)
insertDist("CarSupplyTools", "ImprovisedGlass.GlassPane", 4)
insertDist("CarWindows1", "ImprovisedGlass.GlassPane", 5)
insertDist("CarWindows2", "ImprovisedGlass.GlassPane", 5)
insertDist("CarWindows3", "ImprovisedGlass.GlassPane", 5)
insertDist("CrateCarpentry", "ImprovisedGlass.GlassPane", 5)
insertDist("CrateMechanics", "ImprovisedGlass.GlassPane", 10)
insertDist("CrateMetalwork", "ImprovisedGlass.GlassPane", 3)
insertDist("CratePlaster", "ImprovisedGlass.GlassPane", 8)
insertDist("CrateRandomJunk", "ImprovisedGlass.GlassPane", 1)
insertDist("CrateTools", "ImprovisedGlass.GlassPane", 1)
insertDist("EngineerTools", "ImprovisedGlass.GlassPane", 2)
insertDist("GarageCarpentry", "ImprovisedGlass.GlassPane", 2)
insertDist("GarageMechanics", "ImprovisedGlass.GlassPane", 1)
insertDist("GarageMetalwork", "ImprovisedGlass.GlassPane", 6)
insertDist("GarageTools", "ImprovisedGlass.GlassPane", 1)
insertDist("GigamartTools", "ImprovisedGlass.GlassPane", 2)
insertDist("JanitorMisc", "ImprovisedGlass.GlassPane", 1)
insertDist("JanitorTools", "ImprovisedGlass.GlassPane", 10)
insertDist("MechanicShelfMisc", "ImprovisedGlass.GlassPane", 10)
insertDist("MechanicShelfTools", "ImprovisedGlass.GlassPane", 10)
insertJunkDist("MechanicShelfTools", "ImprovisedGlass.GlassPane", 75)
insertDist("MetalShopTools", "ImprovisedGlass.GlassPane", 10)
insertDist("OtherGeneric", "ImprovisedGlass.GlassPane", 1)
insertDist("RadioFactoryComponents", "ImprovisedGlass.GlassPane", 10)
insertDist("ToolStoreCarpentry", "ImprovisedGlass.GlassPane", 7)
insertDist("ToolStoreMetalwork", "ImprovisedGlass.GlassPane", 6)
insertDist("ToolStoreMisc", "ImprovisedGlass.GlassPane", 5)
insertDist("ToolStoreTools", "ImprovisedGlass.GlassPane", 1)