-- TrailerCargo_Bed: bed geometry in PART units (the frame a part model's
-- `offset` is written in: the body-model frame before modelScale). Pure Lua.
-- Bounds rows are tiles horizontally, floors vertically; converted here only.
---@class (partial) TrailerCargo
---@field Bed TrailerCargo.Bed
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class TrailerCargo.Bed
local B = TrailerCargo.Bed or {}
TrailerCargo.Bed = B

local sin, cos, abs, max, min = math.sin, math.cos, math.abs, math.max, math.min
local asin, atan2 = math.asin, math.atan2
local RAD = math.pi / 180

-- hx, hz, ox, oz (tiles: half-extents along model X/Z, centre offset),
-- bottom, top (floors), 7th `true` on a default box.
---@alias TrailerCargo.BoundsEntry [number, number, number, number, number, number, boolean?]

-- Calibrated in game: bed direction of model +X at yaw 0, handedness of
-- model Z, sense of the yaw.
B.AXIS_MAP = { mx = 1, mz = 0, hand = 1, signYaw = 1 }
-- Sign between physics-local x and part x (calibrated in arrange mode).
B.SIGN_X = 1
B.FLOORS_TO_TILES = 2.25
-- Gap between packed items, tiles.
B.GAP_TILES = 0.03
B.LONG_RATIO = 2.5
-- Smallest half-extent a footprint is packed with, tiles (thin models).
B.MIN_HALF = 0.05
-- A model the table lacks still draws, in a plausible box.
---@type TrailerCargo.BoundsEntry
B.DEFAULT_BOX = { 0.15, 0.15, 0, 0, 0, 0.12, true }

-- The bounds key for a model name as TrailerCargo_Trunk.modelOf returns it.
---@param m string|nil  model script name
---@return string|nil  the bare name, module stripped
function B.key(m)
  if m == nil then return nil end
  local dot = string.find(m, ".", 1, true)
  if dot then return string.sub(m, dot + 1) end
  return m
end

-- True when the name came from the weapon-sprite fallback: the engine
-- rewrites a WorldStaticModel to its full type but never a WeaponSprite.
---@param m string
function B.isWeaponModel(m)
  return string.find(m, ".", 1, true) == nil
end

-- The bounds row of the model AS DRAWN: a weapon model reads its "W:" row
-- (after the weapon transform, lying down), not the as-authored one.
---@param bounds table<string, TrailerCargo.BoundsEntry>
---@param m string
---@return TrailerCargo.BoundsEntry
function B.entry(bounds, m)
  local k = B.key(m)
  if k == nil then return B.DEFAULT_BOX end
  local e
  if B.isWeaponModel(m) then e = bounds["W:" .. k] end
  e = e or bounds[k] or B.DEFAULT_BOX
  local lay = TrailerCargo.LayDown
  if lay and lay[m] then return B.laidDown(e) end
  return e
end

-- The box tipped a quarter turn about model X (TrailerCargo_LayDown):
-- (x, y, z) becomes (x, -z, y).
---@param e TrailerCargo.BoundsEntry
---@return TrailerCargo.BoundsEntry
function B.laidDown(e)
  local hx, hz, ox, oz = e[1], e[2], e[3], e[4]
  local y0, y1 = e[5] * B.FLOORS_TO_TILES, e[6] * B.FLOORS_TO_TILES
  return {
    hx,                                   -- untouched
    (y1 - y0) / 2,                        -- the height lies down
    ox,
    (y1 + y0) / 2,
    -(oz + hz) / B.FLOORS_TO_TILES,       -- the depth stands up
    -(oz - hz) / B.FLOORS_TO_TILES,
  }
end

-- Footprint half-extents along model X/Z and centre offset, part units.
-- The X offset is NEGATED: the render mirrors the part frame along x.
---@return number hx, number hz, number ox, number oz
function B.footprint(bounds, m, ms)
  local e = B.entry(bounds, m)
  return max(e[1], B.MIN_HALF) / ms, max(e[2], B.MIN_HALF) / ms, -e[3] / ms, e[4] / ms
