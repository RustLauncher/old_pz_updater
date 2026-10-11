require "UsefulPallets/Config"
require "TimedActions/ISTakeBricks"
require "Moveables/ISMoveableSpriteProps"

local WP = UsefulPallets
local function loaded(object)
    local state = WP.state(object)
    return state and state.count > 0
end

-- A vanilla entity can retain its bulk-take entry after changing sprites.
-- Also guard completion so an older/stale vanilla action cannot bypass the count.
local vanillaTake = ISTakeBricks.complete
function ISTakeBricks:complete()
    if WP.state(self.pallet) then return false end
    return vanillaTake(self)
end

local vanillaCanPickUp = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(character, square, object, isMulti)
    if loaded(object) then return false end
    return vanillaCanPickUp(self, character, square, object, isMulti)
end

local vanillaPickUp = ISMoveableSpriteProps.pickUpMoveableInternal
function ISMoveableSpriteProps:pickUpMoveableInternal(character, square, object, sprInstance, spriteName, createItem, rotating)
    if loaded(object) then return nil end
    return vanillaPickUp(self, character, square, object, sprInstance, spriteName, createItem, rotating)
end
