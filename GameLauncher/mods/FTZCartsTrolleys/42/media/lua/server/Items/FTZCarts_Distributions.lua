-- FTZ Carts & Trolleys - container loot (same places and base rates as the original mod),
-- scaled by the sandbox option FTZCarts.LootRate (100 = original).
require "Items/ProceduralDistributions"

local CART = "Base.FTZ_ShoppingCart"
local TROLLEY = "Base.FTZ_PlatformTrolley"

local ENTRIES = {
    { "GigamartTools", CART, 1 },
    { "GigamartHousewares", TROLLEY, 1 },
    { "CrateTools", CART, 1 },
    { "CrateTools", TROLLEY, 1.5 },
    { "CrateMetalwork", CART, 0.2 },
    { "CrateMetalwork", TROLLEY, 0.2 },
    { "StoreCounterBagsFancy", CART, 1 },
    { "JanitorTools", TROLLEY, 0.5 },
    { "ToolStoreFarming", TROLLEY, 1 },
    { "ToolStoreFarming", CART, 1 },
    { "ToolStoreMisc", TROLLEY, 1 },
    { "ToolStoreMisc", CART, 1 },
    { "ToolStoreTools", TROLLEY, 1 },
    { "ToolStoreTools", CART, 1 },
}

local function addLoot()
    local rate = 100
    if SandboxVars and SandboxVars.FTZCarts and SandboxVars.FTZCarts.LootRate then
        rate = tonumber(SandboxVars.FTZCarts.LootRate) or 100
    end
    if rate <= 0 then return end
    for _, e in ipairs(ENTRIES) do
        local list = ProceduralDistributions and ProceduralDistributions.list and ProceduralDistributions.list[e[1]]
        if list and list.items then
            table.insert(list.items, e[2])
            table.insert(list.items, e[3] * rate / 100)
        end
    end
end

-- runs once the sandbox settings of the save are known
Events.OnPreDistributionMerge.Add(addLoot)
