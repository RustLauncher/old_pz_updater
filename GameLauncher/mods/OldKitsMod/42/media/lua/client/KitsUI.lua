require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 520
local PANEL_H = 500
local HEADER_H = 38
local PAD = 10
local CARD_PAD = 8
local ICON_SIZE = 36
local ICON_GAP = 4

local COLOR_BG         = { r = 0.08, g = 0.08, b = 0.10, a = 0.95 }
local COLOR_HEADER     = { r = 0.12, g = 0.11, b = 0.14, a = 1 }
local COLOR_CARD       = { r = 0.13, g = 0.13, b = 0.16, a = 1 }
local COLOR_CARD_LOCK  = { r = 0.10, g = 0.09, b = 0.11, a = 1 }
local COLOR_BORDER     = { r = 0.25, g = 0.24, b = 0.28, a = 1 }
local COLOR_ACCENT     = { r = 0.95, g = 0.60, b = 0.12, a = 1 }
local COLOR_ACCENT_DIM = { r = 0.55, g = 0.38, b = 0.18, a = 1 }
local COLOR_TEXT       = { r = 0.92, g = 0.90, b = 0.88, a = 1 }
local COLOR_TEXT_SEC   = { r = 0.60, g = 0.58, b = 0.56, a = 1 }
local COLOR_READY      = { r = 0.30, g = 0.82, b = 0.40, a = 1 }
local COLOR_COOLDOWN   = { r = 0.95, g = 0.35, b = 0.25, a = 1 }
local COLOR_LOCKED     = { r = 0.60, g = 0.22, b = 0.22, a = 1 }
local COLOR_BTN        = { r = 0.90, g = 0.56, b = 0.10, a = 1 }
local COLOR_BTN_HOVER  = { r = 1.00, g = 0.65, b = 0.18, a = 1 }
local COLOR_BTN_DIS    = { r = 0.22, g = 0.22, b = 0.25, a = 1 }
local COLOR_ICON_BG    = { r = 0.18, g = 0.17, b = 0.20, a = 1 }
local COLOR_ADMIN      = { r = 0.22, g = 0.52, b = 0.88, a = 0.9 }
local COLOR_SEPARATOR  = { r = 0.20, g = 0.19, b = 0.23, a = 1 }

local function getItemTexture(itemType)
    local si = ScriptManager.instance:getItem(itemType)
    if si then
        local texName = si:getIcon()
        if texName then
            local tex = getTexture("Item_" .. texName)
            if tex then return tex end
            tex = getTexture(texName)
            if tex then return tex end
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
    o.kitCardHeights = {}
    o.showingAdmin = false
    return o
end

function KitsUI:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(PANEL_W - 34, 6, 26, 26, "X", self, KitsUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColorMouseOver = { r = 0.6, g = 0.15, b = 0.15, a = 0.8 }
    self.closeBtn.textColor = { r = 0.7, g = 0.7, b = 0.7, a = 1 }
    self:addChild(self.closeBtn)

    self.adminBtn = ISButton:new(PAD, 8, 65, 22, "ADMIN", self, KitsUI.onToggleAdmin)
    self.adminBtn:initialise()
    self.adminBtn:instantiate()
    self.adminBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminBtn.backgroundColor = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = 0.7 }
    self.adminBtn.backgroundColorMouseOver = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = 1 }
    self.adminBtn.textColor = COLOR_TEXT
    self.adminBtn:setVisible(false)
    self:addChild(self.adminBtn)

    self:buildKitsPanel()
    self:buildAdminPanel()
    KitsClient.CheckAdmin()
end

function KitsUI:buildKitsPanel()
    self.kitsPanel = ISPanel:new(0, HEADER_H + 2, PANEL_W, PANEL_H - HEADER_H - 2)
    self.kitsPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.kitsPanel)

    local yOff = CARD_PAD
    for i, kit in ipairs(KitsConfig.Kits) do
        local cardH = self:createKitCard(kit, yOff, i)
        yOff = yOff + cardH + CARD_PAD
    end

    local totalH = HEADER_H + 2 + yOff + PAD
    if totalH > PANEL_H then
        self:setHeight(totalH)
        self.kitsPanel:setHeight(totalH - HEADER_H - 2)
    end
end