end

---@return number  lowest vertex relative to the origin, part units (usually <= 0)
function B.bottom(bounds, m, ms)
  return B.entry(bounds, m)[5] * B.FLOORS_TO_TILES / ms
end

---@return number  model height, part units
function B.height(bounds, m, ms)
  local e = B.entry(bounds, m)
  return (e[6] - e[5]) * B.FLOORS_TO_TILES / ms
end

-- Part units every item rests above the floor: undersides are not flat.
B.REST_CLEAR = 0.03

-- Part units from one layer of a pile to the next: the model's height,
-- or less for a model that nests (TrailerCargo.StackPitch, floors).
function B.pitch(bounds, m, ms)
  local nest = TrailerCargo.StackPitch and TrailerCargo.StackPitch[m]
  if nest then return nest * B.FLOORS_TO_TILES / ms end
  return B.height(bounds, m, ms)
end

-- Part-offset y for a layer: the origin sits -bottom above the floor, then
-- one pitch per layer beneath it.
function B.layerY(bed, bounds, m, ms, layer)
  return bed.floor + B.REST_CLEAR - B.bottom(bounds, m, ms) + layer * B.pitch(bounds, m, ms)
end

-- Bed-space unit directions of model X and model Z for a yaw in degrees.
---@return number uxx, number uxz, number uzx, number uzz
function B.axes(yaw)
  local a = B.AXIS_MAP.signYaw * yaw * RAD
  local c, s = cos(a), sin(a)
  local uxx = B.AXIS_MAP.mx * c - B.AXIS_MAP.mz * s
  local uxz = B.AXIS_MAP.mx * s + B.AXIS_MAP.mz * c
  local h = B.AXIS_MAP.hand
  return uxx, uxz, -h * uxz, h * uxx
end

---@class TrailerCargo.Rect
---@field cx number  footprint centre, bed x
---@field cz number  footprint centre, bed z
---@field uxx number
---@field uxz number
---@field uzx number
---@field uzz number
---@field hx number
---@field hz number
---@field minx number
---@field maxx number
---@field minz number
---@field maxz number

-- Oriented footprint of a model whose ORIGIN is at (x, z).
---@return TrailerCargo.Rect
function B.rect(x, z, yaw, hx, hz, ox, oz)
  local uxx, uxz, uzx, uzz = B.axes(yaw)
  local cx = x + ox * uxx + oz * uzx
  local cz = z + ox * uxz + oz * uzz
  local rx = hx * abs(uxx) + hz * abs(uzx)
  local rz = hx * abs(uxz) + hz * abs(uzz)
  return {
    cx = cx, cz = cz, uxx = uxx, uxz = uxz, uzx = uzx, uzz = uzz, hx = hx, hz = hz,
    minx = cx - rx, maxx = cx + rx, minz = cz - rz, maxz = cz + rz,
  }
end

local function separated(dx, dz, ax, az, ha, b)
  local d = abs(dx * ax + dz * az)
  return d > ha + b.hx * abs(b.uxx * ax + b.uxz * az) + b.hz * abs(b.uzx * ax + b.uzz * az) + 1e-9
end

-- Separating-axis test. Touching edges count as overlap.
---@param a TrailerCargo.Rect
---@param b TrailerCargo.Rect
function B.overlaps(a, b)
  if a.maxx < b.minx or b.maxx < a.minx or a.maxz < b.minz or b.maxz < a.minz then return false end
  local dx, dz = b.cx - a.cx, b.cz - a.cz
  if separated(dx, dz, a.uxx, a.uxz, a.hx, b) then return false end
  if separated(dx, dz, a.uzx, a.uzz, a.hz, b) then return false end
  if separated(-dx, -dz, b.uxx, b.uxz, b.hx, a) then return false end
  if separated(-dx, -dz, b.uzx, b.uzz, b.hz, a) then return false end
  return true
end

