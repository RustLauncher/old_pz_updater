-- ============================================================================
-- Eris Food Expiry (batman fork) — freshness strip in the expanded item list
--
-- A row holds one line of text (itemHgt): the vanilla detail line is kept and
-- a thin strip is drawn along the bottom of the row.
-- ============================================================================

require "ISUI/ISInventoryPane"
require "ErisFoodExpiry/EFE_Core"

local EFE = ErisFoodExpiry

local STRIP_HEIGHT = 2

local original = ISInventoryPane.drawItemDetails
if not original then
    print("[ErisFoodExpiry] ISInventoryPane.drawItemDetails missing: no freshness strip")
    return
end

function ISInventoryPane:drawItemDetails(item, y, xoff, yoff, red)
    original(self, item, y, xoff, yoff, red)
    if not instanceof(item, "Food") or not EFE.canAge(item) then return end
    local fraction = EFE.freshFraction(item)
    local left = 40 + 30 + xoff
    -- vanilla label column (min 120) + progress bar, as in drawTextAndProgressBar
    local width = 120 - 30 + self:getProgressBarWidth()
    local top = self.headerHgt + y * self.itemHgt + yoff + self.itemHgt - STRIP_HEIGHT - 1
    local done = math.floor(width * fraction)
    local c = EFE.COLORS[EFE.stage(item)]
    self:drawRect(left, top, done, STRIP_HEIGHT, 0.9, c[1], c[2], c[3])
    self:drawRect(left + done, top, width - done, STRIP_HEIGHT, 0.8, 0.25, 0.25, 0.25)
end
