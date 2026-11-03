-- TrailerCargo_Arrange: moving cargo around the bed with vanilla's gizmos.
-- A session: hover lifts the item under the mouse (the only highlight a
-- sub-model can get), a click selects it, Move/Rotate/Unstack act on it.
-- Movement is free: items may overlap; only the packer avoids overlaps.
-- The setDrag drag exists only to swallow world clicks. A gamepad player
-- is driven by TrailerCargo_ArrangePad instead.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local B, P, Tr = TrailerCargo.Bed, TrailerCargo.Pack, TrailerCargo.Trunk

-- Part units the hovered entry rises; the selected one never does.
local LIFT = 0.07

---@class TrailerCargo.Pose
---@field x number
---@field z number
---@field yaw number
---@field y number
---@field rx number
---@field rz number

---@class TrailerCargo.Arrange
---@field playerNum integer
---@field rec TrailerCargo.Rec
---@field drag table
---@field ui ISPanel|nil
---@field mode string
---@field hover TrailerCargo.Entry|nil
---@field sel TrailerCargo.Entry|nil
---@field pose TrailerCargo.Pose|nil
---@field dragStart TrailerCargo.Pose|nil  the pose a ring drag began from
---@field dragGround number|false|nil  the ground a drag began resting on; false: it began lifted
---@field start table<number, TrailerCargo.Pose>
---@field dirty table<number, boolean>
---@field unstacks number[]  one id per pile split this session, in order
---@field before TrailerCargo.Entry[]|nil  the list before the first split, for Revert
---@field pad boolean  driven from a gamepad (TrailerCargo_ArrangePad)
---@field padMoving boolean|nil  Y is held: the stick slides the selected item
---@field padTurnAt number|nil  when LB or RB went down, ms
---@field padTurnSign number|nil  1 for RB, -1 for LB
---@field padTurning boolean|nil  held past a tap: turning smoothly

---@type TrailerCargo.Arrange|nil
local active

---@param e TrailerCargo.Entry
---@return TrailerCargo.Pose
local function poseOf(e)
  return { x = e.x, z = e.z, yaw = e.yaw, y = e.y or 0, rx = e.rx or 0, rz = e.rz or 0 }
end

---@param e TrailerCargo.Entry
---@param p TrailerCargo.Pose
local function setPose(e, p)
  e.x, e.z, e.yaw, e.y, e.rx, e.rz = p.x, p.z, p.yaw, p.y, p.rx, p.rz
end

-- The trailer's frame from four getWorldPos probes: origin plus local axes
-- in world tiles. getWorldPos adds local height unscaled, so z is divided
-- by WORLD_FLOOR (BaseVehicle.java:1901).
---@param rec TrailerCargo.Rec|TrailerCargo.CarRec
---@return TrailerCargo.Frame
function C.frame(rec)
  local v, p = rec.vehicle, rec.v0
  local K = B.WORLD_FLOOR
  v:getWorldPos(0, 0, 0, p)
  local ox, oy, oz = p:x(), p:y(), p:z()
  ---@type TrailerCargo.Frame
  local fr = { ox = ox, oy = oy, oz = oz, xx = 0, xy = 0, xz = 0, yx = 0, yy = 0, yz = 0, zx = 0, zy = 0, zz = 0 }
  v:getWorldPos(1, 0, 0, p)
  fr.xx, fr.xy, fr.xz = p:x() - ox, p:y() - oy, (p:z() - oz) / K
  v:getWorldPos(0, 1, 0, p)
  fr.yx, fr.yy, fr.yz = p:x() - ox, p:y() - oy, (p:z() - oz) / K
  v:getWorldPos(0, 0, 1, p)
  fr.zx, fr.zy, fr.zz = p:x() - ox, p:y() - oy, (p:z() - oz) / K
  return fr
end

-- World point to part units, or nils when the frame is degenerate.
---@param rec TrailerCargo.Rec|TrailerCargo.CarRec
---@param fr TrailerCargo.Frame
---@return number|nil px, number|nil py, number|nil pz
function C.worldToPart(rec, fr, wx, wy, wz)
  local lx, ly, lz = B.solve3(fr, wx, wy, wz)
  if not lx or not ly or not lz then return nil, nil, nil end
  local px, pz = B.localToPart(lx, lz, rec.body.x, rec.body.z, rec.ms)
  return px, (ly - rec.body.y) / rec.ms, pz
