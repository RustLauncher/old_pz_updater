require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 440
local PANEL_H = 500
local HEADER_H = 36
local PAD = 10
local CARD_GAP = 6
local ICON_SIZE = 32
local ICON_GAP = 4
local ACCENT_BAR_W = 3
local BTN_W = 100
local BTN_H = 24

local C_BG        = { r = 0.06, g = 0.06, b = 0.08, a = 0.98 }
local C_HEADER    = { r = 0.08, g = 0.08, b = 0.10, a = 1 }
local C_CARD      = { r = 0.10, g = 0.10, b = 0.13, a = 1 }
local C_CARD_LOCK = { r = 0.08, g = 0.08, b = 0.10, a = 0.8 }
local C_BORDER    = { r = 0.18, g = 0.17, b = 0.20, a = 0.5 }
local C_TEXT      = { r = 0.92, g = 0.90, b = 0.88, a = 1 }
local C_TEXT2     = { r = 0.50, g = 0.48, b = 0.46, a = 1 }
local C_GREEN     = { r = 0.25, g = 0.85, b = 0.45, a = 1 }
local C_GREEN_BG  = { r = 0.10, g = 0.22, b = 0.12, a = 0.9 }
local C_RED       = { r = 0.95, g = 0.30, b = 0.25, a = 1 }
local C_RED_BG    = { r = 0.25, g = 0.08, b = 0.08, a = 0.9 }
local C_RED_DK    = { r = 0.50, g = 0.20, b = 0.18, a = 1 }
local C_LOCK_BG   = { r = 0.18, g = 0.10, b = 0.10, a = 0.9 }
local C_BTN       = { r = 0.90, g = 0.55, b = 0.10, a = 1 }
local C_BTN_HI    = { r = 1.00, g = 0.68, b = 0.18, a = 1 }
local C_BTN_OFF   = { r = 0.16, g = 0.16, b = 0.18, a = 1 }
local C_SLOT      = { r = 0.14, g = 0.14, b = 0.17, a = 1 }
local C_SLOT_BD   = { r = 0.22, g = 0.21, b = 0.24, a = 0.3 }
local C_ADMIN     = { r = 0.30, g = 0.55, b = 0.90, a = 0.85 }
local C_COUNT_BG  = { r = 0.90, g = 0.55, b = 0.10, a = 0.95 }

local KIT_COLORS = {
    basic       = { r = 0.95, g = 0.58, b = 0.08, a = 1 },
    medico      = { r = 0.20, g = 0.75, b = 0.40, a = 1 },
    combate     = { r = 0.90, g = 0.25, b = 0.20, a = 1 },
    ropa        = { r = 0.60, g = 0.45, b = 0.75, a = 1 },
    armas       = { r = 0.85, g = 0.20, b = 0.15, a = 1 },
    equipo      = { r = 0.30, g = 0.55, b = 0.90, a = 1 },
    generador   = { r = 0.80, g = 0.70, b = 0.15, a = 1 },
}

local function kitColor(kitId)
    return KIT_COLORS[kitId] or KIT_COLORS.basic
end

local function formatCooldown(minutes)
    if minutes >= 1440 then
        local days = math.floor(minutes / 1440)
        local rem = minutes % 1440
        if rem > 0 then
            return tostring(days) .. "d " .. tostring(math.floor(rem / 60)) .. "h"
        end
        return tostring(days) .. "d"
    end
    if minutes >= 60 then
        local h = math.floor(minutes / 60)
        local m = minutes % 60
        if m > 0 then
            return tostring(h) .. "h " .. tostring(m) .. "m"
        end
        return tostring(h) .. "h"
    end
    return tostring(minutes) .. "m"
end

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
    o.borderColor = { r = 0.10, g = 0.10, b = 0.12, a = 0.8 }
    o.moveWithMouse = true
    o.kitButtons = {}
    o.kitCards = {}
    o.kitNameLabels = {}
    o.kitItemData = {}
    o.kitStatus = {}
    o.showingAdmin = false
    return o
end

