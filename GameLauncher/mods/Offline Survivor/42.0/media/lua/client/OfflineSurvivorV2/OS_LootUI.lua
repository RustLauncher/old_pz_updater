require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "OfflineSurvivorV2/OS_Constants"

local OS = OfflineSurvivorV2

OS.LootUI = ISCollapsableWindow:derive("OfflineSurvivorV2LootUI")
OS.LootList = ISScrollingListBox:derive("OfflineSurvivorV2LootList")

local scriptItemCache = {}
local fallbackTextureCache = {}

local function itemLabel(info)
    local name = tostring(info.displayName or info.fullType or "Item")
    local path = tostring(info.containerPath or "Body")
    local weight = tonumber(info.weight) or 0
    return string.format("%s  [%.2f]  - %s", name, weight, path)
end

local function selectedInfo(list)
    local row = list and list.items and list.selected and list.items[list.selected]
    return row and row.item or nil
end

-- The server sends a fullType, never an InventoryItem.  Resolve the item's
-- script locally so this displays the native icon of vanilla and installed
-- mod items without creating or synchronizing a new item instance.
local function getScriptItem(info)
    local fullType = tostring(info and info.fullType or "")
    if fullType == "" then return nil end

    local cached = scriptItemCache[fullType]
    if cached ~= nil then return cached or nil end

    local manager = getScriptManager and getScriptManager() or nil
    local scriptItem = nil
    if manager then
        local ok, item = pcall(function() return manager:FindItem(fullType) end)
        if ok then scriptItem = item end
        if not scriptItem then
            ok, item = pcall(function() return manager:getItem(fullType) end)
            if ok then scriptItem = item end
        end
    end

    scriptItemCache[fullType] = scriptItem or false
    return scriptItem
end

local function getFallbackTexture(info)
    local fullType = tostring(info and info.fullType or "")
    if fullType == "" then return nil end

    local cached = fallbackTextureCache[fullType]
    if cached ~= nil then return cached or nil end

    local texture = nil
    local scriptItem = getScriptItem(info)
    if scriptItem then
        local ok, normalTexture = pcall(function() return scriptItem:getNormalTexture() end)
        if ok then texture = normalTexture end
    end
    if not texture and getItemTex then
        local ok, itemTexture = pcall(getItemTex, fullType)
        if ok then texture = itemTexture end
    end

    fallbackTextureCache[fullType] = texture or false
    return texture
end

