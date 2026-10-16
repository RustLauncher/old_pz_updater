-- TrailerCargo_CarArrange: fine-tuning the cars on a car trailer with
-- vanilla's gizmos; swapping two cars' places. Hover lifts the car under
-- the mouse, a click selects it. Rotate keeps the spin and the nose tilt. Poses
-- are previewed locally and sent on Done; a swap is sent at once. The drag
-- exists only to swallow world clicks (TrailerCargo_Arrange). A gamepad
-- player drives it without gizmos:
--   D-pad          the previous or next car
--   hold Y + stick slide the marked car; Y + D-pad up / down raises or lowers it
--   Y + D-pad left / right  swap places with the previous or next car
--   LB / RB        turn it: a tap turns 5 degrees, a hold keeps turning
--   Y + LB / RB    tilt its nose down or up
--   X              its look: car, cover, hidden; Y + X back on its place
--   A              done; B cancel, every pose put back
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local B, CT, Tr = TrailerCargo.Bed, TrailerCargo.CarTrailer, TrailerCargo.Trunk

local LIFT = 0.12
-- how near the mouse must be to a car's pivot, screen pixels at zoom 1
local PICK_PX = 140
local REACH = 12

---@class TrailerCargo.CarArrange
---@field playerNum integer
---@field crec TrailerCargo.CarRec
---@field drag table
---@field ui ISPanel|nil
---@field mode string       "translate", "rotate" or "swap"
---@field hover integer|nil  position under the mouse
---@field sel integer|nil
---@field dragYaw number|nil the yaw a ring drag began from
---@field dragTilt number|nil its tilt
---@field start table<integer, TrailerCargo.CarPose>
---@field dirty table<integer, boolean>
---@field pad boolean        driven from a gamepad
---@field padMoving boolean|nil  Y is held
---@field padTurnAt number|nil   when LB or RB went down, ms
---@field padTurnSign number|nil
---@field padTurning boolean|nil held past a tap

---@type TrailerCargo.CarArrange|nil
local active

---@param crec TrailerCargo.CarRec
---@param p integer
---@return TrailerCargo.CarPose
local function poseAt(crec, p)
  return crec.preview[p] or CT.poseAt(C.carLayout(crec), p)
end

---@param crec TrailerCargo.CarRec
---@param p integer
---@return number|nil wx, number wy, number wz
local function pivotWorld(crec, p)
  local d = crec.drawn[p]
  if not d then return nil, 0, 0 end
  local px, py, pz = CT.pivotAt(d.place, poseAt(crec, p))
  return C.partToWorld(crec, C.frame(crec), px, py, pz)
end

---@param a TrailerCargo.CarArrange
local function detachGizmo(a)
  local g = Gizmos.getInstance():getGizmo(a.playerNum)
  if g then g:setVisible(false) end
  ---@diagnostic disable-next-line: param-type-mismatch
  Gizmos.getInstance():setGizmo(a.playerNum, nil)
end

-- On the selected car's pivot, turned with it. Called after every drag
-- step: the translate gizmo does not move itself (TranslateGizmo:168).
---@param a TrailerCargo.CarArrange
local function attachGizmo(a)
  local p = a.sel
  if not p or a.mode == "swap" or a.pad or not a.crec.drawn[p] then
    detachGizmo(a)
    return
  end
  local gz = Gizmos.getInstance()
  local g = a.mode == "rotate" and gz:getRotateGizmo(a.playerNum) or gz:getTranslateGizmo(a.playerNum)
  local wx, wy, wz = pivotWorld(a.crec, p)
  if not wx then return end
  g:setWorldPosition(wx, wy, wz)
  -- setRotation stores (x, z, y) (Gizmo.java:55): yaw goes last
  -- the ring about the car's cross axis is its tilt, nose up = negative x
  local pose = poseAt(a.crec, p)
  local gx, gy, gzr = B.gizmoEuler(B.sceneFrame(C.frame(a.crec)), pose.yaw, -(pose.tilt or 0), 0)
  g:setRotation(gx, gzr, gy)
  g:setVisible(true)
  g:setTable(a.drag)
  gz:setGizmo(a.playerNum, g)
