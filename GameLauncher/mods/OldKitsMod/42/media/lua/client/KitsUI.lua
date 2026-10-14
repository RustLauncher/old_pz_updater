--[[
    KitsUI.lua - Build 42 compatible
    Interfaz grafica estilo Rust para seleccionar kits.
    Incluye panel de administracion para gestionar permisos.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 620
local PANEL_H = 460
local CARD_H = 90
local CARD_PAD = 8
local HEADER_H = 44
local SCROLL_PAD = 12

local COLOR_BG         = { r = 0.08, g = 0.08, b = 0.08, a = 0.94 }
local COLOR_CARD       = { r = 0.14, g = 0.14, b = 0.14, a = 1 }
local COLOR_CARD_LOCK  = { r = 0.10, g = 0.10, b = 0.10, a = 1 }
local COLOR_BORDER     = { r = 0.25, g = 0.25, b = 0.25, a = 1 }
local COLOR_TITLE      = { r = 0.90, g = 0.55, b = 0.10, a = 1 }
local COLOR_TITLE_LOCK = { r = 0.45, g = 0.35, b = 0.20, a = 1 }
local COLOR_TEXT       = { r = 0.85, g = 0.85, b = 0.85, a = 1 }
local COLOR_DIM        = { r = 0.50, g = 0.50, b = 0.50, a = 1 }
local COLOR_READY      = { r = 0.20, g = 0.75, b = 0.20, a = 1 }
local COLOR_COOLDOWN   = { r = 0.85, g = 0.25, b = 0.25, a = 1 }
local COLOR_LOCKED     = { r = 0.60, g = 0.20, b = 0.20, a = 1 }
local COLOR_BTN        = { r = 0.90, g = 0.55, b = 0.10, a = 0.9 }
local COLOR_BTN_DIS    = { r = 0.35, g = 0.35, b = 0.35, a = 0.9 }
local COLOR_ADMIN      = { r = 0.20, g = 0.50, b = 0.85, a = 0.9 }

---------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------
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
    o.showingAdmin = false
    return o
end

---------------------------------------------------------------------
-- Build UI
---------------------------------------------------------------------
function KitsUI:createChildren()
    ISPanel.createChildren(self)

    -- Header title
    self.titleLabel = ISLabel:new(
        PANEL_W / 2 - 30, 12, HEADER_H - 14,
        "KITS", COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b, COLOR_TITLE.a,
        UIFont.Large, true
    )
    self:addChild(self.titleLabel)

    -- Close button
    self.closeBtn = ISButton:new(PANEL_W - 35, 10, 25, 25, "X", self, KitsUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = COLOR_BORDER
    self.closeBtn.backgroundColor = { r = 0.6, g = 0.15, b = 0.15, a = 0.8 }
    self.closeBtn.textColor = COLOR_TEXT
    self:addChild(self.closeBtn)

    -- Admin button (hidden by default, shown if admin)
    self.adminBtn = ISButton:new(10, 10, 70, 25, "ADMIN", self, KitsUI.onToggleAdmin)
    self.adminBtn:initialise()
    self.adminBtn:instantiate()
    self.adminBtn.borderColor = { r = COLOR_ADMIN.r * 0.7, g = COLOR_ADMIN.g * 0.7, b = COLOR_ADMIN.b * 0.7, a = 1 }
    self.adminBtn.backgroundColor = { r = COLOR_ADMIN.r, g = COLOR_ADMIN.g, b = COLOR_ADMIN.b, a = COLOR_ADMIN.a }
    self.adminBtn.textColor = COLOR_TEXT
    self.adminBtn:setVisible(false)
    self:addChild(self.adminBtn)

    -- Separator
    self.headerLine = ISPanel:new(SCROLL_PAD, HEADER_H, PANEL_W - SCROLL_PAD * 2, 1)
    self.headerLine.backgroundColor = COLOR_BORDER
    self:addChild(self.headerLine)

    -- Kits panel
    self:buildKitsPanel()

    -- Admin panel (hidden)
    self:buildAdminPanel()

    -- Check admin status
    KitsClient.CheckAdmin()
end

function KitsUI:buildKitsPanel()
    self.kitsPanel = ISPanel:new(0, HEADER_H + 4, PANEL_W, PANEL_H - HEADER_H - 4)
    self.kitsPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.kitsPanel)

    local yOff = SCROLL_PAD
    for i, kit in ipairs(KitsConfig.Kits) do
        self:createKitCard(kit, yOff, i)
        yOff = yOff + CARD_H + CARD_PAD
    end

    local totalH = HEADER_H + 4 + yOff + SCROLL_PAD
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

    local y = SCROLL_PAD
    local labelC = COLOR_TEXT

    -- Title
    local adminTitle = ISLabel:new(SCROLL_PAD, y, 22, "Gestion de Permisos",
        COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b, COLOR_TITLE.a, UIFont.Medium, true)
    self.adminPanel:addChild(adminTitle)
    y = y + 30

    -- Player name
    local plLabel = ISLabel:new(SCROLL_PAD, y, 18, "Jugador:",
        labelC.r, labelC.g, labelC.b, labelC.a, UIFont.Small, true)
    self.adminPanel:addChild(plLabel)
    self.adminPlayerEntry = ISTextEntryBox:new("", SCROLL_PAD + 70, y - 2, 200, 22)
    self.adminPlayerEntry:initialise()
    self.adminPlayerEntry:instantiate()
    self.adminPanel:addChild(self.adminPlayerEntry)

    -- List online button
    local listBtn = ISButton:new(SCROLL_PAD + 280, y - 2, 110, 22, "Ver Online", self, KitsUI.onAdminListPlayers)
    listBtn:initialise()
    listBtn:instantiate()
    listBtn.backgroundColor = COLOR_CARD
    listBtn.borderColor = COLOR_BORDER
    listBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(listBtn)
    y = y + 32

    -- Group name
    local grLabel = ISLabel:new(SCROLL_PAD, y, 18, "Grupo:",
        labelC.r, labelC.g, labelC.b, labelC.a, UIFont.Small, true)
    self.adminPanel:addChild(grLabel)
    self.adminGroupEntry = ISTextEntryBox:new("", SCROLL_PAD + 70, y - 2, 200, 22)
    self.adminGroupEntry:initialise()
    self.adminGroupEntry:instantiate()
    self.adminPanel:addChild(self.adminGroupEntry)
    y = y + 36

    -- Action buttons
    local btnW = 160
    local btnH = 28
    local btnGap = 10

    local addBtn = ISButton:new(SCROLL_PAD, y, btnW, btnH, "Dar Grupo", self, KitsUI.onAdminAddGroup)
    addBtn:initialise()
    addBtn:instantiate()
    addBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    addBtn.borderColor = COLOR_BORDER
    addBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(addBtn)

    local removeBtn = ISButton:new(SCROLL_PAD + btnW + btnGap, y, btnW, btnH, "Quitar Grupo", self, KitsUI.onAdminRemoveGroup)
    removeBtn:initialise()
    removeBtn:instantiate()
    removeBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.9 }
    removeBtn.borderColor = COLOR_BORDER
    removeBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(removeBtn)

    local infoBtn = ISButton:new(SCROLL_PAD + (btnW + btnGap) * 2, y, btnW, btnH, "Ver Grupos", self, KitsUI.onAdminListGroups)
    infoBtn:initialise()
    infoBtn:instantiate()
    infoBtn.backgroundColor = COLOR_CARD
    infoBtn.borderColor = COLOR_BORDER
    infoBtn.textColor = COLOR_TEXT
    self.adminPanel:addChild(infoBtn)
    y = y + 40

    -- Available groups reference
    local refLabel = ISLabel:new(SCROLL_PAD, y, 18, "Grupos disponibles en config:",
        COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, UIFont.Small, true)
    self.adminPanel:addChild(refLabel)
    y = y + 20

    local groups = {}
    for _, kit in ipairs(KitsConfig.Kits) do
        local p = kit.permission or "all"
        if p ~= "all" and p ~= "admin" then
            local found = false
            for _, g in ipairs(groups) do
                if g == p then found = true break end
            end
            if not found then table.insert(groups, p) end
        end
    end
    local groupsText = #groups > 0 and table.concat(groups, ", ") or "(solo 'all' y 'admin')"
    local groupsListLabel = ISLabel:new(SCROLL_PAD, y, 18, groupsText,
        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, COLOR_TEXT.a, UIFont.Small, true)
    self.adminPanel:addChild(groupsListLabel)
end

---------------------------------------------------------------------
-- Kit cards
---------------------------------------------------------------------
function KitsUI:createKitCard(kit, yOff, index)
    local cardX = SCROLL_PAD
    local cardW = PANEL_W - SCROLL_PAD * 2

    local card = ISPanel:new(cardX, yOff, cardW, CARD_H)
    card.backgroundColor = COLOR_CARD
    card.borderColor = COLOR_BORDER
    self.kitsPanel:addChild(card)
    self.kitCards[kit.id] = card

    -- Kit name
    local nameLabel = ISLabel:new(
        12, 6, 22, kit.name,
        COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b, COLOR_TITLE.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    -- Items list
    local itemsText = self:buildItemsText(kit)
    local itemsLabel = ISLabel:new(
        12, 30, 18, itemsText,
        COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, COLOR_TEXT.a,
        UIFont.Small, true
    )
    card:addChild(itemsLabel)

    -- Permission tag + cooldown
    local permTag = ""
    if kit.permission and kit.permission ~= "all" then
        permTag = " [" .. kit.permission:upper() .. "]"
    end
    local cdText = "Cooldown: " .. kit.cooldown .. " min" .. permTag
    local cdLabel = ISLabel:new(
        12, 52, 18, cdText,
        COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a,
        UIFont.Small, true
    )
    card:addChild(cdLabel)

    -- Status
    local statusLabel = ISLabel:new(
        cardW - 210, 10, 22, "LISTO",
        COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, COLOR_READY.a,
        UIFont.Medium, true
    )
    card:addChild(statusLabel)
    self.kitCooldownLabels[kit.id] = statusLabel

    -- Claim button
    local btnW = 110
    local btnH = 30
    local btn = ISButton:new(
        cardW - btnW - 12, (CARD_H - btnH) / 2 + 8, btnW, btnH,
        "RECLAMAR", self, KitsUI.onClaimKit
    )
    btn:initialise()
    btn:instantiate()
    btn.internal = kit.id
    btn.backgroundColor = { r = COLOR_BTN.r, g = COLOR_BTN.g, b = COLOR_BTN.b, a = COLOR_BTN.a }
    btn.borderColor = { r = COLOR_BTN.r * 0.7, g = COLOR_BTN.g * 0.7, b = COLOR_BTN.b * 0.7, a = 1 }
    btn.textColor = { r = 0, g = 0, b = 0, a = 1 }
    card:addChild(btn)
    self.kitButtons[kit.id] = btn
end

function KitsUI:buildItemsText(kit)
    local parts = {}
    for _, entry in ipairs(kit.items) do
        local name = entry.type:gsub("Base%.", "")
        if entry.count > 1 then
            name = name .. " x" .. entry.count
        end
        table.insert(parts, name)
    end
    local text = table.concat(parts, ", ")
    if #text > 65 then
        text = text:sub(1, 62) .. "..."
    end
    return text
end

---------------------------------------------------------------------
-- Kit actions
---------------------------------------------------------------------
function KitsUI:onClaimKit(button)
    local kitId = button.internal
    if not kitId then return end
    if not KitsClient.HasPermission(kitId) then return end
    KitsClient.RequestKit(kitId)
end

---------------------------------------------------------------------
-- Admin actions
---------------------------------------------------------------------
function KitsUI:onToggleAdmin()
    self.showingAdmin = not self.showingAdmin
    self.kitsPanel:setVisible(not self.showingAdmin)
    self.adminPanel:setVisible(self.showingAdmin)
    if self.showingAdmin then
        self.adminBtn.backgroundColor = { r = COLOR_TITLE.r, g = COLOR_TITLE.g, b = COLOR_TITLE.b, a = 0.9 }
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

---------------------------------------------------------------------
-- Update states
---------------------------------------------------------------------
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
                if nameLabel then nameLabel:setColor(COLOR_TITLE_LOCK.r, COLOR_TITLE_LOCK.g, COLOR_TITLE_LOCK.b, COLOR_TITLE_LOCK.a) end
            else
                if card then card.backgroundColor = COLOR_CARD end
                if nameLabel then nameLabel:setColor(COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b, COLOR_TITLE.a) end
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
end

function KitsUI:render()
    ISPanel.render(self)
end

---------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------
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
