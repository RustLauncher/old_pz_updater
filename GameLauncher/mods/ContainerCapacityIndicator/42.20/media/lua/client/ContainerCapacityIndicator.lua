require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "PZAPI/ModOptions"

local CapacityIndicator = {}
local options = PZAPI.ModOptions:create("ContainerCapacityIndicator", "Container Capacity Indicator")
local showMagazineIndicators = options:addTickBox("showMagazineIndicators",
    "Show magazine indicators", true,
    "Show load indicators on loose detachable magazines. Turn off to show only container capacity bars.")

print("[ContainerCapacityIndicator] client UI hook loaded")

local BAR_MARGIN = 2
local BAR_HEIGHT = 4
local ITEM_BAR_HEIGHT = 4
local MAGAZINE_SEGMENTS = 4

local function getFillColor(ratio)
    if ratio >= 0.95 then
        return 0.90, 0.22, 0.18
    end
    if ratio >= 0.75 then
        return 0.95, 0.68, 0.16
    end
    return 0.24, 0.78, 0.32
end

local function getCapacityRatio(inventory, player)
    if not inventory or not player then
        return nil
    end
    local capacity = inventory:getEffectiveCapacity(player)
    if not capacity or capacity <= 0 then
        return nil
    end

    local used = inventory:getCapacityWeight()
    return math.max(0, math.min(used / capacity, 1))
end

local function drawCapacityBar(target, x, y, width, height, ratio)
    if not ratio or width < 3 or height < 3 then
        return
    end

    target:drawRect(x, y, width, height, 0.88, 0.08, 0.08, 0.08)

    if ratio > 0 then
        local r, g, b = getFillColor(ratio)
        local innerWidth = width - 2
        local fillWidth = math.max(1, math.floor(innerWidth * ratio))
        target:drawRect(x + 1, y + 1, fillWidth, height - 2, 0.95, r, g, b)
    end

    target:drawRectBorder(x, y, width, height, 0.70, 0.65, 0.65, 0.65)
end

local function safeItemCall(item, method)
    if not item then
        return nil
    end

    local fn = item[method]
    if not fn then
        return nil
    end

    local ok, value = pcall(fn, item)
    if ok then
        return value
    end
    return nil
end

local function getMagazineRatio(item)
    if not showMagazineIndicators:getValue() then
        return nil
    end
    if not item or safeItemCall(item, "IsWeapon") then
        return nil
    end

    local maxAmmo = tonumber(safeItemCall(item, "getMaxAmmo")) or 0
    local ammoType = safeItemCall(item, "getAmmoType")
    if maxAmmo <= 0 or not ammoType then
        return nil
    end

    local currentAmmo = tonumber(safeItemCall(item, "getCurrentAmmoCount")) or 0
    return math.max(0, math.min(currentAmmo / maxAmmo, 1))
end

local function getMagazineState(ratio)
    if ratio <= 0 then
        return 0
    end
    if ratio >= 1 then
        return MAGAZINE_SEGMENTS
    end
    return math.min(math.ceil(ratio * MAGAZINE_SEGMENTS), MAGAZINE_SEGMENTS - 1)
end

local function getMagazineColor(state)
    if state == 0 then
        return 0.92, 0.16, 0.12
    end
    if state == 1 then
        return 0.95, 0.36, 0.12
    end
    if state == 2 then
        return 0.95, 0.72, 0.14
    end
    if state == 3 then
        return 0.30, 0.68, 0.94
    end
    return 0.24, 0.82, 0.34
end

local function drawMagazineBar(target, x, y, width, height, ratio)
    if ratio == nil or width < (MAGAZINE_SEGMENTS * 2) or height < 3 then
        return
    end

    local state = getMagazineState(ratio)
    local r, g, b = getMagazineColor(state)
    local innerWidth = width - 2
    local gap = 1
    local segmentWidth = (innerWidth - gap * (MAGAZINE_SEGMENTS - 1)) / MAGAZINE_SEGMENTS

    target:drawRect(x, y, width, height, 0.92, 0.06, 0.06, 0.06)
    for segment = 1, MAGAZINE_SEGMENTS do
        local segmentX = x + 1 + math.floor((segment - 1) * (segmentWidth + gap))
        local nextX = x + 1 + math.floor(segment * segmentWidth + (segment - 1) * gap)
        local drawWidth = math.max(1, nextX - segmentX)
        if segment <= state then
            target:drawRect(segmentX, y + 1, drawWidth, height - 2, 0.98, r, g, b)
        else
            target:drawRect(segmentX, y + 1, drawWidth, height - 2, 0.82, 0.18, 0.18, 0.18)
        end
    end
    target:drawRectBorder(x, y, width, height, 0.82, r, g, b)
end