---@param r TrailerCargo.Rect
function B.inside(bed, r)
  return r.minx >= bed.x[1] - 1e-6 and r.maxx <= bed.x[2] + 1e-6
    and r.minz >= bed.z[1] - 1e-6 and r.maxz <= bed.z[2] + 1e-6
end

-- Where a PLAYER may put an item: its centre on the bed (may overhang the
-- rail). The packer keeps to B.inside.
---@param r TrailerCargo.Rect
function B.holds(bed, r)
  return r.cx >= bed.x[1] - 1e-6 and r.cx <= bed.x[2] + 1e-6
    and r.cz >= bed.z[1] - 1e-6 and r.cz <= bed.z[2] + 1e-6
end

-- The shift that brings a footprint's centre back onto the bed.
---@param r TrailerCargo.Rect
---@return number dx, number dz
function B.pullOn(bed, r)
  return max(bed.x[1] - r.cx, 0.0) + min(bed.x[2] - r.cx, 0.0),
    max(bed.z[1] - r.cz, 0.0) + min(bed.z[2] - r.cz, 0.0)
end

-- A bed's humps as rects, cached per bed row.
local NO_HUMPS = {}
local humpCache = {}
---@return TrailerCargo.Rect[]
function B.humpRects(bed)
  local hs = bed.humps
  if not hs then return NO_HUMPS end
  local out = humpCache[bed]
  if not out then
    out = {}
    for i = 1, #hs do
      local h = hs[i]
      out[i] = B.rect((h.x[1] + h.x[2]) / 2, (h.z[1] + h.z[2]) / 2, 0,
        (h.x[2] - h.x[1]) / 2, (h.z[2] - h.z[1]) / 2, 0, 0)
    end
    humpCache[bed] = out
  end
  return out
end

-- The height above the floor a footprint rests at: the top of the highest
-- hump it touches, else 0. Part units.
---@param r TrailerCargo.Rect
function B.groundAt(bed, r)
  local hs = bed.humps
  if not hs then return 0.0 end
  local hr, g = B.humpRects(bed), 0.0
  for i = 1, #hr do
    if B.overlaps(hr[i], r) then g = max(g, hs[i].top - bed.floor) end
  end
  return g
end

-- True when one of `cs` (covers or tarps) is installed; an entry with
-- `items` counts only for those item types.
---@param cs TrailerCargo.Cover[]|nil
---@param installedType fun(partId: string): string|nil
local function anyInstalled(cs, installedType)
  if not cs then return false end
  for i = 1, #cs do
    local c = cs[i]
    local t = installedType(c.part)
    if t then
      if not c.items then return true end
      for k = 1, #c.items do
        if c.items[k] == t then return true end
      end
    end
  end
  return false
end

-- True when an installed cover hides the bed.
---@param installedType fun(partId: string): string|nil
function B.covered(bed, installedType)
  return anyInstalled(bed.covers, installedType)
end

-- True when the load cannot spill: a cover or a flat tarp is installed.
---@param installedType fun(partId: string): string|nil
function B.sealed(bed, installedType)
  return anyInstalled(bed.covers, installedType) or anyInstalled(bed.tarps, installedType)
end

-- Inside the bed, off the humps and clear of every rect except rects[skip].
---@param rects TrailerCargo.Rect[]
---@param r TrailerCargo.Rect
---@param skip integer|nil
function B.fits(bed, rects, r, skip)
  if not B.inside(bed, r) then return false end
  local hr = B.humpRects(bed)
  for i = 1, #hr do
    if B.overlaps(hr[i], r) then return false end
  end
  for i = 1, #rects do
    if i ~= skip and B.overlaps(rects[i], r) then return false end
  end
  return true
end

function B.isLong(hx, hz)
  local lo, hi = min(hx, hz), max(hx, hz)
  return lo > 0 and hi / lo >= B.LONG_RATIO
end

-- The yaw that lays the model's long axis along bed z.
function B.lengthwiseYaw(hx, hz)
  if hz >= hx then return 0 end
  return 90
