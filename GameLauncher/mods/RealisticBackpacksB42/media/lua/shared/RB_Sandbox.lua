RB_Sandbox = RB_Sandbox or {}
require "RB_CustomizableContainers"

RB_Sandbox.COMMAND_MODULE = "RealisticBackpacksB42"
RB_Sandbox.COMMAND_REFRESH = "RefreshPlayerBackpacks"
RB_Sandbox.COMMAND_REFRESH_COMPLETE = "RefreshPlayerBackpacksComplete"

local VARIANTS = {
    ["Base.Handmade_Sack"] = {
        capacityOption = "HandmadeCapacity",
        weightReductionOption = "HandmadeWeightReduction",
        weightOption = "HandmadeWeight",
        runSpeedOption = "HandmadeRunSpeedModifier",
        capacity = 20,
        weightReduction = 70,
        weight = 0.5,
        runSpeedModifier = 0.95,
    },
    ["Base.Hunting_Backpack"] = {
        capacityOption = "HuntingCapacity",
        weightReductionOption = "HuntingWeightReduction",
        weightOption = "HuntingWeight",
        runSpeedOption = "HuntingRunSpeedModifier",
        capacity = 30,
        weightReduction = 80,
        weight = 1.5,
        runSpeedModifier = 0.92,
    },
    ["Base.Assault_Backpack"] = {
        capacityOption = "AssaultCapacity",
        weightReductionOption = "AssaultWeightReduction",
        weightOption = "AssaultWeight",
        runSpeedOption = "AssaultRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.0,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Mattress"] = {
        capacityOption = "SleepingBagCapacity",
        weightReductionOption = "SleepingBagWeightReduction",
        weightOption = "SleepingBagWeight",
        runSpeedOption = "SleepingBagRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.1,
        runSpeedModifier = 0.88,
    },
    ["Base.Hunting_Backpack_Green"] = {
        capacityOption = "HuntingCapacity",
        weightReductionOption = "HuntingWeightReduction",
        weightOption = "HuntingWeight",
        runSpeedOption = "HuntingRunSpeedModifier",
        capacity = 30,
        weightReduction = 80,
        weight = 1.5,
        runSpeedModifier = 0.92,
    },
    ["Base.Hunting_Backpack_Green_Patch"] = {
        capacityOption = "HuntingCapacity",
        weightReductionOption = "HuntingWeightReduction",
        weightOption = "HuntingWeight",
        runSpeedOption = "HuntingRunSpeedModifier",
        capacity = 30,
        weightReduction = 80,
        weight = 1.5,
        runSpeedModifier = 0.92,
    },
    ["Base.Hunting_Backpack_Brown"] = {
        capacityOption = "HuntingCapacity",
        weightReductionOption = "HuntingWeightReduction",
        weightOption = "HuntingWeight",
        runSpeedOption = "HuntingRunSpeedModifier",
        capacity = 30,
        weightReduction = 80,
        weight = 1.5,
        runSpeedModifier = 0.92,
    },
    ["Base.Hunting_Backpack_Brown_Patch"] = {
        capacityOption = "HuntingCapacity",
        weightReductionOption = "HuntingWeightReduction",
        weightOption = "HuntingWeight",
        runSpeedOption = "HuntingRunSpeedModifier",
        capacity = 30,
        weightReduction = 80,
        weight = 1.5,
        runSpeedModifier = 0.92,
    },
    ["Base.Assault_Backpack_Black"] = {
        capacityOption = "AssaultCapacity",
        weightReductionOption = "AssaultWeightReduction",
        weightOption = "AssaultWeight",
        runSpeedOption = "AssaultRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.0,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Green"] = {
        capacityOption = "AssaultCapacity",
        weightReductionOption = "AssaultWeightReduction",
        weightOption = "AssaultWeight",
        runSpeedOption = "AssaultRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.0,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Camo"] = {
        capacityOption = "AssaultCapacity",
        weightReductionOption = "AssaultWeightReduction",
        weightOption = "AssaultWeight",
        runSpeedOption = "AssaultRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.0,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Pidoras"] = {
        capacityOption = "AssaultCapacity",
        weightReductionOption = "AssaultWeightReduction",
        weightOption = "AssaultWeight",
        runSpeedOption = "AssaultRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.0,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Mattress_Black"] = {
        capacityOption = "SleepingBagCapacity",
        weightReductionOption = "SleepingBagWeightReduction",
        weightOption = "SleepingBagWeight",
        runSpeedOption = "SleepingBagRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.1,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Mattress_Green"] = {
        capacityOption = "SleepingBagCapacity",
        weightReductionOption = "SleepingBagWeightReduction",
        weightOption = "SleepingBagWeight",
        runSpeedOption = "SleepingBagRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.1,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Mattress_Camo"] = {
        capacityOption = "SleepingBagCapacity",
        weightReductionOption = "SleepingBagWeightReduction",
        weightOption = "SleepingBagWeight",
        runSpeedOption = "SleepingBagRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.1,
        runSpeedModifier = 0.88,
    },
    ["Base.Assault_Backpack_Mattress_Pidoras"] = {
        capacityOption = "SleepingBagCapacity",
        weightReductionOption = "SleepingBagWeightReduction",
        weightOption = "SleepingBagWeight",
        runSpeedOption = "SleepingBagRunSpeedModifier",
        capacity = 45,
        weightReduction = 85,
        weight = 2.1,
        runSpeedModifier = 0.88,
    },
}

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if value == nil or value ~= value then
        value = fallback
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function RB_Sandbox.getConfiguredValues()
    local options = SandboxVars and SandboxVars.RB or nil
    local values = {}

    for fullType, defaults in pairs(VARIANTS) do
        local configured = {
            capacity = defaults.capacity,
            weightReduction = defaults.weightReduction,
            weight = defaults.weight,
            runSpeedModifier = defaults.runSpeedModifier,
        }

        if options then
            configured.capacity = clamp(options[defaults.capacityOption], 1, 10000, defaults.capacity)
            configured.weightReduction = clamp(options[defaults.weightReductionOption], 0, 99, defaults.weightReduction)
            configured.weight = clamp(options[defaults.weightOption], 0.1, 10, defaults.weight)
            configured.runSpeedModifier = clamp(options[defaults.runSpeedOption], 0.50, 1.00, defaults.runSpeedModifier)
        end

        configured.capacity = math.floor(configured.capacity + 0.5)
        configured.weightReduction = math.floor(configured.weightReduction + 0.5)
        values[fullType] = configured
    end

    return values