local function renderCapacityIndicator(button)
    local player = getSpecificPlayer(button.cciPlayer or 0)
    local ratio = getCapacityRatio(button.inventory, player)
    if not ratio then
        return
    end

    local x = BAR_MARGIN
    local y = button:getHeight() - BAR_HEIGHT - BAR_MARGIN
    local width = math.max(0, button:getWidth() - (BAR_MARGIN * 2))

    drawCapacityBar(button, x, y, width, BAR_HEIGHT, ratio)
end

local function getItemContainerRatio(item, player)
    if not item or not item.IsInventoryContainer or not item:IsInventoryContainer() then
        return nil
    end
    return getCapacityRatio(item:getInventory(), player)
end

local function renderDetailsItemIndicator(pane, item, row, isStackItem, player)
    local capacityRatio = getItemContainerRatio(item, player)
    local magazineRatio = getMagazineRatio(item)
    if capacityRatio == nil and magazineRatio == nil then
        return
    end

    local iconSize = math.min(pane.itemHgt - 2, 32)
    local iconX
    if isStackItem then
        iconX = 26
    else
        iconX = pane.column2 - iconSize - (pane.itemHgt - iconSize) / 2
    end
    local iconY = pane.headerHgt + row * pane.itemHgt + (pane.itemHgt - iconSize) / 2
    local barY = iconY + iconSize - ITEM_BAR_HEIGHT
    local visibleBarY = barY + pane:getYScroll()
    if visibleBarY < pane.headerHgt or visibleBarY > pane.height then
        return
    end

    if capacityRatio ~= nil then
        drawCapacityBar(pane, iconX + 1, barY, iconSize - 2, ITEM_BAR_HEIGHT, capacityRatio)
    else
        drawMagazineBar(pane, iconX + 1, barY, iconSize - 2, ITEM_BAR_HEIGHT, magazineRatio)
    end
end

local function renderDetailsIndicators(pane)
    if not pane.itemslist then
        return
    end

    local player = getSpecificPlayer(pane.player or 0)
    if not player then
        return
    end

    local row = 0
    for _, stack in ipairs(pane.itemslist) do
        local items = stack and stack.items
        if items and items[1] then
            renderDetailsItemIndicator(pane, items[1], row, false, player)

            local collapsed = pane.collapsed and stack.name and pane.collapsed[stack.name]
            if not collapsed then
                local last = math.min(#items, ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER + 1)
                for index = 2, last do
                    row = row + 1
                    renderDetailsItemIndicator(pane, items[index], row, true, player)
                end
            end
            row = row + 1
        end
    end
end

local function renderIconIndicators(pane)
    local inventory = pane.inventory
    local player = getSpecificPlayer(pane.player or 0)
    if not inventory or not player then
        return
    end

    local xPadding = 10
    local yPadding = 10
    local cellWidth = 40
    local cellHeight = 40
    local columns = math.floor((pane.width - xPadding * 2) / cellWidth)
    if columns < 1 then
        return
    end

    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local capacityRatio = getItemContainerRatio(item, player)
        local magazineRatio = getMagazineRatio(item)
        if capacityRatio ~= nil or magazineRatio ~= nil then
            local column = index % columns
            local row = math.floor(index / columns)
            local iconX = column * cellWidth + xPadding + 4
            local iconY = row * cellHeight + yPadding + 4
            if capacityRatio ~= nil then
                drawCapacityBar(pane, iconX + 1, iconY + 32 - ITEM_BAR_HEIGHT,
                    30, ITEM_BAR_HEIGHT, capacityRatio)
            else
                drawMagazineBar(pane, iconX + 1, iconY + 32 - ITEM_BAR_HEIGHT,
                    30, ITEM_BAR_HEIGHT, magazineRatio)
            end
        end
    end
end

function CapacityIndicator.decorateButton(button, page)
    if not button then
        return button
    end

    button.cciPlayer = page and page.player or button.cciPlayer or 0

    if button.cciOriginalRender then
        return button
    end

    button.cciOriginalRender = button.render
    button.render = function(self)
        self.cciOriginalRender(self)
        renderCapacityIndicator(self)
    end

    return button
end

local originalAddContainerButton = ISInventoryPage.addContainerButton

function ISInventoryPage:addContainerButton(container, texture, name, tooltip, ...)
    local button = originalAddContainerButton(self, container, texture, name, tooltip, ...)
    return CapacityIndicator.decorateButton(button, self)
end

local originalRenderDetails = ISInventoryPane.renderdetails

function ISInventoryPane:renderdetails(doDragged, ...)
    local result = originalRenderDetails(self, doDragged, ...)
    if not doDragged then
        renderDetailsIndicators(self)
    end
    return result
end

local originalRenderIcons = ISInventoryPane.rendericons

function ISInventoryPane:rendericons(...)
    local result = originalRenderIcons(self, ...)
    renderIconIndicators(self)
    return result
end
