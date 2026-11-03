WR = WR or {}

WR.MOD_ID = "WaterRestoration"
WR.MAINTENANCE_DURATION_MULTIPLIER = 1.20
WR.DATA_KEY = "WaterRestorationData"
WR.MANUAL_ITEM = "Base.WaterPlantManual"
WR.TARGET_TOLERANCE = 1

WR.TARGETS = {
    central = { id = "central", kind = "central", x = 8044, y = 15360, z = 0 },
    panel1 = { id = "panel1", kind = "panel", x = 8055, y = 15360, z = 0 },
    panel2 = { id = "panel2", kind = "panel", x = 8063, y = 15360, z = 0 },
    panel3 = { id = "panel3", kind = "panel", x = 8071, y = 15360, z = 0 },
    roundValve1 = { id = "roundValve1", kind = "valve", x = 8065, y = 15326, z = 0 },
    roundValve2 = { id = "roundValve2", kind = "valve", x = 8065, y = 15309, z = 0 },
    roundValve3 = { id = "roundValve3", kind = "valve", x = 8065, y = 15291, z = 0 },
    basinValve1 = { id = "basinValve1", kind = "valve", x = 8039, y = 15302, z = 0 },
    basinValve2 = { id = "basinValve2", kind = "valve", x = 8032, y = 15302, z = 0 },
    basinValve3 = { id = "basinValve3", kind = "valve", x = 8025, y = 15302, z = 0 },
    basinValve4 = { id = "basinValve4", kind = "valve", x = 8018, y = 15302, z = 0 },
}

WR.PANEL_IDS = { "panel1", "panel2", "panel3" }
WR.VALVE_IDS = {
    "roundValve1", "roundValve2", "roundValve3",
    "basinValve1", "basinValve2", "basinValve3", "basinValve4",
}
WR.COMPUTER_IDS = { "central", "panel1", "panel2", "panel3" }

WR.OFFICE_AREA = { minX = 7980, maxX = 8038, minY = 15245, maxY = 15290, minZ = 0, maxZ = 1 }

local DEFAULTS = {
    electricity = 7,
    mechanics = 7,
    strength = 6,
    centralScrap = 10,
    panelScrap = 10,
    maintenanceScrap = 2,
    maintenanceDays = 21,
}

local function option(name, fallback)
    local ok, value = pcall(function()
        local found = getSandboxOptions():getOptionByName("WaterRestoration." .. name)
        return found and found:getValue() or nil
    end)
    if ok and value ~= nil then return value end
    return fallback
end

function WR.getRequirements()
    return {
        electricity = option("ElectricityLevel", DEFAULTS.electricity),
        mechanics = option("MechanicsLevel", DEFAULTS.mechanics),
        strength = option("StrengthLevel", DEFAULTS.strength),
        centralScrap = math.max(10, option("CentralScrap", DEFAULTS.centralScrap)),
        panelScrap = math.max(10, option("PanelScrap", DEFAULTS.panelScrap)),
        stationScrap = 9,
        maintenanceScrap = option("MaintenanceScrap", DEFAULTS.maintenanceScrap),
        maintenanceDays = math.min(21, option("MaintenanceDays", DEFAULTS.maintenanceDays)) * WR.MAINTENANCE_DURATION_MULTIPLIER,
    }
end

function WR.findTargetAt(x, y, z)
    local best, bestDistance = nil, math.huge
    for _, target in pairs(WR.TARGETS) do
        if z == target.z then
            local distance = math.abs(x - target.x) + math.abs(y - target.y)
            if distance <= WR.TARGET_TOLERANCE and distance < bestDistance then
                best, bestDistance = target, distance
            end
        end
    end
    return best
end

function WR.isInsideOffice(x, y, z)
    local a = WR.OFFICE_AREA
    return x >= a.minX and x <= a.maxX and y >= a.minY and y <= a.maxY and z >= a.minZ and z <= a.maxZ
end

print("[WaterRestoration] shared configuration loaded")

-- Use the same explicit item traversal for UI validation and material consumption.
function WR.getElectronicScrap(inventory)
    local result = {}
    local function visit(container)
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getFullType() == "Base.ElectronicsScrap" then
                result[#result + 1] = item
            end
            if instanceof(item, "InventoryContainer") then visit(item:getInventory()) end
        end
    end
    visit(inventory)
    return result
end

function WR.countElectronicScrap(inventory)
    return #WR.getElectronicScrap(inventory)
end

WR.ALL_IDS = { "central", "panel1", "panel2", "panel3", "roundValve1", "roundValve2", "roundValve3", "basinValve1", "basinValve2", "basinValve3", "basinValve4" }
function WR.condition(data, id, day)
    local ready = id == "central" and data.centralRepaired or data.panels[id] or data.valves[id]
    if not ready then return 0 end
    if not data.wasActivated then return 100 end
    local serviced = data.servicedAt and data.servicedAt[id] or day
    return math.max(0, math.min(100, 100 * (1 - (day - serviced) / WR.getRequirements().maintenanceDays)))
end
function WR.nextService(data)
    local oldest = math.huge
    for _, id in ipairs(WR.ALL_IDS) do oldest = math.min(oldest, data.servicedAt[id] or 0) end
    return oldest + WR.getRequirements().maintenanceDays
end
function WR.showResult(player, message, remaining)
    if not player then return end
    local key = "IGUI_WR_Result_" .. message
    if remaining ~= nil then key = "IGUI_WR_Progress_" .. message .. tostring(remaining) end
    player:Say(getText(key))
    if message == "StationActivated" then player:playSound("WR_StationFlow") end
    if message == "ValveOpened" or string.sub(message,1,6)=="Valve_" then player:playSound("WR_ValveFlow") end
    if message == "WaterActivated" then
        if WR.PlantAmbience then WR.PlantAmbience.beginStartup() end
        player:playSound("WR_WaterReturn")
    end
end

-- Towns and named residential settlements from the installed base-map annotations.
WR.SupplyLocations = {
    {name="West Point", x=11654, y=6864},
    {name="Riverside", x=6450, y=5430},
    {name="Muldraugh", x=10754, y=9926},
    {name="Brandenburg", x=2056, y=6070},
    {name="Ekron", x=634, y=9746},
    {name="Irvington", x=2427, y=14185},
    {name="Echo Creek", x=3589, y=10952},
    {name="Louisville", x=13077, y=2238},
    {name="March Ridge", x=10130, y=12801},
    {name="Fallas Lake", x=7253, y=8279},
    {name="Rosewood", x=8159, y=11661},
    {name="Valley Station", x=13447, y=5278},
    {name="Bright Valley Trailer Park", x=2733, y=6286},
    {name="Coalfield", x=3486, y=8193},
    {name="Dixie Trailer Park", x=11625, y=8830},
    {name="Scenic Grove Trailer Park", x=5381, y=6006},
}

function WR.hasPipeWrench(player)
    return player and player:getInventory():containsTypeRecurse("PipeWrench") or false
end

function WR.interactionTool(target,command)
    if target and target.kind=="valve" then return command=="maintain" and "BlowTorch" or "PipeWrench" end
    if command=="repairCentral" or command=="repairPanel" or command=="repairStation"
        or command=="maintain" or command=="maintainStation" then return "Screwdriver" end
end
