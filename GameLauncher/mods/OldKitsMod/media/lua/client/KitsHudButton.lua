require "ISUI/ISPanel"
require "ISUI/ISButton"
require "client/KitsUI"

KitsHudButton = ISPanel:derive("KitsHudButton")
KitsHudButton.instance = nil

local BTN_SIZE = 48

function KitsHudButton:new(x, y)
    local o = ISPanel:new(x, y, BTN_SIZE, BTN_SIZE)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    return o
end

function KitsHudButton:createChildren()
    ISPanel.createChildren(self)
    self.btn = ISButton:new(0, 0, BTN_SIZE, BTN_SIZE, "", self, KitsHudButton.onClick)
    self.btn:initialise()
    self.btn:instantiate()
    self.btn.backgroundColor = { r = 0.12, g = 0.12, b = 0.12, a = 0.85 }
    self.btn.backgroundColorMouseOver = { r = 0.20, g = 0.20, b = 0.20, a = 0.90 }
    self.btn.borderColor = { r = 0.90, g = 0.55, b = 0.10, a = 0.8 }
    self.btn.textColor = { r = 0.90, g = 0.55, b = 0.10, a = 1 }
    self.btn.tooltip = "Kits (K)"
    self:addChild(self.btn)
end

function KitsHudButton:prerender()
    ISPanel.prerender(self)
end

function KitsHudButton:render()
    ISPanel.render(self)
    local x = self.btn:getX()
    local y = self.btn:getY()
    local w = BTN_SIZE
    local h = BTN_SIZE
    local cx = x + w / 2
    local cy = y + h / 2

    local r, g, b, a = 0.90, 0.55, 0.10, 1.0

    -- box icon (kit crate)
    self:drawRect(cx - 12, cy - 10, 24, 20, a * 0.3, r, g, b)
    self:drawRectBorder(cx - 12, cy - 10, 24, 20, a, r, g, b)
    -- lid
    self:drawRect(cx - 14, cy - 13, 28, 5, a * 0.5, r, g, b)
    self:drawRectBorder(cx - 14, cy - 13, 28, 5, a, r, g, b)
    -- clasp
    self:drawRect(cx - 3, cy - 4, 6, 8, a, r, g, b)

    -- "K" label
    self:drawTextCentre("K", cx, cy + 12, r, g, b, a, UIFont.Small)
end

function KitsHudButton:onClick()
    local player = getPlayer()
    if player and player:isAlive() then
        KitsUI.Toggle()
    end
end

local function createHudButton()
    if KitsHudButton.instance then return end
    local sw = getCore():getScreenWidth()
    local x = sw - BTN_SIZE - 10
    local y = 10
    local btn = KitsHudButton:new(x, y)
    btn:initialise()
    btn:addToUIManager()
    btn:setVisible(true)
    KitsHudButton.instance = btn
end

local function removeHudButton()
    if KitsHudButton.instance then
        KitsHudButton.instance:removeFromUIManager()
        KitsHudButton.instance = nil
    end
end

Events.OnCreateUI.Add(createHudButton)
Events.OnMainMenuEnter.Add(removeHudButton)