end

---@param a TrailerCargo.CarArrange
local function setHover(a, p)
  if p == a.hover then return end
  local crec = a.crec
  if a.hover and a.hover ~= a.sel then
    crec.lift[a.hover] = nil
    C.poseCar(crec, a.hover)
  end
  if p and p ~= a.sel then
    crec.lift[p] = LIFT
    C.poseCar(crec, p)
  end
  a.hover = p
end

---@param a TrailerCargo.CarArrange
---@param p integer
---@param pose TrailerCargo.CarPose
local function place(a, p, pose)
  local crec = a.crec
  if not a.start[p] then a.start[p] = poseAt(crec, p) end
  crec.preview[p] = CT.clampPose(pose)
  a.dirty[p] = true
  C.poseCar(crec, p)
  attachGizmo(a)
end

---@param a TrailerCargo.CarArrange
local function sendPoses(a)
  local player = getSpecificPlayer(a.playerNum)
  if not player then return end
  -- before sending: single player may apply a command at once
  local rev = C.carLayout(a.crec).rev
  local sent = false
  for p in pairs(a.dirty) do
    local pose = a.crec.preview[p]
    if pose then
      sendClientCommand(player, Tr.MODULE, "carPose", {
        vehicle = a.crec.id, pos = p, x = pose.x, y = pose.y, z = pose.z, yaw = pose.yaw, tilt = pose.tilt or 0,
      })
      sent = true
    end
  end
  a.dirty = {}
  -- previews go when the server's layout comes back (TrailerCargo_CarDraw)
  if sent then a.crec.previewRev = rev end
end

---@param a TrailerCargo.CarArrange
local function selectCar(a, p)
  local crec = a.crec
  if a.mode == "swap" and a.sel and p and p ~= a.sel then
    local player = getSpecificPlayer(a.playerNum)
    sendPoses(a)
    if player then sendClientCommand(player, Tr.MODULE, "carSwap", { vehicle = crec.id, a = a.sel, b = p }) end
    if C.debug() then C.log("car swap " .. a.sel .. " <-> " .. p) end
    a.mode = "translate"
  end
  if a.sel and a.sel ~= p then
    crec.lift[a.sel] = nil
    C.poseCar(crec, a.sel)
  end
  a.sel = p
  if p then
    crec.lift[p] = nil
    C.poseCar(crec, p)
  end
  attachGizmo(a)
end

function C.stopCarArrange()
  local a = active
  if not a then return end
  active = nil
  local crec = a.crec
  if a.pad and a.padMoving then
    local player = getSpecificPlayer(a.playerNum)
    if player then player:setIgnoreMovement(false) end
  end
  for p in pairs(crec.lift) do
    crec.lift[p] = nil
    C.poseCar(crec, p)
  end
  sendPoses(a)
  detachGizmo(a)
  if a.ui then
    a.ui:setVisible(false)
    a.ui:removeFromUIManager()
    a.ui = nil
  end
  if getCell():getDrag(a.playerNum) == a.drag then
    ---@diagnostic disable-next-line: param-type-mismatch
    getCell():setDrag(nil, a.playerNum)
  end
end

function C.revertCarArrange()
  local a = active
  if not a then return end
  for p, pose in pairs(a.start) do
    a.crec.preview[p] = pose
    a.dirty[p] = true
    C.poseCar(a.crec, p)
  end
  attachGizmo(a)
end

-- The selected car back on its place.
function C.resetCar()
  local a = active
  if not a or not a.sel then return end
  place(a, a.sel, { x = 0, y = 0, z = 0, yaw = 0, tilt = 0 })
end

