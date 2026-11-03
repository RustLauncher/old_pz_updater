require "TimedActions/ISInventoryTransferUtil"

function ISInventoryTransferUtil.getDropSquare(character)
        local cx = math.floor(character:getX())
        local cy = math.floor(character:getY())
        local cz = math.floor(character:getZ())
        local mx = getMouseX()
        local my = getMouseY()
        local tx = math.floor(screenToIsoX(0, mx, my, cz))
        local ty = math.floor(screenToIsoY(0, mx, my, cz))

        if tx > cx + 1 then tx = cx + 1 end
        if tx < cx - 1 then tx = cx - 1 end
        if ty > cy + 1 then ty = cy + 1 end
        if ty < cy - 1 then ty = cy - 1 end

        local square = character:getSquare():getCell():getGridSquare(tx, ty, cz)
        return square
end

ISInventoryTransferUtil = ISInventoryTransferUtil or {}

local old = ISInventoryTransferUtil.newInventoryTransferAction
function ISInventoryTransferUtil.newInventoryTransferAction(character, item, srcContainer, destContainer, time)
    local isDropAndArrange = destContainer and destContainer:getType() == "floor" and isShiftKeyDown()
    if isDropAndArrange then
        local dropSquare = ISInventoryTransferUtil.getDropSquare(character)
        return IAArrangeAction:new(character, item, srcContainer, dropSquare)
    end

    return old(character, item, srcContainer, destContainer, time)
end

--[[ 
overwrite version, better for testing

function ISInventoryTransferUtil.newInventoryTransferAction(character, item, srcContainer, destContainer, time)
    local isGrabbingCorpseItem = ISInventoryTransferUtil.isCharacterGrabbingCorpseItem(character, item, srcContainer, destContainer)
    if isGrabbingCorpseItem then
        return ISGrabCorpseItem:new(character, item)
    end

    local isDropAndArrange = destContainer and destContainer:getType() == "floor" and isShiftKeyDown()
    if isDropAndArrange then
        local dropSquare = ISInventoryTransferUtil.getDropSquare(character)
        return IAArrangeAction:new(character, item, srcContainer, dropSquare, time)
    end

    return ISInventoryTransferAction:new(character, item, srcContainer, destContainer, time)
end
]]