function KitsUI:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(PANEL_W - 32, 6, 24, 24, "X", self, KitsUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.closeBtn.backgroundColorMouseOver = { r = 0.70, g = 0.15, b = 0.15, a = 0.9 }
    self.closeBtn.textColor = { r = 0.55, g = 0.53, b = 0.50, a = 1 }
    self:addChild(self.closeBtn)

    self.adminBtn = ISButton:new(PAD, 8, 55, 20, "ADMIN", self, KitsUI.onToggleAdmin)
    self.adminBtn:initialise()
    self.adminBtn:instantiate()
    self.adminBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminBtn.backgroundColor = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.55 }
    self.adminBtn.backgroundColorMouseOver = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.9 }
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

    local yOff = 4
    for i, kit in ipairs(KitsConfig.Kits) do
        local cardH = self:createKitCard(kit, yOff, i)
        yOff = yOff + cardH + CARD_GAP
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
    local contentW = cardW - ACCENT_BAR_W

    local itemCount = #kit.items
    local itemAreaW = contentW - 20
    local slotsPerRow = math.floor(itemAreaW / (ICON_SIZE + ICON_GAP))
    if slotsPerRow < 1 then slotsPerRow = 1 end
    local iconRows = math.ceil(itemCount / slotsPerRow)

    local titleRow = 38
    local itemSection = iconRows * (ICON_SIZE + ICON_GAP) + 2
    local btnRow = BTN_H + 8
    local cardH = titleRow + itemSection + btnRow

    local card = ISPanel:new(cardX, yOff, cardW, cardH)
    card.backgroundColor = C_CARD
    card.borderColor = C_BORDER
    self.kitsPanel:addChild(card)
    self.kitCards[kit.id] = card

    self.kitStatus[kit.id] = { text = "LISTO", state = "ready" }

    local permText = ""
    if kit.permission and kit.permission ~= "all" then
        permText = kit.permission:upper()
    end
    local subText = formatCooldown(kit.cooldown)
    if permText ~= "" then
        subText = subText .. " | " .. permText
    end

    local nameLabel = ISLabel:new(
        ACCENT_BAR_W + 10, 5, 18, kit.name,
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    local subLabel = ISLabel:new(
        ACCENT_BAR_W + 10, 20, 12, subText,
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a,
        UIFont.Small, true
    )
    card:addChild(subLabel)

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

    local btn = ISButton:new(
        cardW - BTN_W - 8, cardH - BTN_H - 5, BTN_W, BTN_H,
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
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Medium, true)
    self.adminPanel:addChild(adminTitle)
    y = y + 28

    local plLabel = ISLabel:new(PAD, y, 18, "Jugador:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(plLabel)
    self.adminPlayerEntry = ISTextEntryBox:new("", PAD + 65, y - 2, 170, 20)
    self.adminPlayerEntry:initialise()
    self.adminPlayerEntry:instantiate()
    self.adminPanel:addChild(self.adminPlayerEntry)

    local listBtn = ISButton:new(PAD + 245, y - 2, 90, 20, "Ver Online", self, KitsUI.onAdminListPlayers)
    listBtn:initialise()
    listBtn:instantiate()
    listBtn.backgroundColor = C_CARD
    listBtn.borderColor = C_BORDER
    listBtn.textColor = C_TEXT
    self.adminPanel:addChild(listBtn)
    y = y + 28

    local grLabel = ISLabel:new(PAD, y, 18, "Grupo:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(grLabel)
    self.adminGroupEntry = ISTextEntryBox:new("", PAD + 65, y - 2, 170, 20)
    self.adminGroupEntry:initialise()
    self.adminGroupEntry:instantiate()
    self.adminPanel:addChild(self.adminGroupEntry)
    y = y + 32

    local bw = 110
    local bh = 24
    local bg = 6

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
    y = y + 34

    local refLabel = ISLabel:new(PAD, y, 18, "Grupos disponibles:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.adminPanel:addChild(refLabel)
    y = y + 18

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
        self.adminBtn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 0.9 }
    else
        self.adminBtn.backgroundColor = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.55 }
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
        local st = self.kitStatus[kit.id]
        local btn = self.kitButtons[kit.id]
        local card = self.kitCards[kit.id]
        local nameLabel = self.kitNameLabels[kit.id]
        if st and btn then
            local hasPerm = KitsClient.HasPermission(kit.id)
            if not hasPerm then
                st.text = "BLOQUEADO"
                st.state = "locked"
                btn:setEnable(false)
                btn.backgroundColor = { r = C_BTN_OFF.r, g = C_BTN_OFF.g, b = C_BTN_OFF.b, a = 1 }
                btn.textColor = { r = 0.35, g = 0.35, b = 0.37, a = 1 }
                if card then card.backgroundColor = C_CARD_LOCK end
                if nameLabel then nameLabel:setColor(C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a) end
            else
                if card then card.backgroundColor = C_CARD end
                if nameLabel then nameLabel:setColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a) end
                local remainMs = KitsClient.Cooldowns[kit.id] or 0
                if remainMs > 0 then
                    local secs = math.ceil(remainMs / 1000)
                    local mins = math.floor(secs / 60)
                    local s = secs % 60
                    if mins >= 60 then
                        local h = math.floor(mins / 60)
                        local m = mins % 60
                        st.text = string.format("%dh %02dm", h, m)
                    else
                        st.text = string.format("%02d:%02d", mins, s)
                    end
                    st.state = "cooldown"
                    btn:setEnable(false)
                    btn.backgroundColor = { r = C_BTN_OFF.r, g = C_BTN_OFF.g, b = C_BTN_OFF.b, a = 1 }
                    btn.textColor = { r = 0.35, g = 0.35, b = 0.37, a = 1 }
                else
                    st.text = "LISTO"
                    st.state = "ready"
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
    local title = "KITS"
    local tw = getTextManager():MeasureStringX(UIFont.Medium, title)
    self:drawText(title, (PANEL_W - tw) / 2, 9,
        C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.9, UIFont.Medium)
end

function KitsUI:render()
    ISPanel.render(self)
    if self.showingAdmin then return end

    for _, kit in ipairs(KitsConfig.Kits) do
        local card = self.kitCards[kit.id]
        local items = self.kitItemData[kit.id]
        local st = self.kitStatus[kit.id]
        if card and items and card:isVisible() then
            local cx = card:getX()
            local cy = card:getY() + HEADER_H
            local cw = card:getWidth()
            local ch = card:getHeight()
            local kc = kitColor(kit.id)

            self:drawRect(cx, cy, ACCENT_BAR_W, ch, 1, kc.r, kc.g, kc.b)

            if st then
                local stText = st.text or "LISTO"
                local stw = getTextManager():MeasureStringX(UIFont.Small, stText)
                local pillPad = 8
                local pillW = stw + pillPad * 2
                local pillH = 18
                local pillX = cx + cw - pillW - 8
                local pillY = cy + 7

                local bgColor = C_GREEN_BG
                local txColor = C_GREEN
                if st.state == "locked" then
                    bgColor = C_LOCK_BG
                    txColor = C_RED_DK
                elseif st.state == "cooldown" then
                    bgColor = C_RED_BG
                    txColor = C_RED
                end

                self:drawRect(pillX, pillY, pillW, pillH, bgColor.a,
                    bgColor.r, bgColor.g, bgColor.b)
                self:drawText(stText, pillX + pillPad, pillY + 2,
                    txColor.r, txColor.g, txColor.b, txColor.a, UIFont.Small)
            end

            local sepY2 = cy + 37
            self:drawRect(cx + ACCENT_BAR_W + 8, sepY2, cw - ACCENT_BAR_W - 16, 1,
                0.12, kc.r, kc.g, kc.b)

            local itemAreaW = cw - ACCENT_BAR_W - 16
            local slotsPerRow = math.floor(itemAreaW / (ICON_SIZE + ICON_GAP))
            if slotsPerRow < 1 then slotsPerRow = 1 end

            local totalSlotsW = #items * (ICON_SIZE + ICON_GAP) - ICON_GAP
            if totalSlotsW > itemAreaW then
                totalSlotsW = slotsPerRow * (ICON_SIZE + ICON_GAP) - ICON_GAP
            end
            local startX = cx + ACCENT_BAR_W + 8
            local slotY = cy + 40
            local col = 0
            local row = 0

            for _, item in ipairs(items) do
                local ix = startX + col * (ICON_SIZE + ICON_GAP)
                local iy = slotY + row * (ICON_SIZE + ICON_GAP)

                self:drawRect(ix, iy, ICON_SIZE, ICON_SIZE,
                    1, C_SLOT.r, C_SLOT.g, C_SLOT.b)
                self:drawRectBorder(ix, iy, ICON_SIZE, ICON_SIZE,
                    C_SLOT_BD.a, C_SLOT_BD.r, C_SLOT_BD.g, C_SLOT_BD.b)

                if item.tex then
                    self:drawTextureScaled(item.tex, ix + 2, iy + 2,
                        ICON_SIZE - 4, ICON_SIZE - 4, 1, 1, 1, 1)
                else
                    local letter = item.name:sub(1, 1)
                    local lw = getTextManager():MeasureStringX(UIFont.Small, letter)
                    self:drawText(letter, ix + (ICON_SIZE - lw) / 2, iy + 8,
                        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, 0.6, UIFont.Small)
                end

                if item.count > 1 then
                    local cs = tostring(item.count)
                    local csw = getTextManager():MeasureStringX(UIFont.Small, cs)
                    local badgeW = csw + 4
                    local badgeX = ix + ICON_SIZE - badgeW
                    local badgeY = iy + ICON_SIZE - 12
                    self:drawRect(badgeX, badgeY, badgeW, 12, 0.92,
                        C_COUNT_BG.r, C_COUNT_BG.g, C_COUNT_BG.b)
                    self:drawText(cs, badgeX + 2, badgeY,
                        1, 1, 1, 1, UIFont.Small)
                end

                local mx = self:getMouseX()
                local my = self:getMouseY()
                if mx >= ix and mx <= ix + ICON_SIZE and my >= iy and my <= iy + ICON_SIZE then
                    self:drawRectBorder(ix - 1, iy - 1, ICON_SIZE + 2, ICON_SIZE + 2,
                        0.7, kc.r, kc.g, kc.b)

                    local tt = item.name
                    if item.count > 1 then
                        tt = item.name .. " x" .. tostring(item.count)
                    end
                    local ttw = getTextManager():MeasureStringX(UIFont.Small, tt)
                    local ttx = ix
                    local tty = iy - 18
                    if ttx + ttw + 10 > self:getWidth() then
                        ttx = self:getWidth() - ttw - 12
                    end
                    self:drawRect(ttx - 4, tty - 2, ttw + 8, 18,
                        0.95, 0.06, 0.06, 0.08)
                    self:drawRectBorder(ttx - 4, tty - 2, ttw + 8, 18,
                        0.4, kc.r, kc.g, kc.b)
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