function KitsUI:createKitCard(kit, yOff, index)
    local cardX = PAD
    local cardW = PANEL_W - PAD * 2

    local itemCount = #kit.items
    local iconsPerRow = math.floor((cardW - 24) / (ICON_SIZE + ICON_GAP))
    local iconRows = math.ceil(itemCount / iconsPerRow)
    local cardH = 44 + iconRows * (ICON_SIZE + ICON_GAP) + 8 + 36

    local card = ISPanel:new(cardX, yOff, cardW, cardH)
    card.backgroundColor = COLOR_CARD
    card.borderColor = COLOR_BORDER
    self.kitsPanel:addChild(card)
    self.kitCards[kit.id] = card
    self.kitCardHeights[kit.id] = cardH

    local nameLabel = ISLabel:new(
        12, 10, 20, kit.name,
        COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    local permText = ""
    if kit.permission and kit.permission ~= "all" then
        permText = kit.permission:upper()
    end
    local cdText = tostring(kit.cooldown) .. " min"
    if permText ~= "" then
        cdText = cdText .. "  |  " .. permText
    end

    local cdLabel = ISLabel:new(
        12, 28, 14, cdText,
        COLOR_TEXT_SEC.r, COLOR_TEXT_SEC.g, COLOR_TEXT_SEC.b, COLOR_TEXT_SEC.a,
        UIFont.Small, true
    )
    card:addChild(cdLabel)

    local statusLabel = ISLabel:new(
        cardW - 110, 10, 20, "LISTO",
        COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, COLOR_READY.a,
        UIFont.Medium, true
    )
    card:addChild(statusLabel)
    self.kitCooldownLabels[kit.id] = statusLabel

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

    local btnW = 130
    local btnH = 30
    local btn = ISButton:new(
        cardW - btnW - 10, cardH - btnH - 8, btnW, btnH,
        "RECLAMAR", self, KitsUI.onClaimKit
    )
    btn:initialise()
    btn:instantiate()
    btn.internal = kit.id
    btn.backgroundColor = { r = COLOR_BTN.r, g = COLOR_BTN.g, b = COLOR_BTN.b, a = 1 }
    btn.backgroundColorMouseOver = { r = COLOR_BTN_HOVER.r, g = COLOR_BTN_HOVER.g, b = COLOR_BTN_HOVER.b, a = 1 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    btn.font = UIFont.Medium
    card:addChild(btn)
    self.kitButtons[kit.id] = btn

    return cardH
end

function KitsUI:buildAdminPanel()
    local panelY = HEADER_H + 2
    local panelH = self:getHeight() - HEADER_H - 2
    self.adminPanel = ISPanel:new(0, panelY, PANEL_W, panelH)
    self.adminPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminPanel:setVisible(false)
    self:addChild(self.adminPanel)

    local y = PAD
    local adminTitle = ISLabel:new(PAD, y, 22, "Gestion de Permisos",
        COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, COLOR_ACCENT.a, UIFont.Medium, true)
    self.adminPanel:addChild(adminTitle)
    y = y + 30

    local plLabel = ISLabel:new(PAD, y, 18, "Jugador:",
        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, COLOR_TEXT.a, UIFont.Small, true)
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
        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, COLOR_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(grLabel)
    self.adminGroupEntry = ISTextEntryBox:new("", PAD + 70, y - 2, 200, 22)
    self.adminGroupEntry:initialise()
    self.adminGroupEntry:instantiate()
    self.adminPanel:addChild(self.adminGroupEntry)
    y = y + 36

    local btnW = 150
    local btnH = 28
    local btnGap = 8

    local addBtn = ISButton:new(PAD, y, btnW, btnH, "Dar Grupo", self, KitsUI.onAdminAddGroup)
    addBtn:initialise()
    addBtn:instantiate()
    addBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    addBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    addBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(addBtn)

    local removeBtn = ISButton:new(PAD + btnW + btnGap, y, btnW, btnH, "Quitar Grupo", self, KitsUI.onAdminRemoveGroup)
    removeBtn:initialise()
    removeBtn:instantiate()
    removeBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.9 }
    removeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
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

    local refLabel = ISLabel:new(PAD, y, 18, "Grupos disponibles:",
        COLOR_TEXT_SEC.r, COLOR_TEXT_SEC.g, COLOR_TEXT_SEC.b, COLOR_TEXT_SEC.a, UIFont.Small, true)
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
        self.adminBtn.backgroundColor = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = 0.7 }
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
                label.name = "BLOQUEADO"
                label:setColor(COLOR_LOCKED.r, COLOR_LOCKED.g, COLOR_LOCKED.b, COLOR_LOCKED.a)
                btn:setEnable(false)
                btn.backgroundColor = { r = COLOR_BTN_DIS.r, g = COLOR_BTN_DIS.g, b = COLOR_BTN_DIS.b, a = 1 }
                btn.textColor = { r = 0.45, g = 0.45, b = 0.48, a = 1 }
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
                    btn.backgroundColor = { r = COLOR_BTN_DIS.r, g = COLOR_BTN_DIS.g, b = COLOR_BTN_DIS.b, a = 1 }
                    btn.textColor = { r = 0.45, g = 0.45, b = 0.48, a = 1 }
                else
                    label.name = "LISTO"
                    label:setColor(COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, COLOR_READY.a)
                    btn:setEnable(true)
                    btn.backgroundColor = { r = COLOR_BTN.r, g = COLOR_BTN.g, b = COLOR_BTN.b, a = 1 }
                    btn.textColor = { r = 1, g = 1, b = 1, a = 1 }
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
    self:drawRect(0, 0, PANEL_W, HEADER_H, 1, COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b)
    self:drawRect(0, HEADER_H - 2, PANEL_W, 2, 1, COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b)
    local titleW = getTextManager():MeasureStringX(UIFont.Medium, "KITS")
    local titleX = (PANEL_W - titleW) / 2
    self:drawText("KITS", titleX, 10, COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 1, UIFont.Medium)