end

---@param rec TrailerCargo.Rec|TrailerCargo.CarRec
---@param fr TrailerCargo.Frame
---@return number wx, number wy, number wz
function C.partToWorld(rec, fr, px, py, pz)
  local lx, lz = B.partToLocal(px, pz, rec.body.x, rec.body.z, rec.ms)
  return B.frameWorld(fr, lx, rec.body.y + py * rec.ms, lz)
end

-- Part y of an entry's origin when it rests on the floor.
---@param rec TrailerCargo.Rec
---@param e TrailerCargo.Entry
local function restY(rec, e)
  return B.layerY(rec.bed, TrailerCargo.Bounds, e.m, rec.ms, 0)
end

---@param a TrailerCargo.Arrange
---@param e TrailerCargo.Entry|nil
local function setLift(a, e, lift)
  if e then C.applyEntryPose(a.rec, e, lift) end
end

---@param a TrailerCargo.Arrange
local function detachGizmo(a)
  local g = Gizmos.getInstance():getGizmo(a.playerNum)
  if g then g:setVisible(false) end
  ---@diagnostic disable-next-line: param-type-mismatch
  Gizmos.getInstance():setGizmo(a.playerNum, nil)
end

-- Put the mode's gizmo on the selected entry. Called after every drag step
-- too: the translate gizmo does not move itself (TranslateGizmo:168).
---@param a TrailerCargo.Arrange
local function attachGizmo(a)
  local e = a.sel
  -- the gizmo follows the mouse only: a pad session has none
  if not e or a.mode == "unstack" or a.pad then
    detachGizmo(a)
    return
  end
  local gz = Gizmos.getInstance()
  local g = a.mode == "rotate" and gz:getRotateGizmo(a.playerNum) or gz:getTranslateGizmo(a.playerNum)
  local fr = C.frame(a.rec)
  local wx, wy, wz = C.partToWorld(a.rec, fr, e.x, restY(a.rec, e) + (e.y or 0), e.z)
  g:setWorldPosition(wx, wy, wz)
  -- setRotation stores (x, z, y) (Gizmo.java:55): yaw goes last
  local gx, gy, gzr = B.gizmoEuler(B.sceneFrame(fr), e.yaw, e.rx or 0, e.rz or 0)
  g:setRotation(gx, gzr, gy)
  g:setVisible(true)
  g:setTable(a.drag)
  gz:setGizmo(a.playerNum, g)
end

-- Free-hand: the footprint centre stays on the bed, neighbours ignored.
---@param a TrailerCargo.Arrange
---@param p TrailerCargo.Pose
local function place(a, p)
  local e = a.sel
  if not e or not a.pose then return end
  local hx, hz, ox, oz = B.footprint(TrailerCargo.Bounds, e.m, a.rec.ms)
  -- pull back on rather than refuse, so a drag never sticks
  local dx, dz = B.pullOn(a.rec.bed, B.rect(p.x, p.z, p.yaw, hx, hz, ox, oz))
  p.x, p.z = p.x + dx, p.z + dz
  -- with Debug tools on the lift may go below the floor, to measure a bed
  p.y = B.clampLift(a.rec.bed, p.y, C.debug())
  p.rx, p.rz = p.rx % 360, p.rz % 360
  a.pose = p
  setPose(e, p)
  a.dirty[e.ids[1]] = true
  C.applyEntryPose(a.rec, e, 0)
  attachGizmo(a)
end

---@param a TrailerCargo.Arrange
---@param e TrailerCargo.Entry|nil
local function selectEntry(a, e)
  if a.sel and a.sel ~= e then setLift(a, a.sel, 0) end
  a.sel = e
  if e then
    a.pose = poseOf(e)
    if not a.start[e.ids[1]] then a.start[e.ids[1]] = poseOf(e) end
    -- it was the hovered item, so it is up: put it where it really is
    setLift(a, e, 0)
    if C.debug() then
      C.log(string.format("arrange select %s at %.3f %.3f lift %.3f", e.m, e.x, e.z, e.y or 0))
    end
  else
    a.pose = nil
  end
  attachGizmo(a)