-- The selected car's next look: car, cover, hidden, car. Applied at once.
function C.cycleCarShow()
  local a = active
  if not a or not a.sel then return end
  local player = getSpecificPlayer(a.playerNum)
  local show = CT.nextShow(CT.showAt(C.carLayout(a.crec), a.sel))
  if player then sendClientCommand(player, Tr.MODULE, "carShow", { vehicle = a.crec.id, pos = a.sel, show = show }) end
end

---@return string|nil  the selected car's look
function C.carShowOf()
  local a = active
  if not a or not a.sel then return nil end
  return CT.showAt(C.carLayout(a.crec), a.sel)
end

function C.setCarMode(mode)
  local a = active
  if not a then return end
  a.mode = mode
  attachGizmo(a)
end

function C.carMode()
  return active and active.mode or "translate"
end

function C.carArrangeStatus()
  local a = active
  if not a then return "" end
  if a.mode == "swap" then
    return a.sel and getText("UI_TrailerCargo_ClickSwap") or getText("UI_TrailerCargo_ClickCar")
  end
  if a.sel then return getText("UI_TrailerCargo_Selected") .. " " .. (a.crec.drawn[a.sel] and a.crec.drawn[a.sel].label or "") end
  return getText("UI_TrailerCargo_ClickCar")
end

-- The drawn car whose pivot is nearest the mouse on screen.
---@param a TrailerCargo.CarArrange
---@return integer|nil
local function pick(a)
  local mx, my = getMouseX(), getMouseY()
  local zoom = getCore():getZoom(a.playerNum)
  local best, bd = nil, (PICK_PX / zoom) ^ 2
  for p in pairs(a.crec.drawn) do
    local wx, wy, wz = pivotWorld(a.crec, p)
    if wx then
      local sx, sy = isoToScreenX(a.playerNum, wx, wy, wz), isoToScreenY(a.playerNum, wx, wy, wz)
      local d = (sx - mx) ^ 2 + (sy - my) ^ 2
      if d < bd then best, bd = p, d end
    end
  end
  return best
end

local lastPick = 0

local function onRenderTick()
  local a = active
  if not a then return end
  if getCell():getDrag(a.playerNum) ~= a.drag or C.cars[a.crec.id] ~= a.crec then
    C.stopCarArrange()
    return
  end
  if a.pad then
    C.carPadTick(a)
    return
  end
  if Gizmos.getInstance():isTrackingMouse() then return end
  a.dragYaw, a.dragTilt = nil, nil
  local now = getTimestampMs()
  if now - lastPick < 40 then return end
  lastPick = now
  setHover(a, pick(a))
end

-- The translate gizmo reports the pivot's world position.
---@param a TrailerCargo.CarArrange
---@param v Vector3f
local function onTranslate(a, v)
  local p = a.sel
  if not p then return end
  local d = a.crec.drawn[p]
  if not d then return end
  local px, py, pz = C.worldToPart(a.crec, C.frame(a.crec), v:x(), v:y(), v:z())
  if not px or not py or not pz then return end
  local pose = poseAt(a.crec, p)
  place(a, p, { x = px, y = py - d.place.pivotY, z = pz - d.place.pivotZ, yaw = pose.yaw, tilt = pose.tilt })
end

-- The rotate gizmo reports the orientation at the drag's start composed
-- with the drag (RotateGizmo.java:199): the spin and the nose tilt are
-- kept, the side roll (its own ring, which cannot be hidden) is not.
---@param a TrailerCargo.CarArrange
---@param v Vector3f
local function onRotate(a, v)
  local p = a.sel
  if not p or not a.crec.drawn[p] then return end
  local pose = poseAt(a.crec, p)
  if not a.dragYaw then a.dragYaw, a.dragTilt = pose.yaw, pose.tilt or 0 end
  local yaw, rx = B.poseFromGizmo(B.sceneFrame(C.frame(a.crec)), v:x(), v:z(), v:y(), a.dragYaw, -a.dragTilt, 0)
  -- poseFromGizmo keeps its lean in 0..360
  local tilt = -rx
  if tilt < -180 then tilt = tilt + 360 end
  place(a, p, { x = pose.x, y = pose.y, z = pose.z, yaw = yaw, tilt = tilt })