end

-- The yaw that lays the long axis ACROSS the bed (TrailerCargo.FloorFirst).
function B.acrossYaw(hx, hz)
  if hx >= hz then return 0 end
  return 90
end

-- Rx(90) composed onto a fixup: Rx is rotateXYZ's outermost term, so a
-- plain add on the X angle.
---@param fix [number, number, number]|[number, number, number, number, number, number]|nil
---@return [number, number, number, number, number, number]
function B.composeLayDown(fix)
  if not fix then return { 90, 0, 0, 0, 0, 0 } end
  return { fix[1] + 90, fix[2], fix[3], fix[4] or 0, fix[5] or 0, fix[6] or 0 }
end

-- ------------------------------------------------------------ 3x3 matrices
-- Row-major, column vectors, as JOML's rotateXYZ (= Rx * Ry * Rz).
---@alias TrailerCargo.Mat3 number[]

---@return TrailerCargo.Mat3
function B.rotX3(deg)
  local c, s = cos(deg * RAD), sin(deg * RAD)
  return { 1, 0, 0, 0, c, -s, 0, s, c }
end

---@return TrailerCargo.Mat3
function B.rotY3(deg)
  local c, s = cos(deg * RAD), sin(deg * RAD)
  return { c, 0, s, 0, 1, 0, -s, 0, c }
end

---@return TrailerCargo.Mat3
function B.rotZ3(deg)
  local c, s = cos(deg * RAD), sin(deg * RAD)
  return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

---@param A TrailerCargo.Mat3
---@param C TrailerCargo.Mat3
---@return TrailerCargo.Mat3
function B.mul3(A, C)
  return {
    A[1] * C[1] + A[2] * C[4] + A[3] * C[7], A[1] * C[2] + A[2] * C[5] + A[3] * C[8], A[1] * C[3] + A[2] * C[6] + A[3] * C[9],
    A[4] * C[1] + A[5] * C[4] + A[6] * C[7], A[4] * C[2] + A[5] * C[5] + A[6] * C[8], A[4] * C[3] + A[5] * C[6] + A[6] * C[9],
    A[7] * C[1] + A[8] * C[4] + A[9] * C[7], A[7] * C[2] + A[8] * C[5] + A[9] * C[8], A[7] * C[3] + A[8] * C[6] + A[9] * C[9],
  }
end

---@param A TrailerCargo.Mat3
---@return TrailerCargo.Mat3
function B.transpose3(A)
  return { A[1], A[4], A[7], A[2], A[5], A[8], A[3], A[6], A[9] }
end

---@param A TrailerCargo.Mat3
function B.det3(A)
  return A[1] * (A[5] * A[9] - A[6] * A[8]) - A[2] * (A[4] * A[9] - A[6] * A[7]) + A[3] * (A[4] * A[8] - A[5] * A[7])
end

-- Rx(ex) * Ry(ey) * Rz(ez), degrees.
---@return TrailerCargo.Mat3
function B.fromXYZ(ex, ey, ez)
  return B.mul3(B.rotX3(ex), B.mul3(B.rotY3(ey), B.rotZ3(ez)))
end

-- M read back as XYZ Euler degrees: M = Rx(ex) * Ry(ey) * Rz(ez).
---@param M TrailerCargo.Mat3
---@return number ex, number ey, number ez
function B.eulerXYZ3(M)
  local ey = asin(max(-1, min(1, M[3])))
  local ex, ez
  if abs(cos(ey)) > 1e-6 then
    ex, ez = atan2(-M[6], M[9]), atan2(-M[2], M[1])
  else
    ex, ez = atan2(M[8], M[5]), 0
  end
  return ex / RAD, ey / RAD, ez / RAD
end