end

function RB_Sandbox.getCommandValues(args)
    args = args or {}
    local values = {}

    for fullType, defaults in pairs(VARIANTS) do
        local configured = {
            capacity = clamp(args[defaults.capacityOption], 1, 10000, defaults.capacity),
            weightReduction = clamp(args[defaults.weightReductionOption], 0, 99, defaults.weightReduction),
            weight = clamp(args[defaults.weightOption], 0.1, 10, defaults.weight),
            runSpeedModifier = clamp(args[defaults.runSpeedOption], 0.50, 1.00, defaults.runSpeedModifier),
        }

        configured.capacity = math.floor(configured.capacity + 0.5)
        configured.weightReduction = math.floor(configured.weightReduction + 0.5)
        values[fullType] = configured
    end

    return values
end

function RB_Sandbox.getCommandArguments(values)
    values = values or RB_Sandbox.getConfiguredValues()
    local args = {}

    for fullType, defaults in pairs(VARIANTS) do
        local configured = values[fullType]
        if configured then
            args[defaults.capacityOption] = configured.capacity
            args[defaults.weightReductionOption] = configured.weightReduction
            args[defaults.weightOption] = configured.weight
            args[defaults.runSpeedOption] = configured.runSpeedModifier
        end
    end

    return args
end

function RB_Sandbox.applyToScriptItems(values)
    if RB_CustomizableContainers.isActive() then
        RB_CustomizableContainers.applyTemplates()
        return
    end
    values = values or RB_Sandbox.getConfiguredValues()

    for fullType, configured in pairs(values) do
        local scriptItem = ScriptManager.instance:getItem(fullType)
        if scriptItem then
            scriptItem:DoParam("Capacity = " .. tostring(configured.capacity))
            scriptItem:DoParam("Weight = " .. tostring(configured.weight))
            scriptItem:DoParam("WeightReduction = " .. tostring(configured.weightReduction))
            scriptItem:DoParam("RunSpeedModifier = " .. tostring(configured.runSpeedModifier))
        else
            print("[RealisticBackpacksB42] Item definition not found: " .. fullType)
        end
    end
end

local function applyToBackpack(item, values)
    if not item then
        return 0
    end

    local configured = values[item:getFullType()]
    if not configured then
        return 0
    end

    if RB_CustomizableContainers.isActive() then
        RB_CustomizableContainers.applyItem(item)
        return 1
    end

    item:setActualWeight(configured.weight)
    item:setWeight(configured.weight)
    item:setCustomWeight(true)
    item:setCapacity(configured.capacity)
    item:setWeightReduction(configured.weightReduction)

    local innerContainer = item:getInventory()
    if innerContainer then
        innerContainer:setCapacity(configured.capacity)
        innerContainer:setWeightReduction(configured.weightReduction)
    end

    return 1
end

local function scanContainer(container, values, visited)
    if not container or visited[container] then
        return 0
    end
    visited[container] = true

    local items = container:getItems()
    if not items then
        return 0
    end

    local updated = 0
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        updated = updated + applyToBackpack(item, values)

        if item and item:IsInventoryContainer() then
            updated = updated + scanContainer(item:getInventory(), values, visited)
        end
    end

    return updated
end

function RB_Sandbox.updatePlayer(player, values)
    if not player then
        return 0
    end

    return scanContainer(player:getInventory(), values or RB_Sandbox.getConfiguredValues(), {})
end

local function initialiseBackpackConfiguration()
    -- A multiplayer client must wait for the authoritative server response.
    -- Singleplayer and server instances may use their own SandboxVars directly.
    if isClient() then
        return
    end

    local values = RB_Sandbox.getConfiguredValues()
    RB_Sandbox.applyToScriptItems(values)

    if RB_CustomizableContainers.isActive() then
        print("[RealisticBackpacksB42] Backpack stats managed by Customizable Containers.")
    else
        print("[RealisticBackpacksB42] Applied sandbox values to all backpack colour templates.")
    end
end

RB_CustomizableContainers.register(VARIANTS)
Events.OnInitGlobalModData.Add(initialiseBackpackConfiguration)
Events.OnGameStart.Add(initialiseBackpackConfiguration)
