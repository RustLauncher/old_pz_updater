-- Specialty bags: additive world loot, registered after distribution merging.
-- These are relative weights, NOT percentage chances.
require "Items/ProceduralDistributions"

local entries = {
    {"MechanicShelfTools", "BolsasEspecialidades.Bag_Mecanica", 3},
    {"MechanicShelfElectric", "BolsasEspecialidades.Bag_Mecanica", 1.5},
    {"GarageTools", "BolsasEspecialidades.Bag_Mecanica", 1},
    {"FishingStoreGear", "BolsasEspecialidades.Bag_Pesca", 3},
    {"CampingStoreGear", "BolsasEspecialidades.Bag_Pesca", 1},
    {"CampingStoreBackpacks", "BolsasEspecialidades.Bag_Caca", 3},
    {"HuntingLockers", "BolsasEspecialidades.Bag_Caca", 3},
    {"CampingStoreGear", "BolsasEspecialidades.Bag_Caca", 1},
    {"GunStoreCases", "BolsasEspecialidades.Bag_Firearms", 3},
    {"GunStoreAmmunition", "BolsasEspecialidades.Bag_Firearms", 1.5},
    {"GunStoreAccessories", "BolsasEspecialidades.Bag_Firearms", 2},
    {"ToolStoreCarpentry", "BolsasEspecialidades.Bag_Carpintaria", 3},
    {"CrateTools", "BolsasEspecialidades.Bag_Carpintaria", 1},
}

local function registerBags()
    local registered = 0
    for _, entry in ipairs(entries) do
        local distribution = ProceduralDistributions.list[entry[1]]
        if distribution and distribution.items then
            local items = distribution.items
            local found = false
            for i = 1, #items, 2 do
                if items[i] == entry[2] then
                    items[i + 1] = entry[3]
                    found = true
                    break
                end
            end
            if not found then
                table.insert(items, entry[2])
                table.insert(items, entry[3])
            end
            registered = registered + 1
        else
            print("[BolsasDeEspecialidades] Missing loot list: " .. entry[1])
        end
    end
    print("[BolsasDeEspecialidades] Spawn revision 2: " .. registered .. "/" .. #entries .. " loot entries registered.")
end

Events.OnPostDistributionMerge.Add(registerBags)