-- M read back as YXZ Euler degrees: M = Ry(ey) * Rx(ex) * Rz(ez), the bed
-- pose order (yaw, then the lean).
---@param M TrailerCargo.Mat3
---@return number ey, number ex, number ez
function B.eulerYXZ3(M)
  local ex = asin(max(-1, min(1, -M[6])))
  local ey, ez
  if abs(cos(ex)) > 1e-6 then
    ey, ez = atan2(M[3], M[9]), atan2(M[4], M[5])
  else
    ey, ez = atan2(-M[7], M[1]), 0
  end
  return ey / RAD, ex / RAD, ez / RAD
end

-- ------------------------------------------------------------ orientation

-- Sign of the lean between the bed frame and the `rotate` field's frame,
-- calibrated in game per standing ring.
B.TILT_SIGN = { x = 1, z = 1 }

-- The rotation the engine must apply for a yaw, a lean and the model's
-- fixup, as a matrix; nil for a plain yaw. The field is read as
-- rotateXYZ(rx, -ry, -rz), so a fixup cannot just have the yaw added.
-- THE MIRROR: a sub-model draws as translate(-ox, oy, oz) * M * v
-- (BaseVehicle.java:4462), so the part frame is the draw frame mirrored by
-- Sx. A bed pose P = Ry(-a) Rx(rx) Rz(rz) draws as M = Sx P Sx Fix =
-- Ry(a) Rx(rx) Rz(-rz) Fix.
---@return TrailerCargo.Mat3|nil M, number a  the signed yaw
local function fieldMatrix(yaw, fix, lay, rx, rz)
  local a = yaw * B.AXIS_MAP.signYaw
  if lay then fix = B.composeLayDown(fix) end
  rx, rz = rx or 0, rz or 0
  if not fix and rx == 0 and rz == 0 then return nil, a end
  local M = B.rotY3(a)
  if rx ~= 0 then M = B.mul3(M, B.rotX3(B.TILT_SIGN.x * rx)) end
  if rz ~= 0 then M = B.mul3(M, B.rotZ3(-B.TILT_SIGN.z * rz)) end
  if fix then M = B.mul3(M, B.fromXYZ(fix[1], fix[2], fix[3])) end
  return M, a
end

---@param yaw number  degrees
---@param fix [number, number, number]|nil  XYZ Euler degrees
---@param lay boolean|nil  tipped on its side (TrailerCargo_LayDown)
---@param rx number|nil  lean about the item's X, degrees
---@param rz number|nil  lean about the item's Z, degrees
---@return number rx, number ry, number rz
function B.rotateField(yaw, fix, lay, rx, rz)
  local M, a = fieldMatrix(yaw, fix, lay, rx, rz)
  -- the plain yaw: the field's y is read negated
  if not M then return 0, -a, 0 end
  local ex, ey, ez = B.eulerXYZ3(M)
  return ex, -ey, -ez
end

-- The `rotate` field plus the `offset` shift that puts the mesh where its
-- bounds row says: vanilla translates by minus the `attachment world`
-- offset before the fixup, a sub-model does not, so it moves by
-- -s * M * off (x negated by the render).
---@param s number  the sub-model's scale (ITEM_SCALE / modelScale)
---@return number rx, number ry, number rz, number dx, number dy, number dz
function B.pose(yaw, fix, lay, rx, rz, s)
  local M, a = fieldMatrix(yaw, fix, lay, rx, rz)
  local ex, ey, ez = 0.0, -a, 0.0
  if M then
    ex, ey, ez = B.eulerXYZ3(M)
    ey, ez = -ey, -ez
  end
  local offx, offy, offz = 0, 0, 0
  if fix then
    if lay then fix = B.composeLayDown(fix) end
    offx, offy, offz = fix[4] or 0, fix[5] or 0, fix[6] or 0
  end
  if offx == 0 and offy == 0 and offz == 0 then return ex, ey, ez, 0, 0, 0 end
  local mx, my, mz
  if M then
    mx = M[1] * offx + M[2] * offy + M[3] * offz
    my = M[4] * offx + M[5] * offy + M[6] * offz
    mz = M[7] * offx + M[8] * offy + M[9] * offz
  else
    -- the plain yaw: the engine applies Ry(a)
    local c, sn = cos(a * RAD), sin(a * RAD)
    mx, my, mz = c * offx + sn * offz, offy, -sn * offx + c * offz
  end
  return ex, ey, ez, s * mx, -s * my, -s * mz
