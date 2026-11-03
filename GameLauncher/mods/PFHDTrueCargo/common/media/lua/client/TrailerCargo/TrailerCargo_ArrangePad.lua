-- TrailerCargo_ArrangePad: arrange mode from a gamepad.
-- No gizmos; runs like vanilla's pad placement (ISPlace3DItemCursor):
--   D-pad          the previous or next item on the bed (Pack.stepEntry)
--   hold Y + stick slide the marked item across the bed; Y + D-pad nudges
--   LB / RB        turn it flat: a tap turns 5 degrees, a hold keeps turning
--   hold Y + RB    its next resting height: the floor, then each top under it
--   X              split the marked pile, the top layer marked next
--   A              done, the changes kept
--   B              cancel: everything this session put back
--
-- No tilt: a pad places flat, as vanilla's does. A pad's buttons and
-- prompts call methods on whatever is dragged (JoyPadSetup.lua:365,
-- ISButtonPrompt.lua:405), so they must exist in a mouse session too.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local B, P, Tr = TrailerCargo.Bed, TrailerCargo.Pack, TrailerCargo.Trunk

-- World tiles a Y + D-pad press nudges, as vanilla's
local NUDGE = 0.05
-- Tiles a full stick moves per 33 ms frame, as vanilla's
local STICK = 0.025
-- Vanilla's tap-or-hold turn (ISPlace3DItemCursor.handleRotate)
local TAP_DEG = 5
local HOLD_MS = 250

-- A pad drives the session unless player 1 touched the mouse since, as
-- vanilla decides for its placement cursor.
---@param playerNum integer
---@return boolean
function C.isPadPlayer(playerNum)
  local player = getSpecificPlayer(playerNum)
  if not player or player:getJoypadBind() == -1 then return false end
  return not (playerNum == 0 and wasMouseActiveMoreRecentlyThanJoypad())
end

-- The marked item up, or down where it is while Y is held.
---@param a TrailerCargo.Arrange
local function mark(a)
  if a.sel then C.applyEntryPose(a.rec, a.sel, a.padMoving and 0 or C.ARRANGE_LIFT) end
end

---@param a TrailerCargo.Arrange
---@param e TrailerCargo.Entry|nil
local function markEntry(a, e)
  C.arrangeSelect(a, e)
  mark(a)
end

-- Place the marked item and keep it marked.
---@param a TrailerCargo.Arrange
---@param p TrailerCargo.Pose
local function placeMarked(a, p)
  C.arrangePlace(a, p)
  mark(a)
end

