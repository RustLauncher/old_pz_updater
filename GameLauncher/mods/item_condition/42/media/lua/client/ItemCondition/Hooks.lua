ItemCondition = ItemCondition or {}
ItemCondition.Hooks = ItemCondition.Hooks or {}

local Hooks = ItemCondition.Hooks

local function drawHotbarCondition(self)
    local Config = ItemCondition.Config
    local UI = ItemCondition.UI

    if not Config or not UI or not self then return end

    local config = Config.Hotbar
    if not config or not config.ProgressBarMode or config.ProgressBarMode <= 1 then
        return
    end

    local slots = self.availableSlot
    local items = self.attachedItems
    if type(slots) ~= "table" or type(items) ~= "table" then
        return
    end

    local slotWidth = tonumber(self.slotWidth)
    local slotHeight = tonumber(self.slotHeight)
    local slotPad = tonumber(self.slotPad) or 0
    local margin = tonumber(self.margins) or 0

    if not slotWidth or not slotHeight then
        return
    end

    local slotX = margin + 1
    local slotY = margin + 1
    local count = #slots

    for i = 1, count do
        local item = items[i]
        if item then
            UI:DrawItemProgress(
                self,
                item,
                config.ProgressBarMode,
                config.ProgressBarOpacity,
                slotX,
                slotY,
                slotWidth,
                slotHeight,
                1.0
            )
        end
        slotX = slotX + slotWidth + slotPad
    end
end

local function resolveAnchor(anchor, fallbackX, fallbackY)
    if type(anchor) == "number" then
        return anchor, fallbackY
    end

    if type(anchor) == "table" then
        local x = anchor.x or anchor[1] or fallbackX
        local y = anchor.y or anchor[2] or fallbackY
        if type(x) == "number" and type(y) == "number" then
            return x, y
        end
    end

    return fallbackX, fallbackY
end

local function drawEquippedCondition(self)
    local Config = ItemCondition.Config
    local UI = ItemCondition.UI

    if not Config or not UI or not self then return end

    local config = Config.Equipped
    if not config or not config.ProgressBarMode or config.ProgressBarMode <= 1 then
        return
    end

    local character = self.chr
    if not character then return end

    local primaryItem = character:getPrimaryHandItem()
    if primaryItem then
        local hand = self.mainHand
        if hand and type(hand.getX) == "function" and type(hand.getY) == "function"
            and type(hand.getWidth) == "function" and type(hand.getHeight) == "function" then
            local handX = hand:getX()
            local handY = hand:getY()
            local handW = hand:getWidth()
            local handH = hand:getHeight()

            local size = math.floor(math.min(handW, handH) + 0.5)
            local x = math.floor(handX + (handW - size) * 0.5 + 0.5)
            local y = math.floor(handY + (handH - size) * 0.5 + 0.5)

            UI:DrawEquippedItemProgress(
                self,
                primaryItem,
                config.ProgressBarMode,
                config.ProgressBarOpacity,
                x,
                y,
                size,
                size
            )
        end
    end

    local secondaryItem = character:getSecondaryHandItem()
    if secondaryItem then
        local hand = self.offHand
        if hand and type(hand.getX) == "function" and type(hand.getY) == "function"
            and type(hand.getWidth) == "function" and type(hand.getHeight) == "function" then
            local handX = hand:getX()
            local handY = hand:getY()
            local handW = hand:getWidth()
            local handH = hand:getHeight()
            local size = math.floor(math.min(handW, handH) + 0.5)
            local x = math.floor(handX + (handW - size) * 0.5 + 0.5)
            local y = math.floor(handY + (handH - size) * 0.5 + 0.5)

            UI:DrawEquippedItemProgress(
                self,
                secondaryItem,
                config.ProgressBarMode,
                config.ProgressBarOpacity,
                x,
                y,
                size,
                size
            )
        end
    end
end

local function installHotbarHook()
    if not ISHotbar or type(ISHotbar.render) ~= "function" then
        return false
    end
    if Hooks.HotbarInstalled then
        return true
    end

    Hooks.OriginalHotbarRender = ISHotbar.render
    ISHotbar.render = function(self, ...)
        drawHotbarCondition(self)
        Hooks.OriginalHotbarRender(self, ...)
    end

    Hooks.HotbarInstalled = true
    return true
end

local function installEquippedHook()
    if not ISEquippedItem or type(ISEquippedItem.render) ~= "function" then
        return false
    end
    if Hooks.EquippedInstalled then
        return true
    end

    Hooks.OriginalEquippedRender = ISEquippedItem.render
    ISEquippedItem.render = function(self, ...)
        drawEquippedCondition(self)
        Hooks.OriginalEquippedRender(self, ...)
    end

    Hooks.EquippedInstalled = true
    return true
end

local function install()
    installHotbarHook()
    installEquippedHook()
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(install)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(install)
end
