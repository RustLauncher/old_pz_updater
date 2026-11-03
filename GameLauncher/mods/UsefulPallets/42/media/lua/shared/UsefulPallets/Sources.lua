require "UsefulPallets/Config"
local WP = UsefulPallets

-- Mirror the vanilla loot window's adjacent-square, wall, lock and vehicle checks.
function WP.canUseSource(character, container)
    if not container or not container:isExistYet() then return false end
    if container:isInCharacterInventory(character) then return true end
    local root = container:getOutermostContainer()
    if not root or root:getType() == "floor" then return false end
    local part = root:getVehiclePart()
    if part then
        -- Vehicle containers may not have an up-to-date sourceGrid. Vanilla uses
        -- the part's vehicle access test (door, lock and interaction distance).
        local vehicle = part:getVehicle()
        return vehicle and vehicle:getSquare()
            and SafeHouse.isSafehouseAllowLoot(vehicle:getSquare(), character)
            and vehicle:canAccessContainer(part:getIndex(), character) or false
    end
    local square = root:getSourceGrid()
    local playerSquare = character:getSquare()
    if not square or not playerSquare or square:getZ() ~= playerSquare:getZ()
        or math.abs(square:getX() - playerSquare:getX()) > 1
        or math.abs(square:getY() - playerSquare:getY()) > 1
        or not playerSquare:canReachTo(square)
        or not SafeHouse.isSafehouseAllowLoot(square, character) then return false end
    local parent = root:getParent()
    if instanceof(parent, "IsoThumpable") and parent:isLockedToCharacter(character) then return false end
    return parent and parent:isExistInTheWorld() or false
end

function WP.canLoadItem(character, item, itemType)
    if not item or item:getFullType() ~= itemType or item:isFavorite()
        or character:isEquipped(item) or item:getIsCraftingConsumed() then return false end
    local container = item:getContainer()
    return WP.canUseSource(character, container) and container:contains(item)
        and container:isRemoveItemAllowed(item) or false
end
