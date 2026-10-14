require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 640
local PANEL_H = 500
local CARD_H = 110
local CARD_PAD = 6
local HEADER_H = 44
local PAD = 12
local ICON_SIZE = 32

local COLOR_BG         = { r = 0.06, g = 0.06, b = 0.08, a = 0.96 }
local COLOR_CARD       = { r = 0.12, g = 0.12, b = 0.14, a = 1 }
local COLOR_CARD_HOVER = { r = 0.16, g = 0.16, b = 0.18, a = 1 }
local COLOR_CARD_LOCK  = { r = 0.08, g = 0.08, b = 0.10, a = 1 }
local COLOR_BORDER     = { r = 0.22, g = 0.22, b = 0.26, a = 1 }
local COLOR_ACCENT     = { r = 0.92, g = 0.58, b = 0.12, a = 1 }
local COLOR_ACCENT_DIM = { r = 0.50, g = 0.35, b = 0.15, a = 1 }
local COLOR_TEXT       = { r = 0.88, g = 0.88, b = 0.90, a = 1 }
local COLOR_DIM        = { r = 0.48, g = 0.48, b = 0.52, a = 1 }
local COLOR_READY      = { r = 0.25, g = 0.78, b = 0.25, a = 1 }
local COLOR_COOLDOWN   = { r = 0.88, g = 0.22, b = 0.22, a = 1 }
local COLOR_LOCKED     = { r = 0.55, g = 0.18, b = 0.18, a = 1 }
local COLOR_BTN        = { r = 0.92, g = 0.58, b = 0.12, a = 1 }
local COLOR_BTN_DIS    = { r = 0.30, g = 0.30, b = 0.32, a = 1 }
local COLOR_ADMIN      = { r = 0.22, g = 0.52, b = 0.88, a = 0.9 }
local COLOR_ICON_BG    = { r = 0.08, g = 0.08, b = 0.10, a = 0.8 }

local function getItemTexture(itemType)
    local si = ScriptManager.instance:getItem(itemType)
    if si then
        local texName = si:getIcon()
        if texName then
            return getTexture("Item_" .. texName)
        end
    end
    return nil
end

local function getItemDisplayName(itemType)
    local si = ScriptManager.instance:getItem(itemType)
    if si then
        return si:getDisplayName()
    end
    return itemType:gsub("Base%.", "")
end

function KitsUI:new(x, y)
    local o = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = COLOR_BG
    o.borderColor = COLOR_BORDER
    o.moveWithMouse = true
    o.kitButtons = {}
    o.kitCooldownLabels = {}
    o.kitCards = {}
    o.kitNameLabels = {}
    o.kitItemData = {}
    o.showingAdmin = false
    return o
end

function KitsUI:createChildren()
    ISPanel.createChildren(self)

    self.titleLabel = ISLabel:new(
        PANEL_W / 2 - 30, 10, HEADER_H - 14,
        "KITS", COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a,
        UIFont.Large, true
    )
    self:addChild(self.titleLabel)

    self.closeBtn = ISButton:new(PANEL_W - 36, 8, 28, 28, "X", self, KitsUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 0.5, g = 0.12, b = 0.12, a = 0.8 }
    self.closeBtn.backgroundColor = { r = 0.6, g = 0.12, b = 0.12, a = 0.85 }
    self.closeBtn.textColor = COLOR_TEXT
    self:addChild(self.closeBtn)

    self.adminBtn = ISButton:new(10, 10, 70, 25, "ADMIN", self, KitsUI.onToggleAdmin)
    self.adminBtn:initialise()
    self.adminBtn:instantiate()
    self.adminBtn.borderColor = { r = COLOR_ADMIN.r * 0.7, g = COLOR_ADMIN.g * 0.7, b = COLOR_ADMIN.b * 0.7, a = 1 }
    self.adminBtn.backgroundColor = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = COLOR_ADMIN.a }
    self.adminBtn.textColor = COLOR_TEXT
    self.adminBtn:setVisible(false)
    self:addChild(self.adminBtn)

    self.headerLine = ISPanel:new(PAD, HEADER_H, PANEL_W - PAD * 2, 1)
    self.headerLine.backgroundColor = COLOR_BORDER
    self:addChild(self.headerLine)

    self:buildKitsPanel()
    self:buildAdminPanel()
    KitsClient.CheckAdmin()
end