end

---@param list TrailerCargo.Entry[]
---@return TrailerCargo.Entry[]
local function copyList(list)
  local out = {}
  for i = 1, #list do
    local e = list[i]
    local ids = {}
    for j = 1, #e.ids do ids[j] = e.ids[j] end
    out[i] = { m = e.m, x = e.x, z = e.z, yaw = e.yaw, ids = ids, y = e.y, rx = e.rx, rz = e.rz, free = e.free }
  end
  return out
end

-- Split the pile under the mouse; each layer stays where it was drawn.
---@param a TrailerCargo.Arrange
---@param e TrailerCargo.Entry|nil
local function unstackEntry(a, e)
  if not e or #e.ids < 2 then return end
  local layout = Tr.layoutOf(a.rec.part)
  if not a.before then a.before = copyList(layout.list) end
  local ids = {}
  for j = 1, #e.ids do ids[j] = e.ids[j] end
  if not P.unstack(layout, C.ctx(a.rec), ids[1]) then return end
  a.unstacks[#a.unstacks + 1] = ids[1]
  a.hover = nil
  for j = 1, #ids do
    local split = P.entryOf(layout, ids[j])
    if split then
      C.applyEntryPose(a.rec, split, 0)
      -- the server splits where IT has the pile, so every layer sends its place
      a.dirty[ids[j]] = true
    end
  end
  if C.debug() then C.log("arrange unstack " .. e.m .. " into " .. #ids) end
end

-- Tells one commit's moves from another's (the server's onMove).
local batchSeq = 0

-- Send every move, one command each, sharing a batch key so the server
-- accepts the rest of the batch after each move bumps the rev.
---@param a TrailerCargo.Arrange
local function commit(a)
  local player = getSpecificPlayer(a.playerNum)
  if not player then return end
  local layout = Tr.layoutOf(a.rec.part)
  batchSeq = batchSeq + 1
  -- the clock keeps a key from a previous game session from matching
  local batch = getTimestamp() * 1000 + batchSeq % 1000
  -- splits first: the moves below may name a layer only a split made free
  for i = 1, #a.unstacks do
    sendClientCommand(player, Tr.MODULE, "unstack", {
      vehicle = a.rec.id, base = layout.rev, batch = batch, id = a.unstacks[i],
    })
  end
  a.unstacks = {}
  a.before = nil
  for id in pairs(a.dirty) do
    local e = P.entryOf(layout, id)
    if e then
      sendClientCommand(player, Tr.MODULE, "move", {
        vehicle = a.rec.id, base = layout.rev, batch = batch, id = id, x = e.x, z = e.z, yaw = e.yaw,
        y = e.y or 0, rx = e.rx or 0, rz = e.rz or 0,
      })
      if C.debug() then
        C.log(string.format("arrange commit %s to %.3f %.3f yaw %.1f lift %.3f lean %.1f %.1f",
          e.m, e.x, e.z, e.yaw, e.y or 0, e.rx or 0, e.rz or 0))
      end
    end
  end
  a.dirty = {}
end

function C.stopArrange()
  local a = active
  if not a then return end
  active = nil
  if a.pad and C.padStop then C.padStop(a) end
  if a.sel then setLift(a, a.sel, 0) end
  if a.hover and a.hover ~= a.sel then setLift(a, a.hover, 0) end
  commit(a)
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
  if C.debug() then C.log("arrange ended") end
end

-- Put every touched entry back; after a split the whole list is restored.
function C.revertArrange()
  local a = active
  if not a then return end
  local layout = Tr.layoutOf(a.rec.part)
  if a.before then
    layout.list = a.before
    a.before, a.unstacks, a.dirty, a.start = nil, {}, {}, {}
    a.hover = nil
    selectEntry(a, nil)
    for i = 1, #layout.list do C.applyEntryPose(a.rec, layout.list[i], 0) end
    if C.debug() then C.log("arrange reverted, splits undone") end
    return
  end
  for id, at in pairs(a.start) do
    local e = P.entryOf(layout, id)
    if e then
      setPose(e, at)
      C.applyEntryPose(a.rec, e, 0)
      a.dirty[id] = true
    end
  end
  if a.sel then
    a.pose = poseOf(a.sel)
    attachGizmo(a)
  end
  if C.debug() then C.log("arrange reverted") end
end

-- "translate", "rotate" or "unstack" (no gizmo: a click splits a pile).
function C.setGizmoMode(mode)
  local a = active
  if not a then return end
  a.mode = mode
  if mode == "unstack" and a.sel then selectEntry(a, nil) end
  attachGizmo(a)
end

function C.gizmoMode()
  return active and active.mode or "translate"
end

function C.arrangeStatus()
  local a = active
  if not a then return "" end
  if a.mode == "unstack" then return getText("UI_TrailerCargo_ClickStack") end
  if a.sel then return getText("UI_TrailerCargo_Selected") .. " " .. tostring(a.sel.m) end
  return getText("UI_TrailerCargo_ClickItem")
end

-- Mouse to bed coordinates, on the plane of the tub floor.
---@param a TrailerCargo.Arrange
---@return number|nil bx, number|nil bz
local function mouseBed(a)
  local fr = C.frame(a.rec)
  local _, _, z = C.partToWorld(a.rec, fr, 0, a.rec.bed.floor, 0)
  local mx, my = getMouseX(), getMouseY()
  local px, _, pz = C.worldToPart(a.rec, fr, screenToIsoX(a.playerNum, mx, my, z),
    screenToIsoY(a.playerNum, mx, my, z), z)
  return px, pz
end

-- The hover pick is costly on a full bed: run it every PICK_MS only.
local PICK_MS = 40
local lastPick = 0

local function onRenderTick()
  local a = active
  if not a then return end
  if getCell():getDrag(a.playerNum) ~= a.drag then
    C.stopArrange()
    return
  end
  if not C.tracked[a.rec.id] then
    C.stopArrange()
    return
  end
  -- every frame: the stick and the held bumpers are read, not sent
  if a.pad then
    if C.padTick then C.padTick(a) end
    return
  end
  -- The gizmo owns the mouse while it is being dragged.
  if Gizmos.getInstance():isTrackingMouse() then return end
  a.dragStart = nil
  a.dragGround = nil
  local now = getTimestampMs()
  if now - lastPick < PICK_MS then return end
  lastPick = now
  local bx, bz = mouseBed(a)
  local e = nil
  if bx and bz then
    e = P.pick(Tr.layoutOf(a.rec.part), a.rec.bed, C.ctx(a.rec), bx, bz)
  end
  if e ~= a.hover then
    if a.hover and a.hover ~= a.sel then setLift(a, a.hover, 0) end
    if e and e ~= a.sel then setLift(a, e, LIFT) end
    a.hover = e
  end
end

-- The translate gizmo reports the world position of the entry's origin;
-- its height above rest is the lift, snapped to a floor or top within a
-- hair (P.snapLift).
---@param a TrailerCargo.Arrange
---@param v Vector3f
local function onTranslate(a, v)
  local e, p0 = a.sel, a.pose
  if not e or not p0 then return end
  local fr = C.frame(a.rec)
  local px, py, pz = C.worldToPart(a.rec, fr, v:x(), v:y(), v:z())
  if not px or not py or not pz then return end
  local asked = py - restY(a.rec, e)
  -- An item resting on a hump follows the bed down off it; a hump never
  -- lifts a hand-placed item (the player's rule).
  local hx, hz, ox, oz = B.footprint(TrailerCargo.Bounds, e.m, a.rec.ms)
  if a.dragGround == nil then
    local g0 = B.groundAt(a.rec.bed, B.rect(p0.x, p0.z, p0.yaw, hx, hz, ox, oz))
    a.dragGround = g0 > 0 and math.abs((p0.y or 0) - g0) <= P.SNAP and g0 or false
  end
  local g1 = B.groundAt(a.rec.bed, B.rect(px, pz, p0.yaw, hx, hz, ox, oz))
  if a.dragGround then asked = asked - a.dragGround + g1 end
  local tops = P.topsUnder(Tr.layoutOf(a.rec.part), C.ctx(a.rec), e.ids[1], px, pz, p0.yaw)
  tops[#tops + 1] = g1
  place(a, { x = px, z = pz, yaw = p0.yaw, y = P.snapLift(asked, tops), rx = p0.rx, rz = p0.rz })
end

-- The rotate gizmo reports (x, z, y) Euler degrees: the orientation at the
-- drag's START composed with the whole drag, so it is applied to the pose
-- kept from the drag's start (RotateGizmo.java:199).
---@param a TrailerCargo.Arrange
---@param v Vector3f
local function onRotate(a, v)
  local e, p0 = a.sel, a.pose
  if not e or not p0 then return end
  local s = a.dragStart
  if not s then
    s = { x = p0.x, z = p0.z, yaw = p0.yaw, y = p0.y, rx = p0.rx, rz = p0.rz }
    a.dragStart = s
  end
  local fr = C.frame(a.rec)
  local yaw, rx, rz = B.poseFromGizmo(B.sceneFrame(fr), v:x(), v:z(), v:y(), s.yaw, s.rx, s.rz)
  place(a, { x = p0.x, z = p0.z, yaw = yaw % 360, y = p0.y, rx = rx, rz = rz })
end

-- What TrailerCargo_ArrangePad drives the session with.
C.ARRANGE_LIFT = LIFT
C.arrangeRestY = restY
C.arrangePlace = place
C.arrangeSelect = selectEntry
C.arrangeUnstack = unstackEntry

---@return TrailerCargo.Arrange|nil
function C.arrangeActive()
  return active
end

---@param playerNum integer
---@param rec TrailerCargo.Rec
---@param selectId number|nil  an item to start with selected, in Move mode (the trunk menu's Arrange)
function C.startArrange(playerNum, rec, selectId)
  C.stopArrange()
  ---@type TrailerCargo.Arrange
  local a = {
    playerNum = playerNum, rec = rec, drag = {}, ui = nil, mode = "translate",
    hover = nil, sel = nil, pose = nil, dragStart = nil, start = {}, dirty = {},
    unstacks = {}, before = nil, pad = false,
  }
  -- ISObjectClickHandler stops when the hook returns true. The rest are
  -- the methods vanilla's building driver calls on any drag (a missing one
  -- crashes it). setTable wants one table, so the gizmo callbacks live here.
  a.drag.Type = "TrailerCargoCursor"
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
  a.drag.deactivate = function() C.stopArrange() end
  a.drag.onObjectLeftMouseButtonDown = function()
    if not active then return false end
    if Gizmos.getInstance():isTrackingMouse() then return true end
    if active.mode == "unstack" then
      unstackEntry(active, active.hover)
    else
      selectEntry(active, active.hover)
    end
    return true
  end
  -- Both arrive as a Vector3f: a world position, or a rotation.
  a.drag.onTranslateGizmo = function(_, v)
    if active then onTranslate(active, v) end
  end
  a.drag.onRotateGizmo = function(_, v)
    if active then onRotate(active, v) end
  end
  -- a pad's buttons go to whatever is dragged (JoyPadSetup.lua:365)
  if C.padBind then C.padBind(a.drag) end
  a.pad = C.isPadPlayer ~= nil and C.isPadPlayer(playerNum)
  active = a
  getCell():setDrag(a.drag, playerNum)
  if not a.pad then
    -- the panel opens over the click that chose "Arrange cargo"
    a.ui = TrailerCargoArrangeUI:new(playerNum, getMouseX(), getMouseY())
    a.ui:initialise()
    a.ui:addToUIManager()
  end
  if selectId then
    local e = P.entryOf(Tr.layoutOf(rec.part), selectId)
    if e then selectEntry(a, e) end
  end
  if a.pad and C.padStart then C.padStart(a) end
  if C.debug() then C.log("arrange started on " .. rec.id) end
end

Events.OnRenderTick.Add(onRenderTick)