end

-- Gamepad. World tiles a full stick moves per 33 ms frame and the
-- tap-or-hold turn, as the item pad (TrailerCargo_ArrangePad); RAISE is
-- part units a Y + D-pad press lifts.
local STICK = 0.025
local RAISE = 0.05
local TAP_DEG = 5
local HOLD_MS = 250

-- The marked car up, or down where it is while Y is held.
---@param a TrailerCargo.CarArrange
local function mark(a)
  local p = a.sel
  if not p then return end
  a.crec.lift[p] = not a.padMoving and LIFT or nil
  C.poseCar(a.crec, p)
end

-- The position dir steps from the marked one, wrapping; nil with none drawn.
---@param a TrailerCargo.CarArrange
---@return integer|nil
local function stepFrom(a, dir)
  local list = {}
  for p in pairs(a.crec.drawn) do list[#list + 1] = p end
  table.sort(list)
  local n = #list
  if n == 0 then return nil end
  local i = 0
  for k = 1, n do
    if list[k] == a.sel then i = k end
  end
  if i == 0 then return list[1] end
  -- Kahlua's % keeps the left operand's sign: keep it positive
  return list[(i - 1 + dir + n) % n + 1]
end

---@param a TrailerCargo.CarArrange
local function step(a, dir)
  local p = stepFrom(a, dir)
  if not p then return end
  selectCar(a, p)
  mark(a)
end

---@param a TrailerCargo.CarArrange
---@param pose TrailerCargo.CarPose
local function placeMarked(a, pose)
  local p = a.sel
  if not p then return end
  place(a, p, pose)
  mark(a)
end

-- Slide the marked car by a world step.
---@param a TrailerCargo.CarArrange
local function slide(a, dx, dy)
  local p = a.sel
  if not p then return end
  local d = a.crec.drawn[p]
  if not d then return end
  local wx, wy, wz = pivotWorld(a.crec, p)
  if not wx then return end
  local px, _, pz = C.worldToPart(a.crec, C.frame(a.crec), wx + dx, wy + dy, wz)
  if not px or not pz then return end
  local pose = poseAt(a.crec, p)
  placeMarked(a, { x = px, y = pose.y, z = pz - d.place.pivotZ, yaw = pose.yaw, tilt = pose.tilt })
end

---@param a TrailerCargo.CarArrange
local function adjust(a, dy, dyaw, dtilt)
  local p = a.sel
  if not p or not a.crec.drawn[p] then return end
  local pose = poseAt(a.crec, p)
  placeMarked(a, { x = pose.x, y = pose.y + dy, z = pose.z, yaw = pose.yaw + dyaw, tilt = (pose.tilt or 0) + dtilt })
end

-- Swap the marked car with the previous or next one; it stays marked.
---@param a TrailerCargo.CarArrange
local function swapStep(a, dir)
  local p = stepFrom(a, dir)
  if not a.sel or not p or p == a.sel then return end
  a.mode = "swap"
  selectCar(a, p)
  mark(a)
end

-- LB / RB: a tap turns (with Y, tilts) TAP_DEG; a hold keeps going,
-- rounded on release.
---@param a TrailerCargo.CarArrange
local function pollTurn(a, joy)
  local back = isJoypadLBPressed(joy)
  local down = back or isJoypadRBPressed(joy)
  local sign = back and -1 or 1
  local tilt = a.padMoving == true
  local function turn(deg)
    if tilt then adjust(a, 0, 0, deg) else adjust(a, 0, deg, 0) end
  end
  local now = getTimestampMs()
  if down then
    if not a.padTurnAt then
      a.padTurnAt, a.padTurnSign = now, sign
    elseif now - a.padTurnAt > HOLD_MS then
      a.padTurning = true
      turn(sign * TAP_DEG * 0.75 * getGameTime():getMultiplier() / 1.6)
    end
    return
  end
  if a.padTurnAt then
    local pose = a.sel and poseAt(a.crec, a.sel)
    if not a.padTurning then
      turn((a.padTurnSign or 1) * TAP_DEG)
    elseif pose then
      local v = tilt and (pose.tilt or 0) or pose.yaw
      turn(math.floor(v / TAP_DEG + 0.5) * TAP_DEG - v)
    end
  end
  a.padTurnAt, a.padTurning = nil, false
end

-- Every render frame of a pad session.
---@param a TrailerCargo.CarArrange
function C.carPadTick(a)
  local player = getSpecificPlayer(a.playerNum)
  if not player then return end
  local joy = player:getJoypadBind()
  if joy == -1 then return end
  local moving = JoypadButton.Y:isDown(joy)
  if moving ~= (a.padMoving == true) then
    a.padMoving = moving
    -- the stick slides the car, not the player
    player:setIgnoreMovement(moving)
    a.padTurnAt, a.padTurning = nil, false
    mark(a)
  end
  if moving then
    local ax, ay = getJoypadMovementAxisX(joy), getJoypadMovementAxisY(joy)
    if ax ~= 0 or ay ~= 0 then
      local d = UIManager.getMillisSinceLastRender() / 33.3 * STICK
      slide(a, ax * d, ay * d)
    end
  end
  pollTurn(a, joy)
end

-- A new pad session: the car nearest the player marked.
---@param a TrailerCargo.CarArrange
local function padStart(a)
  local player = getSpecificPlayer(a.playerNum)
  local best, bd = nil, math.huge
  if player then
    for p in pairs(a.crec.drawn) do
      local wx, wy = pivotWorld(a.crec, p)
      if wx then
        local d = (wx - player:getX()) ^ 2 + (wy - player:getY()) ^ 2
        if d < bd then best, bd = p, d end
      end
    end
  end
  selectCar(a, best or stepFrom(a, 1))
  mark(a)
  if player then player:setHaloNote(getText("UI_TrailerCargo_PadCarHint"), 220, 220, 220, 300) end
end

---@return TrailerCargo.CarArrange|nil
local function padSession()
  if active and active.pad then return active end
  return nil
end

-- Every method a pad's input or its prompts call on the drag; they must
-- exist in a mouse session too.
---@param drag table
local function padBind(drag)
  drag.onJoypadPressButton = function(_, _, _, button)
    local a = padSession()
    if not a then
      if button == Joypad.BButton then C.stopCarArrange() end
      return
    end
    if button == Joypad.XButton then
      if a.padMoving then C.resetCar() else C.cycleCarShow() end
      mark(a)
    elseif a.padMoving then
      return
    elseif button == Joypad.AButton then
      C.stopCarArrange()
    elseif button == Joypad.BButton then
      C.revertCarArrange()
      C.stopCarArrange()
    end
  end
  drag.onJoypadDirUp = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then adjust(a, RAISE, 0, 0) else step(a, -1) end
  end
  drag.onJoypadDirDown = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then adjust(a, -RAISE, 0, 0) else step(a, 1) end
  end
  drag.onJoypadDirLeft = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then swapStep(a, -1) else step(a, -1) end
  end
  drag.onJoypadDirRight = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then swapStep(a, 1) else step(a, 1) end
  end
  drag.getAPrompt = function()
    local a = padSession()
    if not a or a.padMoving then return nil end
    return getText("UI_TrailerCargo_Done")
  end
  drag.getBPrompt = function()
    local a = padSession()
    if a and a.padMoving then return nil end
    return getText("UI_Cancel")
  end
  drag.getXPrompt = function()
    local a = padSession()
    if not a or not a.sel then return nil end
    if a.padMoving then return getText("UI_TrailerCargo_ResetCar") end
    return getText("UI_TrailerCargo_ShowCar") .. ": " .. getText("UI_TrailerCargo_Show_" .. (C.carShowOf() or "car"))
  end
  drag.getYPrompt = function()
    if not padSession() then return nil end
    return getText("IGUI_Place3DItem_JoypadPosition")
  end
  drag.getLBPrompt = function()
    local a = padSession()
    if not a then return nil end
    if a.padMoving then return getText("UI_TrailerCargo_NoseDown") end
    return getText("IGUI_Controller_RotateLeft")
  end
  drag.getRBPrompt = function()
    local a = padSession()
    if not a then return nil end
    if a.padMoving then return getText("UI_TrailerCargo_NoseUp") end
    return getText("IGUI_Controller_RotateRight")
  end
end

---@param player IsoGameCharacter
---@param crec TrailerCargo.CarRec
function C.canArrangeCars(player, crec)
  local n = 0
  for _ in pairs(crec.drawn) do n = n + 1 end
  local dx, dy = player:getX() - crec.vehicle:getX(), player:getY() - crec.vehicle:getY()
  return n > 0 and C.isStopped(crec.vehicle) and crec.vehicle:getUpVectorDot() > 0.9 and dx * dx + dy * dy <= REACH * REACH
end

---@param playerNum integer
---@param crec TrailerCargo.CarRec
function C.startCarArrange(playerNum, crec)
  if C.stopArrange then C.stopArrange() end
  C.stopCarArrange()
  ---@type TrailerCargo.CarArrange
  local a = { playerNum = playerNum, crec = crec, drag = {}, ui = nil, mode = "translate", start = {}, dirty = {},
    pad = C.isPadPlayer ~= nil and C.isPadPlayer(playerNum) }
  -- the methods vanilla's building driver calls on any drag (TrailerCargo_Arrange)
  a.drag.Type = "TrailerCargoCarCursor"
  a.drag.player = playerNum
  a.drag.north = false
  a.drag.nSprite = 1
  a.drag.square = nil
  a.drag.build = false
  a.drag.canBeBuild = false
  a.drag.isLeftDown = false
  a.drag.dragNilAfterPlace = false
  a.drag.craftRecipe = nil
  a.drag.render = function() end
  a.drag.renderOpaqueObjectsInWorld = function() end
  a.drag.getSprite = function() return "carpentry_02_56" end
  a.drag.isValid = function() return false end
  a.drag.rotateMouse = function() end
  a.drag.reinit = function() end
  a.drag.tryBuild = function() end
  a.drag.walkTo = function() return true end
  a.drag.rotateKey = function() end
  a.drag.deactivate = function() C.stopCarArrange() end
  a.drag.onObjectLeftMouseButtonDown = function()
    if not active then return false end
    if Gizmos.getInstance():isTrackingMouse() then return true end
    selectCar(active, active.hover)
    return true
  end
  a.drag.onTranslateGizmo = function(_, v)
    if active then onTranslate(active, v) end
  end
  a.drag.onRotateGizmo = function(_, v)
    if active then onRotate(active, v) end
  end
  -- a pad's buttons and prompts go to whatever is dragged (JoyPadSetup.lua:365)
  padBind(a.drag)
  active = a
  getCell():setDrag(a.drag, playerNum)
  if a.pad then
    padStart(a)
  else
    a.ui = TrailerCargoCarArrangeUI:new(playerNum, getMouseX(), getMouseY())
    a.ui:initialise()
    a.ui:addToUIManager()
  end
end

Events.OnRenderTick.Add(onRenderTick)

-- The session's panel: Move / Rotate / Swap, Reset, Revert / Done.
---@class TrailerCargo.CarArrangeUI : ISPanel
TrailerCargoCarArrangeUI = ISPanel:derive("TrailerCargoCarArrangeUI")

local WIDTH, HEIGHT, PAD = 250, 188, 10

local function button(self, x, y, w, h, key, fn)
  local b = ISButton:new(x, y, w, h, getText(key), self, fn)
  b:initialise()
  b:instantiate()
  self:addChild(b)
  return b
end

function TrailerCargoCarArrangeUI:createChildren()
  ISPanel.createChildren(self)
  local bh = 22
  local half = (WIDTH - PAD * 3) / 2
  local third = (WIDTH - PAD * 4) / 3
  local y = HEIGHT - PAD - bh
  self.doneBtn = button(self, PAD, y, half, bh, "UI_TrailerCargo_Done", function() C.stopCarArrange() end)
  self.doneBtn.borderColor = { r = 0.4, g = 0.7, b = 0.4, a = 1 }
  self.revertBtn = button(self, PAD * 2 + half, y, half, bh, "UI_TrailerCargo_Revert", function() C.revertCarArrange() end)
  y = y - bh - 6
  self.resetBtn = button(self, PAD, y, WIDTH - PAD * 2, bh, "UI_TrailerCargo_ResetCar", function() C.resetCar() end)
  y = y - bh - 6
  self.showBtn = button(self, PAD, y, WIDTH - PAD * 2, bh, "UI_TrailerCargo_ShowCar", function() C.cycleCarShow() end)
  self.showBtn:setTooltip(getText("UI_TrailerCargo_ShowCar_tooltip"))
  y = y - bh - 6
  self.moveBtn = button(self, PAD, y, third, bh, "UI_TrailerCargo_Move", function() C.setCarMode("translate") end)
  self.rotateBtn = button(self, PAD * 2 + third, y, third, bh, "UI_TrailerCargo_Rotate", function() C.setCarMode("rotate") end)
  self.swapBtn = button(self, PAD * 3 + third * 2, y, third, bh, "UI_TrailerCargo_Swap", function() C.setCarMode("swap") end)
end

local ACTIVE = { bg = { r = 0.20, g = 0.45, b = 0.75, a = 0.9 }, over = { r = 0.28, g = 0.55, b = 0.85, a = 1 },
  border = { r = 0.6, g = 0.85, b = 1, a = 1 } }
local IDLE = { bg = { r = 0, g = 0, b = 0, a = 0.5 }, over = { r = 0.3, g = 0.3, b = 0.3, a = 1 },
  border = { r = 0.7, g = 0.7, b = 0.7, a = 1 } }

local function paint(btn, on)
  local c = on and ACTIVE or IDLE
  btn.backgroundColor, btn.backgroundColorMouseOver, btn.borderColor = c.bg, c.over, c.border
end

function TrailerCargoCarArrangeUI:prerender()
  ISPanel.prerender(self)
  self:drawText(getText("UI_TrailerCargo_ArrangeCars"), PAD, PAD, 1, 1, 1, 1, UIFont.Medium)
  self:drawText(C.carArrangeStatus(), PAD, PAD + 22, 0.8, 0.8, 0.8, 1, UIFont.Small)
  local mode = C.carMode()
  if self.moveBtn then
    paint(self.moveBtn, mode == "translate")
    paint(self.rotateBtn, mode == "rotate")
    paint(self.swapBtn, mode == "swap")
    local show = C.carShowOf()
    self.showBtn:setTitle(getText("UI_TrailerCargo_ShowCar") .. ": " .. getText("UI_TrailerCargo_Show_" .. (show or "car")))
    self.showBtn:setEnable(show ~= nil)
  end
end

---@param playerNum integer
function TrailerCargoCarArrangeUI:new(playerNum, clickX, clickY)
  local n = math.floor(playerNum)
  local left, top = getPlayerScreenLeft(n), getPlayerScreenTop(n)
  local right, bottom = left + getPlayerScreenWidth(n), top + getPlayerScreenHeight(n)
  local x = math.max(left, math.min(math.floor(clickX - WIDTH / 2), right - WIDTH))
  local y = math.max(top, math.min(math.floor(clickY - 120 - HEIGHT), bottom - HEIGHT))
  local o = ISPanel.new(self, x, y, WIDTH, HEIGHT)
  o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.75 }
  o.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
  o.moveWithMouse = true
  o.playerNum = playerNum
  return o
end
