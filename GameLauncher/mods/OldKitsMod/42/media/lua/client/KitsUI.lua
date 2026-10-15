require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "KitsConfig"
require "KitsClient"

KitsUI = ISPanel:derive("KitsUI")
KitsUI.instance = nil

local PANEL_W = 460
local PANEL_H = 500
local HEADER_H = 36
local PAD = 10
local CARD_GAP = 6
local ICON_SIZE = 32
local ICON_GAP = 4
local ACCENT_BAR_W = 3
local BTN_W = 100
local BTN_H = 24
local EDIT_ITEM_H = 26
local EDIT_ICON = 22

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
local ROLE_BAR_H  = 22

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

local function getRoleColor(roleName)
    local colors = KitsClient.RoleColors or {}
    local c = colors[roleName:lower()]
    if c then return c end
    return C_TEXT2
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
    o.adminActiveTab = "roles"
    o.editingKitId = nil
    o.editKitItems = {}
    o.editItemWidgets = {}
    o.editItemDisplayData = {}
    o.kitSelectorBtns = {}
    o.editPermission = "all"
    o.itemSearchCache = nil
    o.lastSearchText = ""
    o.lastPlayerSearchText = ""
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

    local yOff = 4 + ROLE_BAR_H + 2
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

function KitsUI:updateRoleBar()
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

    local titleRow = 44
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
        ACCENT_BAR_W + 10, 3, 18, kit.name,
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a,
        UIFont.Medium, true
    )
    card:addChild(nameLabel)
    self.kitNameLabels[kit.id] = nameLabel

    local subLabel = ISLabel:new(
        ACCENT_BAR_W + 10, 25, 12, subText,
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

    local tabW = 65
    local tabY = 4
    self.adminTabRolesBtn = ISButton:new(PAD, tabY, tabW, 20, "ROLES", self, KitsUI.onAdminTabRoles)
    self.adminTabRolesBtn:initialise()
    self.adminTabRolesBtn:instantiate()
    self.adminTabRolesBtn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 0.9 }
    self.adminTabRolesBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminTabRolesBtn.textColor = C_TEXT
    self.adminPanel:addChild(self.adminTabRolesBtn)

    self.adminTabKitsBtn = ISButton:new(PAD + tabW + 4, tabY, tabW, 20, "KITS", self, KitsUI.onAdminTabKits)
    self.adminTabKitsBtn:initialise()
    self.adminTabKitsBtn:instantiate()
    self.adminTabKitsBtn.backgroundColor = C_CARD
    self.adminTabKitsBtn.borderColor = C_BORDER
    self.adminTabKitsBtn.textColor = C_TEXT
    self.adminPanel:addChild(self.adminTabKitsBtn)

    self.adminActiveTab = "roles"
    self:buildRolesSubPanel()
    self:buildKitEditorPanel()
end