end

-- The bed-frame rotation about the vertical that turns model X the way
-- B.axes says a yaw does, as the angle of a right-handed Ry.
function B.thetaOfYaw(yaw)
  local uxx, uxz = B.axes(yaw)
  return atan2(-uxz, uxx) / RAD
end

-- Inverse of thetaOfYaw.
function B.yawOfTheta(theta)
  local uxx, uxz = cos(theta * RAD), -sin(theta * RAD)
  local m = B.AXIS_MAP
  local c, s = m.mx * uxx + m.mz * uxz, m.mx * uxz - m.mz * uxx
  return atan2(s, c) / RAD * m.signYaw
end

-- An entry's orientation in the bed frame: yaw about the vertical, then
-- its lean about its own X and Z.
---@return TrailerCargo.Mat3
function B.bedRotation(yaw, rx, rz)
  return B.mul3(B.rotY3(B.thetaOfYaw(yaw)), B.mul3(B.rotX3(rx or 0), B.rotZ3(rz or 0)))
end

-- ------------------------------------------------------------ the gizmo

-- Physics units per floor. `getWorldPos` adds a local height WITHOUT this
-- division (the gizmo divides, TranslateGizmo:218): probes must correct.
B.WORLD_FLOOR = 2.44949

-- A trailer's frame from getWorldPos probes: world = o + lx X + ly Y + lz Z,
-- world-z components already divided by WORLD_FLOOR.
---@class TrailerCargo.Frame
---@field ox number
---@field oy number
---@field oz number
---@field xx number
---@field xy number
---@field xz number
---@field yx number
---@field yy number
---@field yz number
---@field zx number
---@field zy number
---@field zz number

-- Local coordinates of a world point, or nil when the frame is degenerate.
---@param fr TrailerCargo.Frame
---@return number|nil lx, number|nil ly, number|nil lz
function B.solve3(fr, wx, wy, wz)
  local A = { fr.xx, fr.yx, fr.zx, fr.xy, fr.yy, fr.zy, fr.xz, fr.yz, fr.zz }
  local det = B.det3(A)
  if abs(det) < 1e-9 then return nil, nil, nil end
  local dx, dy, dz = wx - fr.ox, wy - fr.oy, wz - fr.oz
  local lx = B.det3({ dx, fr.yx, fr.zx, dy, fr.yy, fr.zy, dz, fr.yz, fr.zz }) / det
  local ly = B.det3({ fr.xx, dx, fr.zx, fr.xy, dy, fr.zy, fr.xz, dz, fr.zz }) / det
  local lz = B.det3({ fr.xx, fr.yx, dx, fr.xy, fr.yy, dy, fr.xz, fr.yz, dz }) / det
  return lx, ly, lz
end