-- Slide the marked item by a world step, as the mouse's onTranslate does.
---@param a TrailerCargo.Arrange
local function slide(a, dx, dy)
  local e, p0 = a.sel, a.pose
  if not e or not p0 then return end
  local rec = a.rec
  local fr = C.frame(rec)
  local wx, wy, wz = C.partToWorld(rec, fr, p0.x, C.arrangeRestY(rec, e) + p0.y, p0.z)
  local px, _, pz = C.worldToPart(rec, fr, wx + dx, wy + dy, wz)
  if not px or not pz then return end
  local hx, hz, ox, oz = B.footprint(TrailerCargo.Bounds, e.m, rec.ms)
  local g0 = B.groundAt(rec.bed, B.rect(p0.x, p0.z, p0.yaw, hx, hz, ox, oz))
  local g1 = B.groundAt(rec.bed, B.rect(px, pz, p0.yaw, hx, hz, ox, oz))
  local y = p0.y
  if g0 > 0 and math.abs(y - g0) <= P.SNAP then y = y - g0 + g1 end
  local tops = P.topsUnder(Tr.layoutOf(rec.part), C.ctx(rec), e.ids[1], px, pz, p0.yaw)
  tops[#tops + 1] = g1
  placeMarked(a, { x = px, z = pz, yaw = p0.yaw, y = P.snapLift(y, tops), rx = p0.rx, rz = p0.rz })
end

---@param a TrailerCargo.Arrange
local function turn(a, deg)
  local p0 = a.pose
  if not a.sel or not p0 then return end
  placeMarked(a, { x = p0.x, z = p0.z, yaw = (p0.yaw + deg + 360) % 360, y = p0.y, rx = p0.rx, rz = p0.rz })
end

-- The marked item on its next resting height (Pack.nextRest).
---@param a TrailerCargo.Arrange
local function nextRest(a)
  local e, p0 = a.sel, a.pose
  if not e or not p0 then return end
  local rec = a.rec
  local hx, hz, ox, oz = B.footprint(TrailerCargo.Bounds, e.m, rec.ms)
  local g = B.groundAt(rec.bed, B.rect(p0.x, p0.z, p0.yaw, hx, hz, ox, oz))
  local tops = P.topsUnder(Tr.layoutOf(rec.part), C.ctx(rec), e.ids[1], p0.x, p0.z, p0.yaw)
  placeMarked(a, { x = p0.x, z = p0.z, yaw = p0.yaw, y = P.nextRest(p0.y, tops, g), rx = p0.rx, rz = p0.rz })
end

---@param a TrailerCargo.Arrange
local function step(a, dir)
  markEntry(a, P.stepEntry(Tr.layoutOf(a.rec.part), C.ctx(a.rec), a.sel, dir))
end

-- Split the marked pile; its top layer is marked next.
---@param a TrailerCargo.Arrange
local function unstack(a)
  local e = a.sel
  if not e or #e.ids < 2 then return end
  local top = e.ids[#e.ids]
  C.arrangeSelect(a, nil)
  C.arrangeUnstack(a, e)
  markEntry(a, P.entryOf(Tr.layoutOf(a.rec.part), top))
end

-- LB / RB: a tap turns TAP_DEG; a hold turns smoothly, rounded on release.
---@param a TrailerCargo.Arrange
local function pollTurn(a, joy)
  local back = isJoypadLBPressed(joy)
  local down = back or isJoypadRBPressed(joy)
  local sign = back and -1 or 1
  local now = getTimestampMs()
  if down then
    if not a.padTurnAt then
      a.padTurnAt, a.padTurnSign = now, sign
    elseif now - a.padTurnAt > HOLD_MS then
      a.padTurning = true
      turn(a, sign * TAP_DEG * 0.75 * getGameTime():getMultiplier() / 1.6)
    end
    return
  end
  if a.padTurnAt then
    local p0 = a.pose
    if not a.padTurning then
      turn(a, (a.padTurnSign or 1) * TAP_DEG)
    elseif p0 then
      turn(a, math.floor(p0.yaw / TAP_DEG + 0.5) * TAP_DEG - p0.yaw)
    end
  end
  a.padTurnAt, a.padTurning = nil, false
end

-- Every render frame of a pad session (TrailerCargo_Arrange onRenderTick).
---@param a TrailerCargo.Arrange
function C.padTick(a)
  local player = getSpecificPlayer(a.playerNum)
  if not player then return end
  local joy = player:getJoypadBind()
  if joy == -1 then return end
  local moving = JoypadButton.Y:isDown(joy)
  if moving ~= (a.padMoving == true) then
    a.padMoving = moving
    -- the stick slides the item, not the player
    player:setIgnoreMovement(moving)
    mark(a)
  end
  if moving then
    local ax, ay = getJoypadMovementAxisX(joy), getJoypadMovementAxisY(joy)
    if ax ~= 0 or ay ~= 0 then
      local d = UIManager.getMillisSinceLastRender() / 33.3 * STICK
      slide(a, ax * d, ay * d)
    end
  else
    pollTurn(a, joy)
  end
end

-- A new pad session: the item asked for, else the one nearest the player.
---@param a TrailerCargo.Arrange
function C.padStart(a)
  local e = a.sel
  if not e then
    local player = getSpecificPlayer(a.playerNum)
    local layout = Tr.layoutOf(a.rec.part)
    if player then
      local px, _, pz = C.worldToPart(a.rec, C.frame(a.rec), player:getX(), player:getY(), player:getZ())
      if px and pz then e = P.nearestEntry(layout, C.ctx(a.rec), px, pz) end
    end
    e = e or P.stepEntry(layout, C.ctx(a.rec), nil, 1)
  end
  markEntry(a, e)
  local player = getSpecificPlayer(a.playerNum)
  if player then player:setHaloNote(getText("UI_TrailerCargo_PadHint"), 220, 220, 220, 300) end
end

---@param a TrailerCargo.Arrange
function C.padStop(a)
  local player = getSpecificPlayer(a.playerNum)
  if player and a.padMoving then player:setIgnoreMovement(false) end
  a.padMoving = false
end

-- The live pad session, or nil (a mouse session, or none).
---@return TrailerCargo.Arrange|nil
local function padSession()
  local a = C.arrangeActive()
  if a and a.pad then return a end
  return nil
end

-- Every method a pad's input or its prompts call on the drag.
---@param drag table
function C.padBind(drag)
  drag.onJoypadPressButton = function(_, _, _, button)
    local a = padSession()
    if not a then
      -- a mouse session still closes on B, as any vanilla cursor does
      if button == Joypad.BButton then C.stopArrange() end
      return
    end
    if a.padMoving then
      if button == Joypad.RBumper then nextRest(a) end
      return
    end
    if button == Joypad.AButton then
      C.stopArrange()
    elseif button == Joypad.BButton then
      -- send nothing: a resent place would mark the item hand-placed
      C.revertArrange()
      a.dirty = {}
      C.stopArrange()
    elseif button == Joypad.XButton then
      unstack(a)
    end
  end
  -- held Y nudges; otherwise the D-pad walks the bed
  drag.onJoypadDirUp = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then slide(a, 0, -NUDGE) else step(a, -1) end
  end
  drag.onJoypadDirDown = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then slide(a, 0, NUDGE) else step(a, 1) end
  end
  drag.onJoypadDirLeft = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then slide(a, -NUDGE, 0) else step(a, -1) end
  end
  drag.onJoypadDirRight = function()
    local a = padSession()
    if not a then return end
    if a.padMoving then slide(a, NUDGE, 0) else step(a, 1) end
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
    if not a or a.padMoving or not a.sel or #a.sel.ids < 2 then return nil end
    return getText("UI_TrailerCargo_Unstack")
  end
  drag.getYPrompt = function()
    if not padSession() then return nil end
    return getText("IGUI_Place3DItem_JoypadPosition")
  end
  drag.getLBPrompt = function()
    local a = padSession()
    if not a or a.padMoving then return nil end
    return getText("IGUI_Controller_RotateLeft")
  end
  drag.getRBPrompt = function()
    local a = padSession()
    if not a then return nil end
    if a.padMoving then return getText("UI_TrailerCargo_PadRest") end
    return getText("IGUI_Controller_RotateRight")
  end
end
