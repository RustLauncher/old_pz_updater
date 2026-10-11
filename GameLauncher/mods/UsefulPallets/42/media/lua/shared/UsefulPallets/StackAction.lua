require "UsefulPallets/TransferAction"

ISUsefulPalletStack = ISUsefulPalletTransfer:derive("ISUsefulPalletStack")
local WP = UsefulPallets

function ISUsefulPalletStack:isValid()
    if not WP.canReach(self.character, self.pallet) then return false end
    local state = WP.state(self.pallet)
    local inventory = self.character:getInventory()
    if not state or self.revision ~= (state.stackRevision or 0) then return false end
    if self.direction == "attach" then
        return WP.canAttach(state) and WP.isMilitaryPalletItem(self.item)
            and self.item:getContainer() == inventory and inventory:contains(self.item)
            and not self.item:isFavorite() and not self.character:isEquipped(self.item)
    elseif self.direction == "detach" then
        return WP.canDetach(state) and inventory:hasRoomFor(self.character, state.topPallet.weight)
    end
    return false
end

function ISUsefulPalletStack:complete()
    -- B42 server completion must recheck ownership, geometry and current state.
    if not self:isValid() then return false end
    local old = WP.state(self.pallet)
    local state = copyTable(old)
    local inventory = self.character:getInventory()
    state.stackRevision = (old.stackRevision or 0) + 1
    if self.direction == "attach" then
        state.kind = "stacked"
        state.bottomCount = old.count
        state.topPallet = WP.captureItem(self.item)
        state.topPallet.itemType = "Moveables." .. self.item:getWorldSprite()
        state.topPallet.sprite = self.item:getWorldSprite()
        state.topPallet.weight = self.item:getActualWeight()
    else
        state.kind = "military"
        state.topPallet = nil
        state.bottomCount = nil
        state.vanillaIntact = nil
    end
    local sprite = WP.spriteFor(state.kind, state.item, state.count, state.bottomCount)
    if not sprite or not IsoSpriteManager.instance:getSprite(sprite) then return false end
    if self.direction == "attach" then
        sendRemoveItemFromContainer(inventory, self.item)
        inventory:Remove(self.item)
    else
        local record = old.topPallet
        -- The item factory gives dynamic furniture a Base.<sprite> full type,
        -- which is not a script item ID. Rebuild from the validated sprite alias;
        -- this also recovers tops saved with that non-instantiable legacy type.
        local returned = instanceItem("Moveables." .. record.sprite)
        if not returned or not instanceof(returned, "Moveable") or not returned:ReadFromWorldSprite(record.sprite) then return false end
        returned:setActualWeight(record.weight)
        WP.restoreItem(returned, record)
        if not inventory:AddItem(returned) then return false end
        sendAddItemToContainer(inventory, returned)
    end
    self.pallet:getModData().UsefulPallets = state
    self.pallet:setSpriteFromName(sprite)
    self.pallet:transmitModData()
    self.pallet:transmitUpdatedSpriteToClients()
    self.pallet:getSquare():RecalcProperties()
    self.pallet:getSquare():RecalcAllWithNeighbours(true)
    return true
end

-- Parameter names are the B42 network field names; keep them synchronized.
function ISUsefulPalletStack:new(character, pallet, direction, item, revision)
    return ISUsefulPalletTransfer.new(self, character, pallet, nil, direction, item, nil, revision)
end