-- Tiles from a point in part units to the bed's rectangle, 0 over it
-- (arrange reach: a pickup's origin is mid-cab).
---@param bed { x: number[], z: number[] }  a bed row, or any rectangle
---@return number
function B.bedDistance(bed, px, pz, ms)
  local dx = max(bed.x[1] - px, 0, px - bed.x[2])
  local dz = max(bed.z[1] - pz, 0, pz - bed.z[2])
  return math.sqrt(dx * dx + dz * dz) * ms
end

-- The world point of local coordinates.
---@param fr TrailerCargo.Frame
---@return number wx, number wy, number wz
function B.frameWorld(fr, lx, ly, lz)
  return fr.ox + lx * fr.xx + ly * fr.yx + lz * fr.zx,
    fr.oy + lx * fr.xy + ly * fr.yy + lz * fr.zy,
    fr.oz + lx * fr.xz + ly * fr.yz + lz * fr.zz
end

-- The trailer's local axes in the gizmo's scene frame (scene x = world x,
-- y = up in physics units, z = -world y; Scene.setGizmoTransforms). Its
-- determinant is the physics frame's handedness.
---@param fr TrailerCargo.Frame
---@return TrailerCargo.Mat3
function B.sceneFrame(fr)
  local K = B.WORLD_FLOOR
  return { fr.xx, fr.yx, fr.zx, fr.xz * K, fr.yz * K, fr.zz * K, -fr.xy, -fr.yy, -fr.zy }
end

local function handedness(Tm)
  return { B.det3(Tm) < 0 and -1 or 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

-- `Gizmo:setRotation` angles that put the rings on the item's own axes (a
-- mirror T flips the X column). Scene XYZ Euler; the caller swaps the last
-- two, the engine stores (rx, rz, ry).
---@param Tm TrailerCargo.Mat3
---@return number ex, number ey, number ez
function B.gizmoEuler(Tm, yaw, rx, rz)
  local G = B.mul3(Tm, B.mul3(B.bedRotation(yaw, rx, rz), handedness(Tm)))
  return B.eulerXYZ3(G)
end

-- Sense of a ring drag against the item. One wrong ring: fix its TILT_SIGN.
B.RING_SIGN = 1

-- The bed pose after a ring drag: the gizmo composes the drag on the right,
-- so its delta from the start pose is a turn about one of the item's axes.
---@param Tm TrailerCargo.Mat3
---@param ex number  scene XYZ Euler the gizmo reports
---@param ey number
---@param ez number
---@param yaw0 number  the pose the drag started from
---@param rx0 number
---@param rz0 number
---@return number yaw, number rx, number rz
function B.poseFromGizmo(Tm, ex, ey, ez, yaw0, rx0, rz0)
  local D = handedness(Tm)
  local R0 = B.bedRotation(yaw0, rx0, rz0)
  local G0 = B.mul3(Tm, B.mul3(R0, D))
  local delta = B.mul3(B.transpose3(G0), B.fromXYZ(ex, ey, ez))
  if B.RING_SIGN < 0 then delta = B.transpose3(delta) end
  local R = B.mul3(R0, B.mul3(D, B.mul3(delta, D)))
  local theta, rx, rz = B.eulerYXZ3(R)
  return B.yawOfTheta(theta), rx, rz
end

-- ------------------------------------------------------------ height

-- How far above the rail an item's underside may be lifted, part units.
B.LIFT_MARGIN = 0.15

function B.maxLift(bed)
  return bed.rail - bed.floor + B.LIFT_MARGIN
end

-- How far below the bed floor a probe may push an item, part units.
B.PROBE_DEPTH = 0.5
-- How far below its resting place a player may sink an item, part units.
B.SINK_DEPTH = 0.25

-- A lift is measured from the resting place on the floor. `probe` (Debug
-- tools) goes deeper to read a floor correction; the server clamps at
-- SINK_DEPTH. A hump never lifts a hand-placed item (the player's rule).
function B.clampLift(bed, y, probe)
  local lo = probe and -B.PROBE_DEPTH or -B.SINK_DEPTH
  return max(lo, min(y, B.maxLift(bed)))
end

-- physics-local (tiles; x right, z forward) <-> part units. local =
-- bodyOffset + modelScale * part, with SIGN_X on the x axis.
function B.localToPart(lx, lz, bodyX, bodyZ, ms)
  return B.SIGN_X * (lx - bodyX) / ms, (lz - bodyZ) / ms
end

function B.partToLocal(px, pz, bodyX, bodyZ, ms)
  return bodyX + B.SIGN_X * px * ms, bodyZ + pz * ms
end

-- Coefficients u, v with (wx, wy) = o + u * a + v * b, or nil when a and b
-- are parallel.
function B.solve2(ox, oy, ax, ay, bx, by, wx, wy)
  local det = ax * by - ay * bx
  if abs(det) < 1e-9 then return nil end
  local dx, dy = wx - ox, wy - oy
  return (dx * by - dy * bx) / det, (ax * dy - ay * dx) / det
end