function KitsUI:buildRolesSubPanel()
    local subY = 30
    self.rolesSubPanel = ISPanel:new(0, subY, PANEL_W, self.adminPanel:getHeight() - subY)
    self.rolesSubPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminPanel:addChild(self.rolesSubPanel)

    local y = PAD
    local adminTitle = ISLabel:new(PAD, y, 22, "Roles Temporales",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Medium, true)
    self.rolesSubPanel:addChild(adminTitle)
    y = y + 30

    local searchLabel = ISLabel:new(PAD, y + 2, 16, "Buscar jugador:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.rolesSubPanel:addChild(searchLabel)
    y = y + 18

    self.playerSearchEntry = ISTextEntryBox:new("", PAD, y, PANEL_W - PAD * 2, 22)
    self.playerSearchEntry:initialise()
    self.playerSearchEntry:instantiate()
    self.rolesSubPanel:addChild(self.playerSearchEntry)
    y = y + 26

    self.playerListBox = ISScrollingListBox:new(PAD, y, PANEL_W - PAD * 2, 120)
    self.playerListBox:initialise()
    self.playerListBox:instantiate()
    self.playerListBox.itemheight = 24
    self.playerListBox.font = UIFont.Small
    self.playerListBox.backgroundColor = { r = 0.08, g = 0.08, b = 0.10, a = 1 }
    self.playerListBox.borderColor = C_BORDER
    self.playerListBox.drawBorder = true
    self.playerListBox.doDrawItem = self.doDrawPlayerItem
    self.rolesSubPanel:addChild(self.playerListBox)
    y = y + 126

    local rolLabel = ISLabel:new(PAD, y + 2, 18, "Rol:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.rolesSubPanel:addChild(rolLabel)

    local rolBtnW = 90
    local rolBtnGap = 4
    local rolX = PAD + 40
    self.adminSelectedRole = "vip"

    self.roleBtnVip = ISButton:new(rolX, y, rolBtnW, 22, "VIP", self, KitsUI.onSelectRoleVip)
    self.roleBtnVip:initialise()
    self.roleBtnVip:instantiate()
    self.roleBtnVip.backgroundColor = { r = 0.20, g = 0.55, b = 0.20, a = 0.9 }
    self.roleBtnVip.borderColor = { r = 0.40, g = 0.80, b = 0.40, a = 0.8 }
    self.roleBtnVip.textColor = C_TEXT
    self.rolesSubPanel:addChild(self.roleBtnVip)

    self.roleBtnUlt = ISButton:new(rolX + rolBtnW + rolBtnGap, y, rolBtnW, 22, "ULTIMATE", self, KitsUI.onSelectRoleUlt)
    self.roleBtnUlt:initialise()
    self.roleBtnUlt:instantiate()
    self.roleBtnUlt.backgroundColor = C_CARD
    self.roleBtnUlt.borderColor = C_BORDER
    self.roleBtnUlt.textColor = C_TEXT
    self.rolesSubPanel:addChild(self.roleBtnUlt)
    y = y + 28

    local dayLabel = ISLabel:new(PAD, y + 2, 18, "Dias:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.rolesSubPanel:addChild(dayLabel)
    self.adminDaysEntry = ISTextEntryBox:new("30", PAD + 40, y, 60, 22)
    self.adminDaysEntry:initialise()
    self.adminDaysEntry:instantiate()
    self.rolesSubPanel:addChild(self.adminDaysEntry)
    y = y + 32

    local bw = 120
    local bg = 8
    local giveBtn = ISButton:new(PAD, y, bw, BTN_H, "DAR ROL", self, KitsUI.onAdminGiveRole)
    giveBtn:initialise()
    giveBtn:instantiate()
    giveBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    giveBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    giveBtn.textColor = C_TEXT
    self.rolesSubPanel:addChild(giveBtn)

    local removeBtn = ISButton:new(PAD + bw + bg, y, bw, BTN_H, "QUITAR ROL", self, KitsUI.onAdminRemoveRole)
    removeBtn:initialise()
    removeBtn:instantiate()
    removeBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.9 }
    removeBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    removeBtn.textColor = C_TEXT
    self.rolesSubPanel:addChild(removeBtn)
    y = y + 36

    self:drawHSeparator(self.rolesSubPanel, y)
    y = y + 8

    local listTitle = ISLabel:new(PAD, y, 18, "Roles activos:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.rolesSubPanel:addChild(listTitle)
    y = y + 22

    self.tempRolesListY = y
    self.tempRolesLabels = {}
end

function KitsUI:drawHSeparator(panel, y)
    local sep = ISPanel:new(PAD, y, PANEL_W - PAD * 2, 1)
    sep.backgroundColor = { r = C_BORDER.r, g = C_BORDER.g, b = C_BORDER.b, a = 0.3 }
    sep.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    panel:addChild(sep)
end

function KitsUI.doDrawPlayerItem(self2, y, item, alt)
    if self2.selected == item.index then
        self2:drawRect(0, y, self2:getWidth(), self2.itemheight, 0.4, C_BTN.r, C_BTN.g, C_BTN.b)
    elseif alt then
        self2:drawRect(0, y, self2:getWidth(), self2.itemheight, 0.05, 1, 1, 1)
    end
    local data = item.item
    if data and data.online then
        self2:drawRect(6, y + 8, 8, 8, 1, C_GREEN.r, C_GREEN.g, C_GREEN.b)
    else
        self2:drawRect(6, y + 8, 8, 8, 0.4, C_RED_DK.r, C_RED_DK.g, C_RED_DK.b)
    end
    self2:drawText(item.text, 20, y + 4, C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small)
    return y + self2.itemheight
end

function KitsUI.doDrawSearchItem(self2, y, item, alt)
    if self2.selected == item.index then
        self2:drawRect(0, y, self2:getWidth(), self2.itemheight, 0.4, C_BTN.r, C_BTN.g, C_BTN.b)
    elseif alt then
        self2:drawRect(0, y, self2:getWidth(), self2.itemheight, 0.05, 1, 1, 1)
    end
    local data = item.item
    local textX = 8
    if data and data.tex then
        self2:drawTextureScaled(data.tex, 4, y + 2, 20, 20, 1, 1, 1, 1)
        textX = 28
    end
    self2:drawText(item.text, textX, y + 4, C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small)
    return y + self2.itemheight
end

function KitsUI:buildKitEditorPanel()
    local subY = 30
    self.kitsEditorPanel = ISPanel:new(0, subY, PANEL_W, self.adminPanel:getHeight() - subY)
    self.kitsEditorPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.kitsEditorPanel:setVisible(false)
    self.adminPanel:addChild(self.kitsEditorPanel)

    local y = 4
    local selBtnW = 90
    local selBtnGap = 2
    local bx = PAD
    self.kitSelectorBtns = {}
    local kitsPerRow = 4
    for i, kit in ipairs(KitsConfig.Kits) do
        if i == kitsPerRow + 1 then
            y = y + 24
            bx = PAD
        end
        local label = kit.id:upper()
        local btn = ISButton:new(bx, y, selBtnW, 22, label, self, KitsUI.onSelectKitForEdit)
        btn:initialise()
        btn:instantiate()
        btn.internal = kit.id
        btn.backgroundColor = C_CARD
        btn.borderColor = C_BORDER
        btn.textColor = C_TEXT
        self.kitsEditorPanel:addChild(btn)
        self.kitSelectorBtns[kit.id] = btn
        bx = bx + selBtnW + selBtnGap
    end
    y = y + 30

    local lblW = 75
    local entryW = PANEL_W - PAD * 2 - lblW - 6

    local nameLabel = ISLabel:new(PAD, y + 3, 18, "Nombre:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.kitsEditorPanel:addChild(nameLabel)
    self.editNameEntry = ISTextEntryBox:new("", PAD + lblW, y, entryW, 22)
    self.editNameEntry:initialise()
    self.editNameEntry:instantiate()
    self.kitsEditorPanel:addChild(self.editNameEntry)
    y = y + 28

    local cdLabel = ISLabel:new(PAD, y + 3, 18, "CD(min):",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.kitsEditorPanel:addChild(cdLabel)
    self.editCooldownEntry = ISTextEntryBox:new("", PAD + lblW, y, 70, 22)
    self.editCooldownEntry:initialise()
    self.editCooldownEntry:instantiate()
    self.kitsEditorPanel:addChild(self.editCooldownEntry)

    local permX = PAD + lblW + 80
    local permBtnW = 55
    local permGap = 3

    self.editPermBtns = {}

    local permAll = ISButton:new(permX, y, permBtnW, 22, "ALL", self, KitsUI.onEditPermAll)
    permAll:initialise()
    permAll:instantiate()
    permAll.backgroundColor = C_CARD
    permAll.borderColor = C_BORDER
    permAll.textColor = C_TEXT
    self.kitsEditorPanel:addChild(permAll)
    self.editPermBtns["all"] = permAll

    local permVip = ISButton:new(permX + permBtnW + permGap, y, permBtnW, 22, "VIP", self, KitsUI.onEditPermVip)
    permVip:initialise()
    permVip:instantiate()
    permVip.backgroundColor = C_CARD
    permVip.borderColor = C_BORDER
    permVip.textColor = C_TEXT
    self.kitsEditorPanel:addChild(permVip)
    self.editPermBtns["vip"] = permVip

    local permUlt = ISButton:new(permX + (permBtnW + permGap) * 2, y, 65, 22, "ULTIM.", self, KitsUI.onEditPermUlt)
    permUlt:initialise()
    permUlt:instantiate()
    permUlt.backgroundColor = C_CARD
    permUlt.borderColor = C_BORDER
    permUlt.textColor = C_TEXT
    self.kitsEditorPanel:addChild(permUlt)
    self.editPermBtns["ultimate"] = permUlt

    y = y + 32

    local itemsTitle = ISLabel:new(PAD, y, 18, "Items del kit:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.kitsEditorPanel:addChild(itemsTitle)
    y = y + 22

    self.editItemsStartY = y
    self.editItemsAreaH = 190

    local searchY = y + self.editItemsAreaH + 4

    self:drawHSeparator(self.kitsEditorPanel, searchY - 6)

    local searchTitle = ISLabel:new(PAD, searchY, 18, "Buscar item:",
        C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small, true)
    self.kitsEditorPanel:addChild(searchTitle)
    searchY = searchY + 20

    self.itemSearchEntry = ISTextEntryBox:new("", PAD, searchY, PANEL_W - PAD * 2, 22)
    self.itemSearchEntry:initialise()
    self.itemSearchEntry:instantiate()
    self.kitsEditorPanel:addChild(self.itemSearchEntry)
    searchY = searchY + 26

    self.itemSearchList = ISScrollingListBox:new(PAD, searchY, PANEL_W - PAD * 2, 110)
    self.itemSearchList:initialise()
    self.itemSearchList:instantiate()
    self.itemSearchList.itemheight = 24
    self.itemSearchList.font = UIFont.Small
    self.itemSearchList.backgroundColor = { r = 0.08, g = 0.08, b = 0.10, a = 1 }
    self.itemSearchList.borderColor = C_BORDER
    self.itemSearchList.drawBorder = true
    self.itemSearchList.doDrawItem = self.doDrawSearchItem
    self.kitsEditorPanel:addChild(self.itemSearchList)
    searchY = searchY + 116

    local cntLabel = ISLabel:new(PAD, searchY + 3, 18, "Cantidad:",
        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
    self.kitsEditorPanel:addChild(cntLabel)

    self.editNewItemCount = ISTextEntryBox:new("1", PAD + 72, searchY, 50, 22)
    self.editNewItemCount:initialise()
    self.editNewItemCount:instantiate()
    self.kitsEditorPanel:addChild(self.editNewItemCount)

    self.editAddItemBtn = ISButton:new(PAD + 130, searchY, 100, 22, "AGREGAR", self, KitsUI.onAddEditItem)
    self.editAddItemBtn:initialise()
    self.editAddItemBtn:instantiate()
    self.editAddItemBtn.backgroundColor = { r = 0.15, g = 0.55, b = 0.15, a = 0.9 }
    self.editAddItemBtn.backgroundColorMouseOver = { r = 0.20, g = 0.65, b = 0.20, a = 1 }
    self.editAddItemBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.editAddItemBtn.textColor = C_TEXT
    self.kitsEditorPanel:addChild(self.editAddItemBtn)
    searchY = searchY + 32

    self.editSaveBtn = ISButton:new(PAD, searchY, 140, BTN_H, "GUARDAR", self, KitsUI.onSaveEditKit)
    self.editSaveBtn:initialise()
    self.editSaveBtn:instantiate()
    self.editSaveBtn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 1 }
    self.editSaveBtn.backgroundColorMouseOver = { r = C_BTN_HI.r, g = C_BTN_HI.g, b = C_BTN_HI.b, a = 1 }
    self.editSaveBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.editSaveBtn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    self.kitsEditorPanel:addChild(self.editSaveBtn)
end

function KitsUI:onAdminTabRoles()
    self.adminActiveTab = "roles"
    self.rolesSubPanel:setVisible(true)
    self.kitsEditorPanel:setVisible(false)
    self.adminTabRolesBtn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 0.9 }
    self.adminTabRolesBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminTabKitsBtn.backgroundColor = C_CARD
    self.adminTabKitsBtn.borderColor = C_BORDER
    KitsClient.AdminListTempRoles()
    KitsClient.AdminListAllPlayers()
end

function KitsUI:onAdminTabKits()
    self.adminActiveTab = "kits"
    self.rolesSubPanel:setVisible(false)
    self.kitsEditorPanel:setVisible(true)
    self.adminTabKitsBtn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 0.9 }
    self.adminTabKitsBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.adminTabRolesBtn.backgroundColor = C_CARD
    self.adminTabRolesBtn.borderColor = C_BORDER
    KitsClient.AdminGetKits()
end

function KitsUI:onSelectKitForEdit(button)
    local kitId = button.internal
    self:loadKitIntoEditor(kitId)
end

function KitsUI:loadKitIntoEditor(kitId)
    self.editingKitId = kitId
    local kit = KitsConfig.GetKitById(kitId)
    if not kit then return end

    for id, btn in pairs(self.kitSelectorBtns) do
        if id == kitId then
            btn.backgroundColor = { r = C_BTN.r, g = C_BTN.g, b = C_BTN.b, a = 0.9 }
            btn.borderColor = { r = C_BTN_HI.r, g = C_BTN_HI.g, b = C_BTN_HI.b, a = 0.8 }
        else
            btn.backgroundColor = C_CARD
            btn.borderColor = C_BORDER
        end
    end

    self.editNameEntry:setText(kit.name)
    self.editCooldownEntry:setText(tostring(kit.cooldown))

    self.editPermission = kit.permission or "all"
    self:updateEditPermButtons()

    self.editKitItems = {}
    for _, item in ipairs(kit.items) do
        table.insert(self.editKitItems, { type = item.type, count = item.count })
    end

    self:rebuildEditItemsList()
end

function KitsUI:updateEditPermButtons()
    for perm, btn in pairs(self.editPermBtns) do
        if perm == self.editPermission then
            btn.backgroundColor = { r = 0.20, g = 0.55, b = 0.20, a = 0.9 }
            btn.borderColor = { r = 0.40, g = 0.80, b = 0.40, a = 0.8 }
        else
            btn.backgroundColor = C_CARD
            btn.borderColor = C_BORDER
        end
    end
end

function KitsUI:onEditPermAll()
    self.editPermission = "all"
    self:updateEditPermButtons()
end

function KitsUI:onEditPermVip()
    self.editPermission = "vip"
    self:updateEditPermButtons()
end

function KitsUI:onEditPermUlt()
    self.editPermission = "ultimate"
    self:updateEditPermButtons()
end

function KitsUI:rebuildEditItemsList()
    for _, w in ipairs(self.editItemWidgets) do
        self.kitsEditorPanel:removeChild(w)
    end
    self.editItemWidgets = {}
    self.editItemDisplayData = {}

    local y = self.editItemsStartY
    for idx, item in ipairs(self.editKitItems) do
        table.insert(self.editItemDisplayData, {
            tex = getItemTexture(item.type),
            name = getItemDisplayName(item.type),
            count = item.count,
            type = item.type,
        })

        local xBtn = ISButton:new(PANEL_W - 50, y + 3, 30, 20, "X", self, KitsUI.onRemoveEditItem)
        xBtn:initialise()
        xBtn:instantiate()
        xBtn.internal = idx
        xBtn.backgroundColor = { r = 0.55, g = 0.15, b = 0.15, a = 0.6 }
        xBtn.backgroundColorMouseOver = { r = 0.75, g = 0.20, b = 0.20, a = 0.9 }
        xBtn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        xBtn.textColor = C_TEXT
        self.kitsEditorPanel:addChild(xBtn)
        table.insert(self.editItemWidgets, xBtn)

        y = y + EDIT_ITEM_H
    end
end

function KitsUI:onAddEditItem()
    if not self.itemSearchList then return end
    local sel = self.itemSearchList.selected
    if not sel or sel < 1 or sel > #self.itemSearchList.items then return end
    local selectedItem = self.itemSearchList.items[sel].item
    if not selectedItem then return end
    local count = tonumber(self.editNewItemCount:getText())
    if not count or count < 1 then count = 1 end
    table.insert(self.editKitItems, { type = selectedItem.type, count = count })
    self.editNewItemCount:setText("1")
    self.itemSearchEntry:setText("")
    self.lastSearchText = ""
    self.itemSearchList:clear()
    self:rebuildEditItemsList()
end

function KitsUI:onRemoveEditItem(button)
    local idx = button.internal
    if not idx or not self.editKitItems[idx] then return end
    table.remove(self.editKitItems, idx)
    self:rebuildEditItemsList()
end

function KitsUI:onSaveEditKit()
    if not self.editingKitId then return end
    local name = self.editNameEntry:getText()
    local cooldown = tonumber(self.editCooldownEntry:getText())
    if not name or name == "" or not cooldown or cooldown < 1 then return end
    local itemsStr = KitsConfig.SerializeItems(self.editKitItems)
    KitsClient.AdminSaveKit(self.editingKitId, name, "", cooldown, self.editPermission, itemsStr)
end

function KitsUI:populateItemSearch(searchText)
    if not self.itemSearchList then return end
    self.itemSearchList:clear()
    if not searchText or #searchText < 2 then return end

    if not self.itemSearchCache then
        self.itemSearchCache = {}
        local allItems = ScriptManager.instance:getAllItems()
        if allItems then
            for i = 0, allItems:size() - 1 do
                local si = allItems:get(i)
                if si then
                    local fullName = si:getFullName()
                    local displayName = si:getDisplayName()
                    if fullName and displayName then
                        table.insert(self.itemSearchCache, {
                            type = fullName,
                            name = displayName,
                        })
                    end
                end
            end
        end
    end

    local lower = searchText:lower()
    local count = 0
    for _, item in ipairs(self.itemSearchCache) do
        if count >= 20 then break end
        if item.name:lower():find(lower, 1, true) or item.type:lower():find(lower, 1, true) then
            self.itemSearchList:addItem(item.name .. "  [" .. item.type .. "]", {
                type = item.type,
                name = item.name,
                tex = getItemTexture(item.type),
            })
            count = count + 1
        end
    end
end

function KitsUI:getSelectedPlayerName()
    if not self.playerListBox then return nil end
    local sel = self.playerListBox.selected
    if not sel or sel < 1 or sel > #self.playerListBox.items then return nil end
    return self.playerListBox.items[sel].item.name
end

function KitsUI:filterPlayerList(searchText)
    if not self.playerListBox then return end
    self.playerListBox:clear()
    local lower = searchText and searchText:lower() or ""
    local players = KitsClient.AllPlayers
    if not players or #players == 0 then
        players = {}
        for _, name in ipairs(KitsClient.OnlinePlayers or {}) do
            table.insert(players, { name = name, online = true })
        end
    end
    for _, pl in ipairs(players) do
        if lower == "" or pl.name:lower():find(lower, 1, true) then
            self.playerListBox:addItem(pl.name, pl)
        end
    end
end

function KitsUI:onSelectRoleVip()
    self.adminSelectedRole = "vip"
    self.roleBtnVip.backgroundColor = { r = 0.20, g = 0.55, b = 0.20, a = 0.9 }
    self.roleBtnVip.borderColor = { r = 0.40, g = 0.80, b = 0.40, a = 0.8 }
    self.roleBtnUlt.backgroundColor = C_CARD
    self.roleBtnUlt.borderColor = C_BORDER
end

function KitsUI:onSelectRoleUlt()
    self.adminSelectedRole = "ultimate"
    self.roleBtnUlt.backgroundColor = { r = 0.55, g = 0.35, b = 0.10, a = 0.9 }
    self.roleBtnUlt.borderColor = { r = 0.90, g = 0.55, b = 0.10, a = 0.8 }
    self.roleBtnVip.backgroundColor = C_CARD
    self.roleBtnVip.borderColor = C_BORDER
end

function KitsUI:onAdminGiveRole()
    local pn = self:getSelectedPlayerName()
    if not pn then return end
    local days = tonumber(self.adminDaysEntry:getText())
    if not days or days <= 0 then return end
    KitsClient.AdminSetTempRole(pn, self.adminSelectedRole, days)
end

function KitsUI:onAdminRemoveRole()
    local pn = self:getSelectedPlayerName()
    if not pn then return end
    KitsClient.AdminRemoveTempRole(pn)
end

function KitsUI:onAdminRefresh()
    KitsClient.AdminListTempRoles()
    KitsClient.AdminListAllPlayers()
end

function KitsUI:updateTempRolesList()
    for _, lbl in ipairs(self.tempRolesLabels) do
        self.rolesSubPanel:removeChild(lbl)
    end
    self.tempRolesLabels = {}

    local y = self.tempRolesListY or 200
    local roles = KitsClient.TempRoles or {}
    if #roles == 0 then
        local lbl = ISLabel:new(PAD + 10, y, 18, "(ninguno)",
            C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, C_TEXT2.a, UIFont.Small, true)
        self.rolesSubPanel:addChild(lbl)
        table.insert(self.tempRolesLabels, lbl)
    else
        for _, entry in ipairs(roles) do
            local rolColor = getRoleColor(entry.role)
            local suffix = ""
            local daysLeft = tonumber(entry.daysLeft)
            if daysLeft and daysLeft >= 0 then
                suffix = "(" .. entry.daysLeft .. "d)"
            else
                suffix = "(servidor)"
            end
            local line = entry.playerName .. "  -  " .. entry.role:upper() .. "  " .. suffix
            local lbl = ISLabel:new(PAD + 10, y, 18, line,
                rolColor.r, rolColor.g, rolColor.b, rolColor.a, UIFont.Small, true)
            self.rolesSubPanel:addChild(lbl)
            table.insert(self.tempRolesLabels, lbl)
            y = y + 20
        end
    end
end

function KitsUI:updateOnlineList()
    local players = KitsClient.OnlinePlayers or {}
    if #KitsClient.AllPlayers == 0 then
        self:filterPlayerList(self.lastPlayerSearchText)
    end
end

function KitsUI:updatePlayerList()
    self:filterPlayerList(self.lastPlayerSearchText)
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
        KitsClient.AdminListTempRoles()
        KitsClient.AdminListAllPlayers()
    else
        self.adminBtn.backgroundColor = { r = C_ADMIN.r, g = C_ADMIN.g, b = C_ADMIN.b, a = 0.55 }
    end
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

    if self.showingAdmin and self.adminActiveTab == "kits" and self.itemSearchEntry then
        local txt = self.itemSearchEntry:getText()
        if txt ~= self.lastSearchText then
            self.lastSearchText = txt
            self:populateItemSearch(txt)
        end
    end

    if self.showingAdmin and self.adminActiveTab == "roles" and self.playerSearchEntry then
        local txt = self.playerSearchEntry:getText()
        if txt ~= self.lastPlayerSearchText then
            self.lastPlayerSearchText = txt
            self:filterPlayerList(txt)
        end
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

    if self.showingAdmin then
        if self.adminActiveTab == "kits" and self.editingKitId then
            local items = self.editItemDisplayData or {}
            local panelY = HEADER_H + 30
            local startY = self.editItemsStartY or 0
            for idx, item in ipairs(items) do
                local iy = panelY + startY + (idx - 1) * EDIT_ITEM_H
                local ix = PAD + 6

                self:drawRect(ix - 4, iy, PANEL_W - PAD * 2 - 48, EDIT_ITEM_H - 2,
                    0.6, C_CARD.r, C_CARD.g, C_CARD.b)

                if item.tex then
                    self:drawTextureScaled(item.tex, ix, iy + 2, EDIT_ICON, EDIT_ICON, 1, 1, 1, 1)
                else
                    local letter = item.name:sub(1, 1)
                    local lw = getTextManager():MeasureStringX(UIFont.Small, letter)
                    self:drawText(letter, ix + (EDIT_ICON - lw) / 2, iy + 4,
                        C_TEXT2.r, C_TEXT2.g, C_TEXT2.b, 0.6, UIFont.Small)
                end

                local label = item.name .. "  x" .. tostring(item.count)
                self:drawText(label, ix + EDIT_ICON + 8, iy + 4,
                    C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small)
            end
        end
        return
    end

    do
        local role = KitsClient.PlayerRole or "user"
        local roleUpper = role:upper()
        local barY = HEADER_H + 4
        local barX = PAD
        local barW = PANEL_W - PAD * 2
        local roleColor = getRoleColor(role)
        self:drawRect(barX, barY, barW, ROLE_BAR_H, 0.7, C_CARD.r, C_CARD.g, C_CARD.b)
        local roleFont = UIFont.Small
        local roleLabel = "Rol: " .. roleUpper
        local daysLeft = KitsClient.PlayerRoleDaysLeft
        if daysLeft > 0 then
            roleLabel = roleLabel .. "  (" .. tostring(daysLeft) .. "d restantes)"
        elseif role ~= "user" and daysLeft == -1 then
            roleLabel = roleLabel .. "  (permanente)"
        end
        self:drawText(roleLabel, barX + 8, barY + 3,
            roleColor.r, roleColor.g, roleColor.b, roleColor.a, roleFont)
    end

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
                local stFont = UIFont.NewSmall
                local stw = getTextManager():MeasureStringX(stFont, stText)
                local sth = getTextManager():MeasureStringY(stFont, stText)
                local pillPadX = 8
                local pillPadY = 4
                local pillW = stw + pillPadX * 2
                local pillH = sth + pillPadY * 2
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
                self:drawText(stText, pillX + pillPadX, pillY + pillPadY,
                    txColor.r, txColor.g, txColor.b, txColor.a, stFont)
            end

            local sepY2 = cy + 43
            self:drawRect(cx + ACCENT_BAR_W + 8, sepY2, cw - ACCENT_BAR_W - 16, 1,
                0.12, kc.r, kc.g, kc.b)

            local itemAreaW = cw - ACCENT_BAR_W - 16
            local slotsPerRow = math.floor(itemAreaW / (ICON_SIZE + ICON_GAP))
            if slotsPerRow < 1 then slotsPerRow = 1 end

            local startX = cx + ACCENT_BAR_W + 8
            local slotY = cy + 46
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
                    local badgeFont = UIFont.Small
                    local csw = getTextManager():MeasureStringX(badgeFont, cs)
                    local tx = ix + ICON_SIZE - csw - 2
                    local ty = iy + ICON_SIZE - 18
                    self:drawText(cs, tx + 1, ty + 1, 0, 0, 0, 0.9, badgeFont)
                    self:drawText(cs, tx - 1, ty - 1, 0, 0, 0, 0.9, badgeFont)
                    self:drawText(cs, tx, ty,
                        C_BTN.r, C_BTN.g, C_BTN.b, 1, badgeFont)
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

function KitsUI:rebuildKitsPanel()
    if self.kitsPanel then
        self:removeChild(self.kitsPanel)
    end
    self.kitButtons = {}
    self.kitCards = {}
    self.kitNameLabels = {}
    self.kitItemData = {}
    self.kitStatus = {}
    self:buildKitsPanel()
    if self.showingAdmin then
        self.kitsPanel:setVisible(false)
    end
    self:updateCooldowns()
    if self.editingKitId then
        self:loadKitIntoEditor(self.editingKitId)
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