end

function KitsUI:render()
    ISPanel.render(self)

    if self.showingAdmin then return end

    for _, kit in ipairs(KitsConfig.Kits) do
        local card = self.kitCards[kit.id]
        local items = self.kitItemData[kit.id]
        if card and items and card:isVisible() then
            local cx = card:getX()
            local cy = card:getY() + HEADER_H + 2

            local sepY = cy + 42
            self:drawRect(cx + 10, sepY, card:getWidth() - 20, 1,
                0.5, COLOR_SEPARATOR.r, COLOR_SEPARATOR.g, COLOR_SEPARATOR.b)

            local iconStartY = sepY + 6
            local iconStartX = cx + 12
            local maxIconsPerRow = math.floor((card:getWidth() - 24) / (ICON_SIZE + ICON_GAP))
            local col = 0
            local row = 0

            for idx, item in ipairs(items) do
                local ix = iconStartX + col * (ICON_SIZE + ICON_GAP)
                local iy = iconStartY + row * (ICON_SIZE + ICON_GAP)

                self:drawRect(ix, iy, ICON_SIZE, ICON_SIZE,
                    1, COLOR_ICON_BG.r, COLOR_ICON_BG.g, COLOR_ICON_BG.b)
                self:drawRectBorder(ix, iy, ICON_SIZE, ICON_SIZE,
                    0.3, COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b)

                if item.tex then
                    self:drawTextureScaled(item.tex, ix + 2, iy + 2, ICON_SIZE - 4, ICON_SIZE - 4, 1, 1, 1, 1)
                end

                if item.count > 1 then
                    local countStr = tostring(item.count)
                    local tw = getTextManager():MeasureStringX(UIFont.Small, countStr)
                    local tx = ix + ICON_SIZE - tw - 2
                    local ty = iy + ICON_SIZE - 14
                    self:drawRect(tx - 2, ty, tw + 4, 14, 0.75, 0, 0, 0)
                    self:drawText(countStr, tx, ty, 1, 1, 1, 0.95, UIFont.Small)
                end

                local mx = self:getMouseX()
                local my = self:getMouseY()
                if mx >= ix and mx <= ix + ICON_SIZE and my >= iy and my <= iy + ICON_SIZE then
                    local tooltip = item.name
                    if item.count > 1 then
                        tooltip = item.name .. " x" .. tostring(item.count)
                    end
                    local ttw = getTextManager():MeasureStringX(UIFont.Small, tooltip) + 10
                    local ttx = ix
                    local tty = iy - 18
                    self:drawRect(ttx - 2, tty - 2, ttw + 4, 18, 0.9, 0.05, 0.05, 0.07)
                    self:drawRectBorder(ttx - 2, tty - 2, ttw + 4, 18, 0.6, COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b)
                    self:drawText(tooltip, ttx + 3, tty, COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 1, UIFont.Small)
                end

                col = col + 1
                if col >= maxIconsPerRow then
                    col = 0
                    row = row + 1
                end
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
