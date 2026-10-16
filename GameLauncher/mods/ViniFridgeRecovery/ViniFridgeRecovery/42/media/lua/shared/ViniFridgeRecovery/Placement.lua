-- Reconstructing an MP action on the server uses the server's actual stored
-- item's worldSprite and furniture names. Normalize exact alias items before
-- vanilla builds moveProps. Native placement/removal/ownership stays unchanged.
require 'ViniFridgeRecovery/Recovery'
require 'Moveables/ISMoveablesAction'
local R=ViniFridgeRecovery
function R.installPlacementAdapter()
    local previous=ISMoveablesAction and ISMoveablesAction.new
    if not previous or previous==R.placementConstructor then return end
    R.placementConstructor=function(self,character,square,mode,origSpriteName,object,direction,item,moveCursor,...)
        if mode=='place' and item and instanceof(item,'Moveable') then
            local entry=R.aliases[item:getWorldSprite()]
            local from=R.aliases[origSpriteName]
            if entry or from then
                -- Include split parts before the native constructor and item-name
                -- lookup. This is the same server-owned inventory, not new items.
                if character then R.scanItems(character:getInventory()) end
                R.normalizeItem(item)
                if from then origSpriteName=from.native end
            end
        end
        return previous(self,character,square,mode,origSpriteName,object,direction,item,moveCursor,...)
    end
    ISMoveablesAction.new=R.placementConstructor
end
R.installPlacementAdapter()
Events.OnGameStart.Add(R.installPlacementAdapter)
