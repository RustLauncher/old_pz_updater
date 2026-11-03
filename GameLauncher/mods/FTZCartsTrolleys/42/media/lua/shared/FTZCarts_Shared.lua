-- FTZ Carts & Trolleys (Build 42) - shared data
FTZCarts = FTZCarts or {}

-- item full type -> models, icons and the sandbox option giving its capacity
FTZCarts.TYPES = {
    ["Base.FTZ_PlatformTrolley"] = { model = "FTZ_PlatformTrolleyModel", modelFull = "FTZ_PlatformTrolleyModelFull",
                                     icon = "Item_FTZ_PlatformTrolley", iconFull = "Item_FTZ_PlatformTrolleyFull",
                                     capacityOption = "TrolleyCapacity", capacityDefault = 50 },
    ["Base.FTZ_ShoppingCart"]      = { model = "FTZ_ShoppingCartModel", modelFull = "FTZ_ShoppingCartModelFull",
                                     icon = "Item_FTZ_ShoppingCart", iconFull = "Item_FTZ_ShoppingCartFull",
                                     capacityOption = "CartCapacity", capacityDefault = 37 },
}

function FTZCarts.isCart(item)
    return item ~= nil and FTZCarts.TYPES[item:getFullType()] ~= nil
end

function FTZCarts.capacityFor(fullType)
    local def = FTZCarts.TYPES[fullType]
    if not def then return nil end
    local sv = SandboxVars and SandboxVars.FTZCarts
    local v = sv and tonumber(sv[def.capacityOption]) or def.capacityDefault
    return math.max(1, math.min(100, math.floor(v)))
end

-- keeps an existing cart in line with the sandbox capacity
function FTZCarts.applyCapacity(item)
    if not FTZCarts.isCart(item) or not item.getItemContainer then return end
    local cont = item:getItemContainer()
    local cap = FTZCarts.capacityFor(item:getFullType())
    if cont and cap and cont:getCapacity() ~= cap then
        cont:setCapacity(cap)
        if item.setCapacity then pcall(function() item:setCapacity(cap) end) end
    end
end

-- new carts get the sandbox capacity straight from their script
local function applyScriptCapacities()
    local sm = getScriptManager()
    for fullType, _ in pairs(FTZCarts.TYPES) do
        local script = sm and sm:getItem(fullType)
        if script then pcall(function() script:DoParam("Capacity = " .. tostring(FTZCarts.capacityFor(fullType))) end) end
    end
end
Events.OnInitGlobalModData.Add(applyScriptCapacities)
Events.OnGameStart.Add(applyScriptCapacities)

-- is the cart loaded? (needs to know its contents: the owner, or the server)
function FTZCarts.isFull(item)
    if not item.getItemContainer then return false end
    local cont = item:getItemContainer()
    return cont ~= nil and not cont:isEmpty()
end
