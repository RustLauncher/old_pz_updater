-- Neat skin for the Fluid Info window: header, chrome and footer drawn in
-- NeatUI_Framework's style. Skins the widget only - layout, model and handlers stay the
-- base mod's, and everything here no-ops when the framework is absent.

if isServer() then return end

require "ISUI/ISPanel"
pcall(require, "Vehicles/VFluidInfo")
pcall(require, "NeatUI_Framework/UI/NI_SquareButton")

local function log(msg) print("[VFluidLibNeatUI] " .. tostring(msg)) end

local W = rawget(_G, "VFluidInfoWindow")
if not (W and W.windows) then
    log("VFluidLib info window not found - skin disabled")
    return
end
if W._vfnuiPatched then return end
W._vfnuiPatched = true

local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local HEADER_H = math.floor(FONT_HGT_MEDIUM * 1.5)
local BTN      = math.floor(FONT_HGT_MEDIUM)
local PAD      = math.max(2, math.floor(FONT_HGT_SMALL * 0.4))
local CLOSE    = { r = 0.8, g = 0.2, b = 0.2 }

local NP_BODY   = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png"
local NP_HEADER = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png"
local TEX_CLOSE = "media/ui/NeatUI/Icon/Icon_False.png"

local function np(path)
    if not NinePatchTexture then return nil end
    local ok, t = pcall(NinePatchTexture.getSharedTexture, path)
    if ok then return t end
    return nil
end

local function theme(key, default)
    local v = NR_Config and NR_Config[key]
    if v ~= nil then return v end
    return default
end

local iconTex = nil
local function windowIcon()
    if iconTex == nil then
        iconTex = getTexture("media/ui/vfluid/fluid_info.png") or false
    end
    return iconTex or nil
end

------------------------------------------------------------
-- Title bar widget
------------------------------------------------------------
VFNUI_Header = ISPanel:derive("VFNUI_Header")

function VFNUI_Header:new(x, y, w, h, win)
    local o = ISPanel.new(self, x, y, w, h)
    o.win = win
    o.moving = false
    o:noBackground()
    o:setAnchorRight(true)
    return o
end

function VFNUI_Header:createChildren()
    local bx = self.width - PAD - BTN
    local by = math.floor((self.height - BTN) / 2)
    local onClose = function() if self.win and self.win.close then self.win:close() end end
    local NI = rawget(_G, "NI_SquareButton")
    local closeTex = getTexture(TEX_CLOSE)
    if NI and closeTex then
        self.closeBtn = NI:new(bx, by, BTN, closeTex, self, onClose)
        self.closeBtn:initialise()
        self.closeBtn:setActive(true)
        self.closeBtn:setActiveColor(CLOSE.r, CLOSE.g, CLOSE.b)
    else
        self.closeBtn = ISButton:new(bx, by, BTN, BTN, "X", self, onClose)
        self.closeBtn:initialise()
    end
    self.closeBtn:setAnchorLeft(false)
    self.closeBtn:setAnchorRight(true)
    self:addChild(self.closeBtn)
end

function VFNUI_Header:prerender()
    local band = np(NP_HEADER)
    local c = theme("headerBg", 0.08)
    if band then
        band:render(self:getAbsoluteX(), self:getAbsoluteY(), self.width, self.height, c, c, c, theme("bgAlpha", 1))
    else
        self:drawRect(0, 0, self.width, self.height, 1, c, c, c)
    end
    self:drawRect(0, self.height - 1, self.width, 2, 1, 0, 0, 0)
end

function VFNUI_Header:render()
    local x = PAD
    local icon = windowIcon()
    if icon then
        local size = math.floor((self.height * 0.8) / 4) * 4
        self:drawTextureScaledAspect(icon, x, math.floor((self.height - size) / 2), size, size, 1, 1, 1, 1)
        x = x + size + PAD
    end
    local title = (self.win and self.win.title) or ""
    self:drawText(title, x, math.floor((self.height - FONT_HGT_MEDIUM) / 2), 1, 1, 1, 1, UIFont.Medium)
end

