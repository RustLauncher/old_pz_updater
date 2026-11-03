-- FTZ Carts & Trolleys - what may go inside a cart: anything but another cart or a heavy item.
require "Items/AcceptItemFunction"

function AcceptItemFunction.FTZCart(container, item)
    if not item then return false end
    if FTZCarts and FTZCarts.isCart(item) then return false end
    if item:isForceDropHeavyItem() then return false end
    return true
end
