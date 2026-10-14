require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 460
local PANEL_H = 500
local HEADER_H = 42
local PAD = 12
local CARD_PAD = 6
local ICON_SIZE = 40
local ICON_GAP = 6

local C_BG        = { r = 0.07, g = 0.07, b = 0.09, a = 0.97 }
local C_HEADER    = { r = 0.10, g = 0.10, b = 0.12, a = 1 }
local C_CARD      = { r = 0.12, g = 0.12, b = 0.15, a = 1 }
local C_CARD_LOCK = { r = 0.09, g = 0.09, b = 0.11, a = 1 }
local C_BORDER    = { r = 0.22, g = 0.21, b = 0.25, a = 1 }
local C_ACCENT    = { r = 0.95, g = 0.58, b = 0.08, a = 1 }
local C_ACCENT_DK = { r = 0.50, g = 0.33, b = 0.10, a = 1 }
local C_TEXT      = { r = 0.93, g = 0.91, b = 0.89, a = 1 }
local C_TEXT2     = { r = 0.55, g = 0.53, b = 0.50, a = 1 }
local C_GREEN     = { r = 0.20, g = 0.80, b = 0.35, a = 1 }
local C_RED       = { r = 0.95, g = 0.30, b = 0.20, a = 1 }
local C_RED_DK    = { r = 0.55, g = 0.18, b = 0.15, a = 1 }
local C_BTN       = { r = 0.88, g = 0.54, b = 0.08, a = 1 }
local C_BTN_HI    = { r = 1.00, g = 0.65, b = 0.15, a = 1 }
local C_BTN_OFF   = { r = 0.20, g = 0.20, b = 0.22, a = 1 }
local C_SLOT      = { r = 0.16, g = 0.15, b = 0.18, a = 1 }
local C_SLOT_BD   = { r = 0.28, g = 0.27, b = 0.30, a = 0.5 }
local C_ADMIN     = { r = 0.25, g = 0.55, b = 0.90, a = 0.85 }
local C_SEP       = { r = 0.18, g = 0.17, b = 0.20, a = 1 }

local function getItemTexture(itemType)
    local si = ScriptManager.instance:getItem(itemType)
    if not si then return nil end
    local texName = si:getIcon()
    if texName and texName ~= "" then
        local tex = getTexture("Item_" .. texName)
        if tex then return tex end
        tex = getTexture(texName)
        if tex then return tex end
    end
    local ift = si:getIconsForTexture()
    if ift then
        local first = ift:get(0)
        if first then
            local tex = getTexture("Item_" .. first)
            if tex then return tex end
        end
    end
    local shortName = itemType:gsub("Base%.", "")
    local tex = getTexture("Item_" .. shortName)
    if tex then return tex end
    return nil
end

local function getItemDisplayName(itemType)
    local si = ScriptManager.instance:getItem(itemType)
    if si then return si:getDisplayName() end
    return itemType:gsub("Base%.", "")
end

function KitsUI:new(x, y)
    local o = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = C_BG
    o.borderColor = C_BORDER
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

    self.closeBtn = ISButton:new(PANEL_W - 36, 8, 26, 26, "X", self, KitsUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColorMouseOver = { r = 0.65, g = 0.12, b = 0.12, a = 0.9 }
    self.closeBtn.textColor = { r = 0.65, g = 0.63, b = 0.60, a = 1 }
    self:addChild(self.closeBtn)

    self.adminBtn = ISButton:new(PAD, 10, 60, 22, "ADMIN", self, KitsUI.onToggleAdmin)
    self.adminBtn:initialise()
    self.adminBtn:instantiate()
    self.adminBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminBtn.backgroundColor = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.65 }
    self.adminBtn.backgroundColorMouseOver = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 1 }
    self.adminBtn.textColor = C_TEXT
    self.adminBtn:setVisible(false)
    self:addChild(self.adminBtn)

    self:buildKitsPanel()
    self:buildAdminPanel()
    KitsClient.CheckAdmin()
end

