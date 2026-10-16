-- TrailerCargo_ArrangeUI: the arrange session's panel. Move and Rotate pick
-- vanilla's translate or rotate gizmo; Unstack hides it.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client

local WIDTH, HEIGHT = 230, 132
local PAD = 10

---@class TrailerCargo.ArrangeUI : ISPanel
TrailerCargoArrangeUI = ISPanel:derive("TrailerCargoArrangeUI")

function TrailerCargoArrangeUI:createChildren()
  ISPanel.createChildren(self)
  local bw, bh = (WIDTH - PAD * 3) / 2, 22
  local y = HEIGHT - PAD - bh

  self.doneBtn = ISButton:new(PAD, y, bw, bh, getText("UI_TrailerCargo_Done"), self, self.onDone)
  self.doneBtn:initialise()
  self.doneBtn:instantiate()
  self.doneBtn.borderColor = { r = 0.4, g = 0.7, b = 0.4, a = 1 }
  self:addChild(self.doneBtn)

  self.revertBtn = ISButton:new(PAD * 2 + bw, y, bw, bh, getText("UI_TrailerCargo_Revert"), self, self.onRevert)
  self.revertBtn:initialise()
  self.revertBtn:instantiate()
  self:addChild(self.revertBtn)

  -- the three modes share one row
  y = y - bh - 6
  local mw = (WIDTH - PAD * 4) / 3
  self.moveBtn = ISButton:new(PAD, y, mw, bh, getText("UI_TrailerCargo_Move"), self, self.onMove)
  self.moveBtn:initialise()
  self.moveBtn:instantiate()
  self:addChild(self.moveBtn)

  self.rotateBtn = ISButton:new(PAD * 2 + mw, y, mw, bh, getText("UI_TrailerCargo_Rotate"), self, self.onRotate)
  self.rotateBtn:initialise()
  self.rotateBtn:instantiate()
  self:addChild(self.rotateBtn)

  self.unstackBtn = ISButton:new(PAD * 3 + mw * 2, y, mw, bh, getText("UI_TrailerCargo_Unstack"), self, self.onUnstack)
  self.unstackBtn:initialise()
  self.unstackBtn:instantiate()
  self:addChild(self.unstackBtn)
end

function TrailerCargoArrangeUI:onDone()
  C.stopArrange()
end

function TrailerCargoArrangeUI:onRevert()
  C.revertArrange()
end

function TrailerCargoArrangeUI:onMove()
  C.setGizmoMode("translate")
end

function TrailerCargoArrangeUI:onRotate()
  C.setGizmoMode("rotate")
end

function TrailerCargoArrangeUI:onUnstack()
  C.setGizmoMode("unstack")
end

-- The live mode's button is filled blue (an alpha change alone is invisible).
local ACTIVE_BG = { r = 0.20, g = 0.45, b = 0.75, a = 0.9 }
local ACTIVE_OVER = { r = 0.28, g = 0.55, b = 0.85, a = 1.0 }
local ACTIVE_BORDER = { r = 0.6, g = 0.85, b = 1.0, a = 1 }
local IDLE_BG = { r = 0, g = 0, b = 0, a = 0.5 }
local IDLE_OVER = { r = 0.3, g = 0.3, b = 0.3, a = 1.0 }
local IDLE_BORDER = { r = 0.7, g = 0.7, b = 0.7, a = 1 }

---@param btn ISButton
---@param on boolean
local function paintMode(btn, on)
  btn.backgroundColor = on and ACTIVE_BG or IDLE_BG
  btn.backgroundColorMouseOver = on and ACTIVE_OVER or IDLE_OVER
  btn.borderColor = on and ACTIVE_BORDER or IDLE_BORDER
end

function TrailerCargoArrangeUI:prerender()
  ISPanel.prerender(self)
  self:drawText(getText("UI_TrailerCargo_Arrange"), PAD, PAD, 1, 1, 1, 1, UIFont.Medium)
  local line = C.arrangeStatus and C.arrangeStatus() or ""
  self:drawText(line, PAD, PAD + 22, 0.8, 0.8, 0.8, 1, UIFont.Small)
  -- which gizmo is live
  local mode = C.gizmoMode and C.gizmoMode() or "translate"
  if self.moveBtn then
    paintMode(self.moveBtn, mode == "translate")
    paintMode(self.rotateBtn, mode == "rotate")
    paintMode(self.unstackBtn, mode == "unstack")
  end
end

-- How far above the click the panel's bottom edge sits.
local ABOVE = 120

-- Opens centred over the click, bottom edge ABOVE pixels up, on screen.
---@param playerNum integer
---@param clickX number  screen pixels
---@param clickY number
function TrailerCargoArrangeUI:new(playerNum, clickX, clickY)
  local n = math.floor(playerNum)
  local left, top = getPlayerScreenLeft(n), getPlayerScreenTop(n)
  local right, bottom = left + getPlayerScreenWidth(n), top + getPlayerScreenHeight(n)
  local x = math.floor(clickX - WIDTH / 2)
  local y = math.floor(clickY - ABOVE - HEIGHT)
  x = math.max(left, math.min(x, right - WIDTH))
  y = math.max(top, math.min(y, bottom - HEIGHT))
  local o = ISPanel.new(self, x, y, WIDTH, HEIGHT)
  o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.75 }
  o.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
  o.moveWithMouse = true
  o.playerNum = playerNum
  return o
end
