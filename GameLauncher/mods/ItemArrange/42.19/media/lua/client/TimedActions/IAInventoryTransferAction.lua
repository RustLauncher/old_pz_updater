

require "TimedActions/ISInventoryTransferAction"

local start = ISInventoryTransferAction.start
function ISInventoryTransferAction:start()
    start(self)
    local witem = self.item:getWorldItem()
    if witem then
        self.rearrangeSquare = witem:getSquare()
    end
end

local perform = ISInventoryTransferAction.perform
function ISInventoryTransferAction:perform()
    perform(self)
    if self.rearrangeSquare then
        IA.ArrangeItems(self.rearrangeSquare)
    end
end