function KitsUI:buildKitsPanel()
    self.kitsPanel = ISPanel:new(0, HEADER_H + 4, PANEL_W, PANEL_H - HEADER_H - 4)
    self.kitsPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.kitsPanel)

    local yOff = PAD
    for i, kit in ipairs(KitsConfig.Kits) do
        self:createKitCard(kit, yOff, i)
        yOff = yOff + CARD_H + CARD_PAD
    end

    local totalH = HEADER_H + 4 + yOff + PAD
    if totalH > PANEL_H then
        self:setHeight(totalH)
        self.kitsPanel:setHeight(totalH - HEADER_H - 4)
    end
end

function KitsUI:buildAdminPanel()
    local panelY = HEADER_H + 4
    local panelH = PANEL_H - HEADER_H - 4
    self.adminPanel = ISPanel:new(0, panelY, PANEL_W, panelH)
    self.adminPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminPanel:setVisible(false)
    self:addChild(self.adminPanel)

    local y = PAD
    local labelC = COLOR_TEXT

    local adminTitle = ISLabel:new(PAD, y, 22, "Gestion de Permisos",
        COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a, UIFont.Medium, true)
    self.adminPanel:addChild(adminTitle)
    y = y + 30

    local plLabel = ISLabel:new(PAD, y, 18, "Jugador:",
        labelC.r, labelC.g, labelC.b, labelC.a, UIFont.Small, true)
    self.adminPanel:addChild(plLabel)
    self.adminPlayerEntry = ISTextEntryBox:new("", PAD + 70, y - 2, 200, 22)
    self.adminPlayerEntry:initialise()
    self.adminPlayerEntry:instantiate()
    self.adminPanel:addChild(self.adminPlayerEntry)

    local listBtn = ISButton:new(PAD + 280, y - 2, 110, 22, "Ver Online", self, KitsUI.onAdminListPlayers)
    listBtn:initialise()
    listBtn:instantiate()
    listBtn.backgroundColor = COLOR_CARD
    listBtn.borderColor = COLOR_BORDER
    listBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(listBtn)
    y = y + 32

    local grLabel = ISLabel:new(PAD, y, 18, "Grupo:",
        labelC.r, labelC.g, labelC.b, labelC.a, UIFont.Small, true)
    self.adminPanel:addChild(grLabel)
    self.adminGroupEntry = ISTextEntryBox:new("", PAD + 70, y - 2, 200, 22)
    self.adminGroupEntry:initialise()
    self.adminGroupEntry:instantiate()
    self.adminPanel:addChild(self.adminGroupEntry)
    y = y + 36

    local btnW = 160
    local btnH = 28
    local btnGap = 10

    local addBtn = ISButton:new(PAD, y, btnW, btnH, "Dar Grupo", self, KitsUI.onAdminAddGroup)
    addBtn:initialise()
    addBtn:instantiate()
    addBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    addBtn.borderColor = COLOR_BORDER
    addBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(addBtn)

    local removeBtn = ISButton:new(PAD + btnW + btnGap, y, btnW, btnH, "Quitar Grupo", self, KitsUI.onAdminRemoveGroup)
    removeBtn:initialise()
    removeBtn:instantiate()
    removeBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.9 }
    removeBtn.borderColor = COLOR_BORDER
    removeBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(removeBtn)

    local infoBtn = ISButton:new(PAD + (btnW + btnGap) * 2, y, btnW, btnH, "Ver Grupos", self, KitsUI.onAdminListGroups)
    infoBtn:initialise()
    infoBtn:instantiate()
    infoBtn.backgroundColor = COLOR_CARD
    infoBtn.borderColor = COLOR_BORDER
    infoBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(infoBtn)
    y = y + 40

    local refLabel = ISLabel:new(PAD, y, 18, "Grupos disponibles en config:",
        COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, UIFont.Small, true)
    self.adminPanel:addChild(refLabel)
    y = y + 20

    local groups = {}
    for _, kit in ipairs(KitsConfig.Kits) do
        local p = kit.permission or "all"
        if p ~= "all" and p ~= "admin" then
            local found = false
            for _, g in ipairs(groups) do
                if g == p then found = true end
            end
            if not found then table.insert(groups, p) end
        end
    end
    local groupsText = #groups > 0 and table.concat(groups, ", ") or "(solo 'all' y 'admin')"
    local groupsListLabel = ISLabel:new(PAD, y, 18, groupsText,
        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, COLOR_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(groupsListLabel)
end

function KitsUI:createKitCard(kit, yOff, index)
    local cardX = PAD
    local cardW = PANEL_W - PAD * 2

    local card = ISPanel:new(cardX, yOff, cardW, CARD_H)
    card.backgroundColor = COLOR_CARD
    card.borderColor = COLOR_BORDER
    self.kitsPanel:addChild(card)
    self.kitCards[kit.id] = card

    local nameLabel = ISLabel:new(
        14, 8, 22, kit.name,
        COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    local permTag = ""
    if kit.permission and kit.permission ~= "all" then
        permTag = " [" .. kit.permission:upper() .. "]"
    end
    local cdText = "Cooldown: " .. kit.cooldown .. " min" .. permTag
    local cdLabel = ISLabel:new(
        14, 32, 18, cdText,
        COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a,
        UIFont.Small, true
    )
    card:addChild(cdLabel)

    local itemData = {}
    for _, entry in ipairs(kit.items) do
        local tex = getItemTexture(entry.type)
        local displayName = getItemDisplayName(entry.type)
        table.insert(itemData, {
            tex = tex,
            name = displayName,
            count = entry.count,
            type = entry.type,
        })
    end
    self.kitItemData[kit.id] = itemData

    local statusLabel = ISLabel:new(
        cardW - 200, 8, 22, "LISTO",
        COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, COLOR_READY.a,
        UIFont.Medium, true
    )
    card:addChild(statusLabel)
    self.kitCooldownLabels[kit.id] = statusLabel

    local btnW = 120
    local btnH = 32
    local btn = ISButton:new(
        cardW - btnW - 12, CARD_H - btnH - 10, btnW, btnH,
        "RECLAMAR", self, KitsUI.onClaimKit
    )
    btn:initialise()
    btn:instantiate()
    btn.internal = kit.id
    btn.backgroundColor = { r = COLOR_BTN.r, g = COLOR_BTN.g, b = COLOR_BTN.b, a = COLOR_BTN.a }
    btn.borderColor = { r = COLOR_BTN.r * 0.6, g = COLOR_BTN.g * 0.6, b = COLOR_BTN.b * 0.6, a = 1 }
    btn.textColor = { r = 0.05, g = 0.05, b = 0.05, a = 1 }
    card:addChild(btn)
    self.kitButtons[kit.id] = btn
end

function KitsUI:onClaimKit(button)
    local kitId = button.internal
    if not kitId then return end
    if not KitsClient.HasPermission(kitId) then return end
    KitsClient.RequestKit(kitId)
end

function KitsUI:onToggleAdmin()
    self.showingAdmin = not self.showingAdmin
    self.kitsPanel:setVisible(not self.showingAdmin)
    self.adminPanel:setVisible(self.showingAdmin)
    if self.showingAdmin then
        self.adminBtn.backgroundColor = { r = COLOR_ACCENT.r, g = COLOR_ACCENT.g, b = COLOR_ACCENT.b, a = 0.9 }
    else
        self.adminBtn.backgroundColor = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = COLOR_ADMIN.a }
    end
end

function KitsUI:onAdminAddGroup()
    local playerName = self.adminPlayerEntry:getText()
    local group = self.adminGroupEntry:getText()
    if playerName == "" or group == "" then return end
    KitsClient.AdminAddGroup(playerName, group)
end

function KitsUI:onAdminRemoveGroup()
    local playerName = self.adminPlayerEntry:getText()
    local group = self.adminGroupEntry:getText()
    if playerName == "" or group == "" then return end
    KitsClient.AdminRemoveGroup(playerName, group)
end

function KitsUI:onAdminListGroups()
    local playerName = self.adminPlayerEntry:getText()
    if playerName == "" then return end
    KitsClient.AdminListGroups(playerName)
end

function KitsUI:onAdminListPlayers()
    KitsClient.AdminListPlayers()
end

function KitsUI:updateAdminButton()
    if self.adminBtn then
        self.adminBtn:setVisible(KitsClient.IsAdmin)
    end
end

function KitsUI:updateCooldowns()
    for _, kit in ipairs(KitsConfig.Kits) do
        local label = self.kitCooldownLabels[kit.id]
        local btn = self.kitButtons[kit.id]
        local card = self.kitCards[kit.id]
        local nameLabel = self.kitNameLabels[kit.id]
        if label and btn then
            local hasPermission = KitsClient.HasPermission(kit.id)

            if not hasPermission then
                label.name = "SIN ACCESO"
                label:setColor(COLOR_LOCKED.r, COLOR_LOCKED.g, COLOR_LOCKED.b, COLOR_LOCKED.a)
                btn:setEnable(false)
                btn.backgroundColor = { r = COLOR_BTN_DIS.r, g = COLOR_BTN_DIS.g, b = COLOR_BTN_DIS.b, a = COLOR_BTN_DIS.a }
                if card then card.backgroundColor = COLOR_CARD_LOCK end
                if nameLabel then nameLabel:setColor(COLOR_ACCENT_DIM.r, COLOR_ACCENT_DIM.g, COLOR_ACCENT_DIM.b, COLOR_ACCENT_DIM.a) end
            else
                if card then card.backgroundColor = COLOR_CARD end
                if nameLabel then nameLabel:setColor(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a) end
                local remainMs = KitsClient.Cooldowns[kit.id] or 0
                if remainMs > 0 then
                    local secs = math.ceil(remainMs / 1000)
                    local mins = math.floor(secs / 60)
                    local s = secs % 60
                    label.name = string.format("%02d:%02d", mins, s)
                    label:setColor(COLOR_COOLDOWN.r, COLOR_COOLDOWN.g, COLOR_COOLDOWN.b, COLOR_COOLDOWN.a)
                    btn:setEnable(false)
                    btn.backgroundColor = { r = COLOR_BTN_DIS.r, g = COLOR_BTN_DIS.g, b = COLOR_BTN_DIS.b, a = COLOR_BTN_DIS.a }
                else
                    label.name = "LISTO"
                    label:setColor(COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, COLOR_READY.a)
                    btn:setEnable(true)
                    btn.backgroundColor = { r = COLOR_BTN.r, g = COLOR_BTN.g, b = COLOR_BTN.b, a = COLOR_BTN.a }
                end
            end
        end
    end
end

function KitsUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    KitsUI.instance = nil
end

function KitsUI:update()
    ISPanel.update(self)
    if not self.lastRefresh then self.lastRefresh = 0 end
    local now = getTimestampMs()
    if now - self.lastRefresh > 2000 then
        KitsClient.RequestCooldowns()
        self.lastRefresh = now
    end
end

function KitsUI:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, PANEL_W, HEADER_H, 0.3, COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b)
end