function OS.LootList:doDrawItem(y, row, alt)
    if not row.height then row.height = self.itemheight end
    if row.height <= 0 then return y + row.height end
    if (y + self:getYScroll() + row.height < 0) or (y + self:getYScroll() >= self.height) then
        return y + row.height
    end

    local textColor = row.textColor or self.textColor
    if self.selected == row.index then
        self:drawSelection(0, y, self:getWidth(), row.height - 1)
        textColor = row.selectedTextColor or self.selectedTextColor
    elseif self.mouseoverselected == row.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, self:getWidth(), row.height - 1)
    end
    self:drawRectBorder(0, y, self:getWidth(), row.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    local iconY = y + (row.height - 30) / 2
    local scriptItem = getScriptItem(row.item)
    local drawn = false
    if scriptItem and self.DrawScriptItemIcon then
        drawn = pcall(function()
            self:DrawScriptItemIcon(scriptItem, 5, iconY, 1, 30, 30)
        end)
    end
    if not drawn then
        local texture = getFallbackTexture(row.item)
        if texture then
            self:drawTextureScaledAspect(texture, 5, iconY, 30, 30, 1, 1, 1, 1)
        end
    end

    local textY = y + (row.height - self.fontHgt) / 2
    self:drawText(itemLabel(row.item), 42, textY, textColor.r, textColor.g, textColor.b, textColor.a, self.font)
    return y + row.height
end

function OS.LootList:new(x, y, width, height)
    return ISScrollingListBox.new(self, x, y, width, height)
end

function OS.LootUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.availableList = OS.LootList:new(12, 64, 338, 314)
    self.availableList:initialise()
    self.availableList:instantiate()
    self.availableList.itemheight = 38
    self.availableList.selected = 0
    self.availableList.drawBorder = true
    self:addChild(self.availableList)

    self.selectedList = OS.LootList:new(470, 64, 338, 314)
    self.selectedList:initialise()
    self.selectedList:instantiate()
    self.selectedList.itemheight = 38
    self.selectedList.selected = 0
    self.selectedList.drawBorder = true
    self:addChild(self.selectedList)

    self.addButton = ISButton:new(362, 155, 96, 25, OS.translate("Add", "Add >"), self, OS.LootUI.onAdd)
    self.addButton:initialise()
    self:addChild(self.addButton)

    self.removeButton = ISButton:new(362, 190, 96, 25, OS.translate("Remove", "< Remove"), self, OS.LootUI.onRemove)
    self.removeButton:initialise()
    self:addChild(self.removeButton)

    self.stealButton = ISButton:new(604, self.height - 42, 122, 25, OS.translate("Steal", "Steal (%1/%2)", 0, self.maxItems or 3), self, OS.LootUI.onSteal)
    self.stealButton:initialise()
    self:addChild(self.stealButton)

    self.cancelButton = ISButton:new(736, self.height - 42, 72, 25, OS.translate("Cancel", "Cancel"), self, OS.LootUI.onCloseButton)
    self.cancelButton:initialise()
    self:addChild(self.cancelButton)
end

function OS.LootUI:setLootData(args)
    self.sessionId = args and args.sessionId or nil
    self.targetName = args and args.targetName or OS.translate("Player", "Player")
    self.maxItems = math.max(1, math.min(tonumber(args and args.maxItems) or 3, 20))
    self.availableItems = {}
    self.selectedItems = {}
    self.waiting = false

    for _, info in ipairs(args and args.items or {}) do
        self.availableItems[#self.availableItems + 1] = info
    end
    self:refreshLists()
end

function OS.LootUI:refreshLists()
    self.availableList:clear()
    self.selectedList:clear()

    for _, info in ipairs(self.availableItems or {}) do
        self.availableList:addItem(itemLabel(info), info)
    end
    for _, info in ipairs(self.selectedItems or {}) do
        self.selectedList:addItem(itemLabel(info), info)
    end

    local selectedCount = #(self.selectedItems or {})
    self.addButton:setEnable(not self.waiting and selectedCount < self.maxItems and #(self.availableItems or {}) > 0)
    self.removeButton:setEnable(not self.waiting and selectedCount > 0)
    self.stealButton:setEnable(not self.waiting and selectedCount > 0)
    self.stealButton.title = OS.translate("Steal", "Steal (%1/%2)", selectedCount, self.maxItems)
end

function OS.LootUI:onAdd()
    if self.waiting or #(self.selectedItems or {}) >= self.maxItems then return end
    local info = selectedInfo(self.availableList)
    if not info or not info.itemId then return end

    for index, candidate in ipairs(self.availableItems) do
        if tostring(candidate.itemId) == tostring(info.itemId) then
            table.remove(self.availableItems, index)
            self.selectedItems[#self.selectedItems + 1] = candidate
            self:refreshLists()
            return
        end
    end
end

function OS.LootUI:onRemove()
    if self.waiting then return end
    local info = selectedInfo(self.selectedList)
    if not info or not info.itemId then return end

    for index, candidate in ipairs(self.selectedItems) do
        if tostring(candidate.itemId) == tostring(info.itemId) then
            table.remove(self.selectedItems, index)
            self.availableItems[#self.availableItems + 1] = candidate
            self:refreshLists()
            return
        end
    end
end

function OS.LootUI:onSteal()
    if self.waiting or not self.sessionId or #(self.selectedItems or {}) == 0 then return end

    local itemIds = {}
    for _, info in ipairs(self.selectedItems) do
        itemIds[#itemIds + 1] = tostring(info.itemId)
    end

    local player = getSpecificPlayer(0)
    if not player then return end
    self.waiting = true
    self:refreshLists()
    sendClientCommand(player, OS.MODULE, OS.COMMAND_COMMIT_LOOT, {
        sessionId = self.sessionId,
        itemIds = itemIds,
    })
end

function OS.LootUI:onCloseButton()
    self:close()
end

function OS.LootUI:silentClose()
    self.silent = true
    self:close()
end

function OS.LootUI:close()
    if not self.silent and self.sessionId then
        local player = getSpecificPlayer(0)
        if player then
            sendClientCommand(player, OS.MODULE, OS.COMMAND_CANCEL_LOOT, { sessionId = self.sessionId })
        end
    end

    self:removeFromUIManager()
    if OS.ActiveLootUI == self then OS.ActiveLootUI = nil end
end

function OS.LootUI:finish()
    self.silent = true
    self.sessionId = nil
    self:close()
end

function OS.LootUI:render()
    ISCollapsableWindow.render(self)
    self:drawText(OS.translate("AvailableItems", "Available Items"), 12, 38, 1, 1, 1, 1, UIFont.Small)
    self:drawText(OS.translate("SelectedItems", "Selected Items"), 470, 38, 1, 1, 1, 1, UIFont.Small)
    self:drawText(OS.translate("LootInstruction", "Choose up to %1 item(s) from %2.", self.maxItems or 3, self.targetName or OS.translate("Player", "Player")), 12, self.height - 70, 1, 1, 1, 1, UIFont.Small)
end

function OS.LootUI:new(x, y)
    local object = ISCollapsableWindow.new(self, x, y, 820, 470)
    setmetatable(object, self)
    self.__index = self
    object.title = OS.translate("LootTitle", "Search Offline Survivor")
    object.resizable = false
    object.availableItems = {}
    object.selectedItems = {}
    object.maxItems = 3
    return object
end

function OS.openLootUI(args)
    if OS.ActiveLootUI then OS.ActiveLootUI:silentClose() end

    local width, height = 820, 470
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local ui = OS.LootUI:new(x, y)
    ui:initialise()
    ui:addToUIManager()
    ui:setLootData(args or {})
    OS.ActiveLootUI = ui
    return ui
end