function VFNUI_Header:onMouseDown(x, y)
    self.moving = true
    self:setCapture(true)
    if self.win and self.win.bringToTop then self.win:bringToTop() end
    return true
end

local function drag(self, dx, dy)
    if self.moving and self.win then
        self.win:setX(self.win.x + dx)
        self.win:setY(self.win.y + dy)
        return true
    end
    return false
end
function VFNUI_Header:onMouseMove(dx, dy) return drag(self, dx, dy) end
function VFNUI_Header:onMouseMoveOutside(dx, dy) return drag(self, dx, dy) end

local function release(self)
    if self.moving then
        self.moving = false
        self:setCapture(false)
        return true
    end
    return false
end
function VFNUI_Header:onMouseUp(x, y) return release(self) end
function VFNUI_Header:onMouseUpOutside(x, y) return release(self) end

------------------------------------------------------------
-- Window
------------------------------------------------------------

function W:titleBarHeight() return HEADER_H end

local function attachHeader(win)
    if win.vfnuiHeader then return end
    local header
    local ok = pcall(function()
        header = VFNUI_Header:new(0, 0, win:getWidth(), HEADER_H, win)
        header:initialise()
        win:addChild(header)
    end)
    if not ok then
        if header then pcall(win.removeChild, win, header) end
        return
    end
    win.vfnuiHeader = header
    win.pin = true
    for _, name in ipairs({ "closeButton", "collapseButton", "pinButton", "infoButton" }) do
        local btn = win[name]
        if btn then
            btn:setVisible(false)
            btn.setVisible = function() end
        end
    end
    win.collapse = function() end
end

local function syncHeader(win)
    local h = win.vfnuiHeader
    if h and h:getWidth() ~= win:getWidth() then h:setWidth(win:getWidth()) end
end

local function paintChrome(self)
    local body = np(NP_BODY)
    if not body then return false end
    local attached = self.vfnuiHeader ~= nil
    local band = attached and true or np(NP_HEADER)
    if not band then return false end
    local th = self:titleBarHeight()
    local alpha = theme("bgAlpha", 1)
    local cb = theme("panelBg", 0.15)
    if self.background and not self.isCollapsed then
        local y = attached and th or (th - 1)
        body:render(self:getAbsoluteX(), self:getAbsoluteY() + y, self:getWidth(), self:getHeight() - y, cb, cb, cb, alpha)
    end
    if not attached then
        local ch = theme("headerBg", 0.08)
        band:render(self:getAbsoluteX(), self:getAbsoluteY(), self:getWidth(), th, ch, ch, ch, alpha)
        self:drawRect(0, th - 1, self:getWidth(), 2, 1, 0, 0, 0)
        if self.title ~= nil then
            self:drawText(self.title, PAD, math.floor((th - FONT_HGT_MEDIUM) / 2), 1, 1, 1, 1, UIFont.Medium)
        end
    end
    return true
end

local origPrerender = W.prerender

function W:prerender()
    syncHeader(self)
    if not paintChrome(self) then
        origPrerender(self)
        return
    end
    local drawFrame, background = self.drawFrame, self.background
    self.drawFrame, self.background = false, false
    local ok, err = pcall(origPrerender, self)
    self.drawFrame, self.background = drawFrame, background
    if not ok then error(err) end
end

local origRender = W.render

function W:render()
    if not np(NP_BODY) then
        origRender(self)
        return
    end
    local drawFrame = self.drawFrame
    self.drawFrame = false
    local ok, err = pcall(origRender, self)
    self.drawFrame = drawFrame
    if not ok then error(err) end
end

local function footerRender(tt)
    if not np(NP_BODY) then
        ISToolTip.render(tt)
        return
    end
    tt:renderContents()
end

local origEnsureFooter = W.ensureFooter

function W:ensureFooter()
    local f = origEnsureFooter(self)
    if f and f.render ~= footerRender then
        f.render = footerRender
    end
    return f
end

local origCreateChildren = W.createChildren

function W:createChildren()
    origCreateChildren(self)
    attachHeader(self)
end

log("applied")