function KitsUI:render()
    ISPanel.render(self)

    if self.showingAdmin then return end

    for _, kit in ipairs(KitsConfig.Kits) do
        local card = self.kitCards[kit.id]
        local items = self.kitItemData[kit.id]
        if card and items and card:isVisible() then
            local cx = card:getX()
            local cy = card:getY() + HEADER_H + 4
            local iconY = cy + 52
            local iconX = cx + 14
            local gap = ICON_SIZE + 8

            for idx, item in ipairs(items) do
                if iconX + ICON_SIZE > cx + card:getWidth() - 140 then
                    break
                end

                self:drawRect(iconX - 1, iconY - 1, ICON_SIZE + 2, ICON_SIZE + 2,
                    COLOR_ICON_BG.a, COLOR_ICON_BG.r, COLOR_ICON_BG.g, COLOR_ICON_BG.b)
                self:drawRectBorder(iconX - 1, iconY - 1, ICON_SIZE + 2, ICON_SIZE + 2,
                    0.4, COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b)

                if item.tex then
                    self:drawTextureScaled(item.tex, iconX, iconY, ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
                end

                if item.count > 1 then
                    local countStr = "x" .. tostring(item.count)
                    self:drawTextRight(countStr,
                        iconX + ICON_SIZE + 1, iconY + ICON_SIZE - 14,
                        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.9,
                        UIFont.Small)
                end

                iconX = iconX + gap
            end
        end
    end
end

function KitsUI.Toggle()
    if KitsUI.instance and KitsUI.instance:isVisible() then
        KitsUI.instance:onClose()
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x = (sw - PANEL_W) / 2
    local y = (sh - PANEL_H) / 2

    local ui = KitsUI:new(x, y)
    ui:initialise()
    ui:addToUIManager()
    ui:setVisible(true)
    KitsUI.instance = ui

    KitsClient.RequestCooldowns()
end