function KitsUI:buildKitsPanel()
    self.kitsPanel = ISPanel:new(0, HEADER_H, PANEL_W, PANEL_H - HEADER_H)
    self.kitsPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.kitsPanel)

    local yOff = CARD_PAD + 2
    for i, kit in ipairs(KitsConfig.Kits) do
        local cardH = self:createKitCard(kit, yOff, i)
        yOff = yOff + cardH + CARD_PAD
    end

    local totalH = HEADER_H + yOff + PAD
    if totalH > PANEL_H then
        self:setHeight(totalH)
        self.kitsPanel:setHeight(totalH - HEADER_H)
    end
end

function KitsUI:createKitCard(kit, yOff, index)
    local cardX = PAD
    local cardW = PANEL_W - PAD * 2

    local itemCount = #kit.items
    local slotsPerRow = math.floor((cardW - 20) / (ICON_SIZE + ICON_GAP))
    local iconRows = math.ceil(itemCount / slotsPerRow)
    local cardH = 46 + iconRows * (ICON_SIZE + ICON_GAP + 2) + 40

    local card = ISPanel:new(cardX, yOff, cardW, cardH)
    card.backgroundColor = C_CARD
    card.borderColor = C_BORDER
    self.kitsPanel:addChild(card)
    self.kitCards[kit.id] = card

    local nameLabel = ISLabel:new(
        14, 8, 22, kit.name,
        C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, C_ACCENT.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    local permText = ""
    if kit.permission and kit.permission ~= "all" then
        permText = kit.permission:upper()
    end
    local infoText = tostring(kit.cooldown) .. "min"
    if permText ~= "" then
        infoText = infoText .. " | " .. permText
    end
    local infoLabel = ISLabel:new(
        14, 28, 14, infoText,
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a,
        UIFont.Small, true
    )
    card:addChild(infoLabel)

    local statusLabel = ISLabel:new(
        cardW - 100, 8, 22, "LISTO",
        C_GREEN.r, C_GREEN.g, C_GREEN.b, C_GREEN.a,
        UIFont.Medium, true
    )
    card:addChild(statusLabel)
    self.kitCooldownLabels[kit.id] = statusLabel

    local itemData = {}
    for _, entry in ipairs(kit.items) do
        table.insert(itemData, {
            tex = getItemTexture(entry.type),
            name = getItemDisplayName(entry.type),
            count = entry.count,
            type = entry.type,
        })
    end
    self.kitItemData[kit.id] = itemData

    local btnW = 120
    local btnH = 28
    local btn = ISButton:new(
        cardW - btnW - 10, cardH - btnH - 8, btnW, btnH,
        "RECLAMAR", self, KitsUI.onClaimKit
    )
    btn:initialise()
    btn:instantiate()
    btn.internal = kit.id
    btn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 1 }
    btn.backgroundColorMouseOver = { r = C_BTN_HI.r, g = C_BTN_HI.g, b = C_BTN_HI.b, a = 1 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    card:addChild(btn)
    self.kitButtons[kit.id] = btn

    return cardH
end

function KitsUI:buildAdminPanel()
    local panelY = HEADER_H
    local panelH = self:getHeight() - HEADER_H
    self.adminPanel = ISPanel:new(0, panelY, PANEL_W, panelH)
    self.adminPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminPanel:setVisible(false)
    self:addChild(self.adminPanel)

    local y = PAD
    local adminTitle = ISLabel:new(PAD, y, 22, "Gestion de Permisos",
        C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, C_ACCENT.a, UIFont.Medium, true)
    self.adminPanel:addChild(adminTitle)
    y = y + 30

    local plLabel = ISLabel:new(PAD, y, 18, "Jugador:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(plLabel)
    self.adminPlayerEntry = ISTextEntryBox:new("", PAD + 70, y - 2, 180, 22)
    self.adminPlayerEntry:initialise()
    self.adminPlayerEntry:instantiate()
    self.adminPanel:addChild(self.adminPlayerEntry)

    local listBtn = ISButton:new(PAD + 260, y - 2, 100, 22, "Ver Online", self, KitsUI.onAdminListPlayers)
    listBtn:initialise()
    listBtn:instantiate()
    listBtn.backgroundColor = C_CARD
    listBtn.borderColor = C_BORDER
    listBtn.textColor = C_TEXT
    self.adminPanel:addChild(listBtn)
    y = y + 32

    local grLabel = ISLabel:new(PAD, y, 18, "Grupo:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(grLabel)
    self.adminGroupEntry = ISTextEntryBox:new("", PAD + 70, y - 2, 180, 22)
    self.adminGroupEntry:initialise()
    self.adminGroupEntry:instantiate()
    self.adminPanel:addChild(self.adminGroupEntry)
    y = y + 36

    local bw = 130
    local bh = 26
    local bg = 8

    local addBtn = ISButton:new(PAD, y, bw, bh, "Dar Grupo", self, KitsUI.onAdminAddGroup)
    addBtn:initialise()
    addBtn:instantiate()
    addBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    addBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    addBtn.textColor = C_TEXT
    self.adminPanel:addChild(addBtn)

    local removeBtn = ISButton:new(PAD + bw + bg, y, bw, bh, "Quitar Grupo", self, KitsUI.onAdminRemoveGroup)
    removeBtn:initialise()
    removeBtn:instantiate()
    removeBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.9 }
    removeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    removeBtn.textColor = C_TEXT
    self.adminPanel:addChild(removeBtn)

    local infoBtn = ISButton:new(PAD + (bw + bg) * 2, y, bw, bh, "Ver Grupos", self, KitsUI.onAdminListGroups)
    infoBtn:initialise()
    infoBtn:instantiate()
    infoBtn.backgroundColor = C_CARD
    infoBtn.borderColor = C_BORDER
    infoBtn.textColor = C_TEXT
    self.adminPanel:addChild(infoBtn)
    y = y + 38

    local refLabel = ISLabel:new(PAD, y, 18, "Grupos disponibles:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
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
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
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
        self.adminBtn.backgroundColor = { r = C_ACCENT.r, g = C_ACCENT.g, b = C_ACCENT.b, a = 0.9 }
    else
        self.adminBtn.backgroundColor = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.65 }
    end
end

function KitsUI:onAdminAddGroup()
    local pn = self.adminPlayerEntry:getText()
    local gr = self.adminGroupEntry:getText()
    if pn == "" or gr == "" then return end
    KitsClient.AdminAddGroup(pn, gr)
end

function KitsUI:onAdminRemoveGroup()
    local pn = self.adminPlayerEntry:getText()
    local gr = self.adminGroupEntry:getText()
    if pn == "" or gr == "" then return end
    KitsClient.AdminRemoveGroup(pn, gr)
end

function KitsUI:onAdminListGroups()
    local pn = self.adminPlayerEntry:getText()
    if pn == "" then return end
    KitsClient.AdminListGroups(pn)
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
            local hasPerm = KitsClient.HasPermission(kit.id)
            if not hasPerm then
                label.name = "BLOQUEADO"
                label:setColor(C_RED_DK.r, C_RED_DK.g, C_RED_DK.b, C_RED_DK.a)
                btn:setEnable(false)
                btn.backgroundColor = { r = C_BTN_OFF.r, g = C_BTN_OFF.g, b = C_BTN_OFF.b, a = 1 }
                btn.textColor = { r = 0.40, g = 0.40, b = 0.42, a = 1 }
                if card then card.backgroundColor = C_CARD_LOCK end
                if nameLabel then nameLabel:setColor(C_ACCENT_DK.r, C_ACCENT_DK.g, C_ACCENT_DK.b, C_ACCENT_DK.a) end
            else
                if card then card.backgroundColor = C_CARD end
                if nameLabel then nameLabel:setColor(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, C_ACCENT.a) end
                local remainMs = KitsClient.Cooldowns[kit.id] or 0
                if remainMs > 0 then
                    local secs = math.ceil(remainMs / 1000)
                    local mins = math.floor(secs / 60)
                    local s = secs % 60
                    label.name = string.format("%02d:%02d", mins, s)
                    label:setColor(C_RED.r, C_RED.g, C_RED.b, C_RED.a)
                    btn:setEnable(false)
                    btn.backgroundColor = { r = C_BTN_OFF.r, g = C_BTN_OFF.g, b = C_BTN_OFF.b, a = 1 }
                    btn.textColor = { r = 0.40, g = 0.40, b = 0.42, a = 1 }
                else
                    label.name = "LISTO"
                    label:setColor(C_GREEN.r, C_GREEN.g, C_GREEN.b, C_GREEN.a)
                    btn:setEnable(true)
                    btn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 1 }
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
    self:drawRect(0, 0, PANEL_W, HEADER_H, 1, C_HEADER.r, C_HEADER.g, C_HEADER.b)
    self:drawRect(0, HEADER_H - 3, PANEL_W, 3, 1, C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
    self:drawRect(0, HEADER_H, PANEL_W, 1, 0.15, 0, 0, 0)
    local title = "KITS"
    local tw = getTextManager():MeasureStringX(UIFont.Medium, title)
    self:drawText(title, (PANEL_W - tw) / 2, 11, C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 1, UIFont.Medium)
end

function KitsUI:render()
    ISPanel.render(self)
    if self.showingAdmin then return end

    for _, kit in ipairs(KitsConfig.Kits) do
        local card = self.kitCards[kit.id]
        local items = self.kitItemData[kit.id]
        if card and items and card:isVisible() then
            local cx = card:getX()
            local cy = card:getY() + HEADER_H

            local sepY = cy + 44
            self:drawRect(cx + 12, sepY, card:getWidth() - 24, 1,
                0.4, C_SEP.r, C_SEP.g, C_SEP.b)

            local slotY = sepY + 6
            local slotX = cx + 10
            local slotsPerRow = math.floor((card:getWidth() - 20) / (ICON_SIZE + ICON_GAP))
            local col = 0
            local row = 0

            for _, item in ipairs(items) do
                local ix = slotX + col * (ICON_SIZE + ICON_GAP)
                local iy = slotY + row * (ICON_SIZE + ICON_GAP + 2)

                self:drawRect(ix, iy, ICON_SIZE, ICON_SIZE,
                    1, C_SLOT.r, C_SLOT.g, C_SLOT.b)
                self:drawRectBorder(ix, iy, ICON_SIZE, ICON_SIZE,
                    C_SLOT_BD.a, C_SLOT_BD.r, C_SLOT_BD.g, C_SLOT_BD.b)

                if item.tex then
                    self:drawTextureScaled(item.tex, ix + 2, iy + 2,
                        ICON_SIZE - 4, ICON_SIZE - 4, 1, 1, 1, 1)
                else
                    local ch = item.name:sub(1, 1)
                    local chw = getTextManager():MeasureStringX(UIFont.Small, ch)
                    self:drawText(ch, ix + (ICON_SIZE - chw) / 2, iy + 12,
                        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, 0.7, UIFont.Small)
                end

                if item.count > 1 then
                    local cs = tostring(item.count)
                    local cw = getTextManager():MeasureStringX(UIFont.Small, cs)
                    local cx2 = ix + ICON_SIZE - cw - 1
                    local cy2 = iy + ICON_SIZE - 13
                    self:drawRect(cx2 - 2, cy2 - 1, cw + 4, 14, 0.80, 0, 0, 0)
                    self:drawText(cs, cx2, cy2,
                        C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 1, UIFont.Small)
                end

                local mx = self:getMouseX()
                local my = self:getMouseY()
                if mx >= ix and mx <= ix + ICON_SIZE and my >= iy and my <= iy + ICON_SIZE then
                    local tt = item.name
                    if item.count > 1 then
                        tt = item.name .. " x" .. tostring(item.count)
                    end
                    local ttw = getTextManager():MeasureStringX(UIFont.Small, tt)
                    local ttx = ix
                    local tty = iy - 20
                    if ttx + ttw + 12 > self:getWidth() then
                        ttx = self:getWidth() - ttw - 14
                    end
                    self:drawRect(ttx - 4, tty - 2, ttw + 8, 18,
                        0.95, 0.08, 0.08, 0.10)
                    self:drawRectBorder(ttx - 4, tty - 2, ttw + 8, 18,
                        0.7, C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
                    self:drawText(tt, ttx, tty,
                        C_TEXT.r, C_TEXT.g, C_TEXT.b, 1, UIFont.Small)
                end

                col = col + 1
                if col >= slotsPerRow then
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
    local ui = KitsUI:new((sw - PANEL_W) / 2, (sh - PANEL_H) / 2)
    ui:initialise()
    ui:addToUIManager()
    ui:setVisible(true)
    KitsUI.instance = ui
    KitsClient.RequestCooldowns()
end
