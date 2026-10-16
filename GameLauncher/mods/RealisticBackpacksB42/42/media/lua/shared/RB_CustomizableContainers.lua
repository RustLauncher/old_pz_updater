-- Optional integration with Customizable Containers (Workshop 2719850086).
-- CC owns the values while active; this mod neither installs nor probes its
-- external capacity-limit bypass.
RB_CustomizableContainers = RB_CustomizableContainers or {}
local Compat = RB_CustomizableContainers
local MOD_ID = "RealisticBackpacksB42"
local CC_ID = "CustomizableBackpacks"
local backpacks
local SETTINGS = {
    "CustomizableBackpacks", "CustomizableBags", "CustomizableChestRigs",
    "CustomizableFannyPacks", "CustomizableSatchels", "CustomizableContainers",
}

function Compat.isActive()
    return getActivatedMods():contains(CC_ID)
end

function Compat.register(variants)
    if not Compat.isActive() or backpacks then
        return
    end

    -- Explicit requires make registration independent of mod load order.
    require "01_CustomizableDictionaries"
    require "CustomizableFunctions"
    require "CustomizableSandbox"
    require "CustomizableContainers"

    backpacks = {}
    local ids = {}
    for fullType in pairs(variants) do
        table.insert(ids, fullType)
    end
    table.sort(ids)
    for _, fullType in ipairs(ids) do
        local defaults = variants[fullType]
        -- No invented balance presets: all three CC base presets use our
        -- unchanged original stats. CC multipliers/overrides operate on these.
        local entry = {
            ItemName = fullType,
            Capacity = defaults.capacity,
            CapacityWB = defaults.capacity,
            CapacityB = defaults.capacity,
            WeightReduction = defaults.weightReduction,
            WeightReductionWB = defaults.weightReduction,
            WeightReductionB = defaults.weightReduction,
            Weight = defaults.weight,
        }
        table.insert(backpacks, entry)
        CCRegisterContainerDefinition(entry)
    end
    -- CC's stat handlers and manual override UI share this source table.
    for _, source in ipairs(_CCSupportedContainerSources) do
        if source.modID == MOD_ID then
            source.backpack = backpacks
            return
        end
    end
    table.insert(_CCSupportedContainerSources, { modID = MOD_ID, backpack = backpacks })
    print("[RealisticBackpacksB42] Registered 16 backpack variants with Customizable Containers.")
end

function Compat.applyTemplates()
    if not backpacks then
        return
    end
    CCalterWeight(MOD_ID, backpacks)
    CCalterCapacity(MOD_ID, backpacks)
    CCalterWeightReduction(MOD_ID, backpacks)
    CCalterRunSpeedModifier(MOD_ID, backpacks)
end

function Compat.applyItem(item)
    CCApplyContainerItemInstanceStats(item)
    local inner = item:getInventory()
    if inner then
        inner:setWeightReduction(item:getWeightReduction())
    end
end

local function copySettings(source)
    if type(source) ~= "table" then
        return nil
    end
    local result = {}
    for _, name in ipairs(SETTINGS) do
        if type(source[name]) ~= "table" then
            return nil
        end
        local group = {}
        for key, value in pairs(source[name]) do
            local kind = type(value)
            if type(key) ~= "string" or
                (kind ~= "boolean" and kind ~= "string" and kind ~= "number") then
                return nil
            end
            if kind == "number" and
                (value ~= value or value == math.huge or value == -math.huge) then
                return nil
            end
            group[key] = value
        end
        result[name] = group
    end
    return result
end

function Compat.getServerSettings()
    return copySettings(SandboxVars)
end

function Compat.receiveServerSettings(settings)
    local checked = copySettings(settings)
    if not checked then
        return false
    end
    -- Only the server response reaches this function. Client requests carry
    -- no settings. CC must evaluate the same authoritative SandboxVars.
    for _, name in ipairs(SETTINGS) do
        SandboxVars[name] = checked[name]
    end
    return true
end
