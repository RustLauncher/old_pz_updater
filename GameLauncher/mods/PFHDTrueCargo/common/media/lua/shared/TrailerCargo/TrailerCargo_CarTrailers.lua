-- TrailerCargo_CarTrailers: cars loaded on a car trailer, drawn as the real
-- car. Pure Lua: trailer rows, paint swatches, the saved layout (which car
-- sits where, each position's fine-tune) and the placement math. Positions
-- are the trailer's deck places; a car's W900 slot is where the W900 mod
-- stores it. Part units throughout.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.CarTrailer = TrailerCargo.CarTrailer or {}

---@class TrailerCargo.CarSlot
---@field deck number  deck height under the car's wheel midpoint
---@field z number     that midpoint along the trailer
---@field pitch number degrees, nose up +
---@field harm number|nil 0..1: how much worse a spill treats a car here (a fall from the upper deck)

---@class TrailerCargo.CarTrailerRow
---@field part string   the part whose modData holds the W900 slots (and ours)
---@field cover string  cover part prefix; the W900 slot index follows
---@field coverModels string[]|nil  model script prefixes of a cover, the slot index follows; each sits at its slot
---@field slots TrailerCargo.CarSlot[]

---@class (partial) TrailerCargo.CarTrailer
local CT = TrailerCargo.CarTrailer

-- W900 Semi-Truck [B42] (Workshop 3409472393). From CarCoverWheel<i>: the
-- wheels' bottom midway between the pairs, the pitch front pair to rear.
-- Slots 1-3 are the upper deck, about 1.8 m over 4-5.
---@type table<string, TrailerCargo.CarTrailerRow>
TrailerCargo.CarTrailers = TrailerCargo.CarTrailers or {}
TrailerCargo.CarTrailers["Base.SemiTrailerCartrailer"] = {
  part = "ATAMultiSlotWrecker", cover = "MSWCarCover",
  coverModels = { "Rotators.CarCover", "Rotators.CarCoverWheel" },
  slots = {
    { deck = 0.4855, z = 3.463, pitch = 2.40, harm = 0.6 },
    { deck = 0.3455, z = 0.103, pitch = 2.40, harm = 0.6 },
    { deck = 0.1925, z = -3.324, pitch = 2.40, harm = 0.6 },
    { deck = -1.0365, z = 0.196, pitch = -2.60 },
    { deck = -0.9200, z = -3.231, pitch = 6.43 },
  },
}

CT.MODDATA = "TrailerCargoCars"
-- sign of a model `rotate` x that lifts the nose (JOML rotateX: +z goes down)
CT.PITCH_SIGN = -1
-- how far a fine-tune may take a car from its place
CT.LIMIT = { x = 1.0, y = { -0.3, 1.0 }, z = 3.0, tilt = 30 }

---@param h number|nil
---@return number, number, number
local function cone(h, s, v)
  local a = (h or 0) * 2 * math.pi
  return s * v * math.cos(a), s * v * math.sin(a), v
end

-- The paint swatch nearest a car's colour (hue, saturation, value): nearest
-- in the HSV cone, where a grey's hue does not count.
---@param h number|nil
---@param s number|nil
---@param v number|nil
---@return string
function CT.swatch(h, s, v)
  local list = TrailerCargo.CarSwatches
  if not list or #list == 0 then return "none" end
  if not h or not s or not v then return "silver" end
  local x, y, z = cone(h, s, v)
  local best, bd = list[1][1], math.huge
  for i = 1, #list do
    local e = list[i]
    local ex, ey, ez = cone(e[2], e[3], e[4])
    local d = (x - ex) ^ 2 + (y - ey) ^ 2 + (z - ez) ^ 2
    if d < bd then best, bd = e[1], d end
  end
  return best
end

-- How a model is cloned onto the trailer, from its own shader: "paint"
-- (vanilla's vehicle shaders paint where the skin's alpha is low), "none"
-- (KI5's damn_vehicle_shader bakes the colour) or nil: draw the model from
-- its own script (wheels, glass, anything not on a vehicle shader, which
-- keeps its own texture).
---@param shader string|nil
---@return string|nil
function CT.cloneKind(shader)
  local lower = string.lower(shader or "")
  if not string.find(lower, "vehicle", 1, true) or string.find(lower, "wheel", 1, true) then return nil end
  if string.find(lower, "damn", 1, true) then return "none" end
  return "paint"
end

-- The mesh a clone names. Meshes are cached by name alone (Model.java:87),
-- so a skinned source a real car loaded first would hand the static clone
-- the wrong vertex layout: another spelling of the FILE (its lookup
-- lowercases) is a separate load. The object part keeps its case: the node
-- lookup is case-sensitive (JAssImpImporter.FindNode).
---@param mesh string
---@param isStatic boolean
---@return string
function CT.cloneMesh(mesh, isStatic)
  if isStatic then return mesh end
  local p = string.find(mesh, "|", 1, true)
  if p then return string.upper(string.sub(mesh, 1, p - 1)) .. string.sub(mesh, p) end
  return string.upper(mesh)
end

---@class TrailerCargo.CarPose
---@field x number  across the deck
---@field y number  up
---@field z number  along the deck
---@field yaw number degrees, the car's vertical spin
---@field tilt number|nil degrees, nose up +, on top of the deck's pitch

---@class TrailerCargo.CarLayout
---@field map table<integer|string, integer>  position -> W900 slot drawn there
---@field pose table<integer|string, TrailerCargo.CarPose>
---@field show table<integer|string, string>  position -> "cover" or "hidden"; absent: the car
---@field rev integer
---@field info table<integer|string, TrailerCargo.CarInfo>|nil  per W900 slot, written by the server

---@class TrailerCargo.CarInfo
---@field key string   storage id / script name: which car this describes
---@field h number|nil paint hue, saturation, value
---@field s number|nil
---@field v number|nil
---@field skin number|nil
---@field parts table<string, { item: string|false, cond: number|nil, md: table|nil }>
---@field vmd table|nil the car's own modData

-- The saved layout in a part's modData, created on first use. modData keys
-- may come back as strings after a save: both are read.
---@param md table
---@param n integer  positions on the trailer
---@return TrailerCargo.CarLayout
function CT.layoutOf(md, n)
  local L = md[CT.MODDATA]
  if type(L) ~= "table" then
    L = {}
    md[CT.MODDATA] = L
  end
  if type(L.map) ~= "table" then L.map = {} end
  if type(L.pose) ~= "table" then L.pose = {} end
  if type(L.show) ~= "table" then L.show = {} end
  L.rev = tonumber(L.rev) or 0
  for p = 1, n do
    local w = tonumber(L.map[p] or L.map[tostring(p)])
    L.map[tostring(p)] = nil
    L.map[p] = (w and w >= 1 and w <= n) and math.floor(w) or p
  end
  return L
end

-- A layout's map must stay a permutation; a broken one is reset.
---@param L TrailerCargo.CarLayout
---@param n integer
function CT.fixMap(L, n)
  local seen = {}
  for p = 1, n do
    local w = L.map[p]
    if seen[w] then
      for q = 1, n do L.map[q] = q end
      return
    end
    seen[w] = true
  end
end

---@param L TrailerCargo.CarLayout
---@param p integer
---@return TrailerCargo.CarPose
function CT.poseAt(L, p)
  local e = L.pose[p] or L.pose[tostring(p)]
  if type(e) ~= "table" then return { x = 0, y = 0, z = 0, yaw = 0, tilt = 0 } end
  return { x = tonumber(e.x) or 0, y = tonumber(e.y) or 0, z = tonumber(e.z) or 0, yaw = tonumber(e.yaw) or 0,
    tilt = tonumber(e.tilt) or 0 }
end

---@param pose TrailerCargo.CarPose
---@return TrailerCargo.CarPose
function CT.clampPose(pose)
  local lim = CT.LIMIT
  local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
  local yaw = pose.yaw % 360
  if yaw > 180 then yaw = yaw - 360 end
  return {
    x = clamp(pose.x, -lim.x, lim.x), y = clamp(pose.y, lim.y[1], lim.y[2]),
    z = clamp(pose.z, -lim.z, lim.z), yaw = yaw, tilt = clamp(pose.tilt or 0, -lim.tilt, lim.tilt),
  }
end

---@param L TrailerCargo.CarLayout
---@param p integer
---@param pose TrailerCargo.CarPose|nil  nil resets
function CT.setPose(L, p, pose)
  L.pose[tostring(p)] = nil
  if not pose then
    L.pose[p] = nil
  else
    local c = CT.clampPose(pose)
    L.pose[p] = { x = c.x, y = c.y, z = c.z, yaw = c.yaw, tilt = c.tilt }
  end
  L.rev = L.rev + 1
end

-- Two positions trade cars; each car keeps its fine-tune.
---@param L TrailerCargo.CarLayout
function CT.swap(L, a, b)
  if a == b then return false end
  local pa, pb = L.pose[a] or L.pose[tostring(a)], L.pose[b] or L.pose[tostring(b)]
  L.pose[tostring(a)], L.pose[tostring(b)] = nil, nil
  L.map[a], L.map[b] = L.map[b], L.map[a]
  L.pose[a], L.pose[b] = pb, pa
  local sa, sb = CT.showAt(L, a), CT.showAt(L, b)
  L.show[tostring(a)], L.show[tostring(b)] = nil, nil
  L.show[a] = sb ~= "car" and sb or nil
  L.show[b] = sa ~= "car" and sa or nil
  L.rev = L.rev + 1
  return true
end

-- How position p's car shows: "car", "cover" (a tarp shape, for a car too
-- big for the deck) or "hidden". The player's choice, per car.
CT.SHOWS = { "car", "cover", "hidden" }

---@param L TrailerCargo.CarLayout
---@param p integer
---@return string
function CT.showAt(L, p)
  local s = L.show and (L.show[p] or L.show[tostring(p)])
  return (s == "cover" or s == "hidden") and s or "car"
end

---@param L TrailerCargo.CarLayout
---@param p integer
---@param s string|nil  anything but "cover" or "hidden" means the car
function CT.setShow(L, p, s)
  if type(L.show) ~= "table" then L.show = {} end
  L.show[tostring(p)] = nil
  L.show[p] = (s == "cover" or s == "hidden") and s or nil
  L.rev = math.floor(tonumber(L.rev) or 0) + 1
end

---@param s string
---@return string
function CT.nextShow(s)
  for i = 1, #CT.SHOWS do
    if CT.SHOWS[i] == s then return CT.SHOWS[i % #CT.SHOWS + 1] or "car" end
  end
  return "car"
end

-- A cover is modelled at its slot, pitched with it: it turns and moves by
-- the pose alone, about the same deck point as a car there.
---@param slot TrailerCargo.CarSlot
---@return TrailerCargo.CarPlace
function CT.coverPlace(slot)
  return { k = 1, y = 0, z = 0, pivotY = slot.deck, pivotZ = slot.z, pitch = 0 }
end

-- The W900's compact reference for slot w, from the slot part's modData.
---@param part VehiclePart
---@param w integer
---@return table|nil
function CT.w900Ref(part, w)
  local msw = part:getModData().msw
  local slots = msw and msw.slots
  return slots and (slots[w] or slots[tostring(w)]) or nil
end

-- Which car a reference names: its storage id and script name.
---@return string|nil
function CT.refKey(ref)
  return ref and (tostring(ref.storageId) .. "/" .. tostring(ref.scriptName)) or nil
end

-- A script name without its module.
---@param name string
---@return string
function CT.bareName(name)
  return string.match(name, "^[^%.]+%.(.+)$") or name
end

-- A deep copy of plain data.
function CT.copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = CT.copy(v) end
  return c
end

-- The position a W900 slot's car is drawn at.
---@param L TrailerCargo.CarLayout
---@param w integer
---@return integer|nil
function CT.positionOf(L, w)
  for p, ww in pairs(L.map) do
    local n = tonumber(p)
    if ww == w and n then return math.floor(n) end
  end
  return nil
end

---@class TrailerCargo.CarPlace
---@field k number       car modelScale / trailer modelScale
---@field y number       car origin height before any turn
---@field z number       car origin along the trailer
---@field pivotY number  the deck point under the wheel midpoint
---@field pivotZ number
---@field pitch number   degrees

-- Where a car stands on a slot: the wheels' bottom on the deck, their
-- midpoint over the slot's. Wheels sit in the BODY model's frame
-- (BaseVehicle.java:4489-4515), so the body offset does not enter.
---@param slot TrailerCargo.CarSlot
---@param carMs number     the car's modelScale
---@param trailerMs number
---@param radius number    a wheel's radius, script units (before modelScale)
---@param wheelY number    that wheel's runtime offset y (after modelScale)
---@param zFront number    frontmost wheel's runtime offset z
---@param zRear number
---@return TrailerCargo.CarPlace
function CT.placeOn(slot, carMs, trailerMs, radius, wheelY, zFront, zRear)
  return {
    k = carMs / trailerMs,
    y = slot.deck + (radius * carMs - wheelY) / trailerMs,
    z = slot.z - ((zFront + zRear) / 2) / trailerMs,
    pivotY = slot.deck, pivotZ = slot.z, pitch = slot.pitch or 0,
  }
end

-- A car script's place on a slot, from its wheels (runtime offsets are
-- after the car's modelScale, the radius in TrailerCargo_Cars before it).
---@param slot TrailerCargo.CarSlot
---@param car VehicleScript
---@param crow table  the car's TrailerCargo.Cars row
---@param trailerMs number
---@return TrailerCargo.CarPlace
function CT.placeFor(slot, car, crow, trailerMs)
  local w0 = car:getWheel(0)
  local zf, zr = -1e9, 1e9
  for k = 0, car:getWheelCount() - 1 do
    local z = car:getWheel(k):getOffset():z()
    if z > zf then zf = z end
    if z < zr then zr = z end
  end
  return CT.placeOn(slot, car:getModelScale(), trailerMs, crow.wheels[w0:getId()] or 0.5, w0:getOffset():y(), zf, zr)
end

---@class TrailerCargo.CarModel
---@field ox number  offset in the car's part frame
---@field oy number
---@field oz number
---@field rx number  the model's own rotate, degrees
---@field ry number
---@field rz number
---@field scale number

-- A model's offset and rotate on the trailer: the car spins by the pose's
-- yaw about the vertical through its pivot, tips by the deck's pitch plus
-- the pose's tilt about the pivot, then shifts by the pose. Offsets and
-- meshes turn the same way: a model's `rotate` y turns it in the part frame
-- (seen in game 2026-09-27: turning the offsets by Ry(-yaw) tore the car).
---@param m TrailerCargo.CarModel
---@param pl TrailerCargo.CarPlace
---@param pose TrailerCargo.CarPose
---@return number x, number y, number z, number rx, number ry, number rz, number scale
function CT.modelAt(m, pl, pose)
  local x = pl.k * m.ox
  local y = pl.y + pl.k * m.oy - pl.pivotY
  local z = pl.z + pl.k * m.oz - pl.pivotZ
  local a = math.rad(pose.yaw or 0)
  local ca, sa = math.cos(a), math.sin(a)
  x, z = x * ca + z * sa, -x * sa + z * ca
  local pitch = pl.pitch + (pose.tilt or 0)
  local p = math.rad(pitch)
  local cp, sp = math.cos(p), math.sin(p)
  y, z = y * cp + z * sp, -y * sp + z * cp
  return x + pose.x, pl.pivotY + y + pose.y, pl.pivotZ + z + pose.z,
    m.rx + CT.PITCH_SIGN * pitch, m.ry + (pose.yaw or 0), m.rz, pl.k * m.scale
end

-- 3x3 rotations, rows of columns, M * v.
---@param A number[][]
---@param B number[][]
---@return number[][]
function CT.mul3(A, B)
  local C = {}
  for i = 1, 3 do
    C[i] = {}
    for j = 1, 3 do C[i][j] = A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j] end
  end
  return C
end
function CT.rotX(a) local c, s = math.cos(a), math.sin(a) return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
function CT.rotY(a) local c, s = math.cos(a), math.sin(a) return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end
function CT.rotZ(a) local c, s = math.cos(a), math.sin(a) return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } end

-- Degrees a, b, c with M = Rx(a) Ry(b) Rz(c), what setAngles builds
-- (Quaternionf.rotationXYZ). Heading straight up or down: z kept 0.
---@param M number[][]
---@return number, number, number
function CT.eulerXYZ(M)
  local b = math.asin(math.max(-1, math.min(1, M[1][3])))
  if math.abs(M[1][3]) > 0.9999 then return math.deg(math.atan2(M[3][2], M[2][2])), math.deg(b), 0 end
  return math.deg(math.atan2(-M[2][3], M[3][3])), math.deg(b), math.deg(math.atan2(-M[1][2], M[1][1]))
end

---@class TrailerCargo.CarSpillPose
---@field lx number  chassis origin in the trailer's physics-local frame
---@field ly number
---@field lz number
---@field R number[][]  rotation relative to the trailer

-- Where a live car goes to stand where it is drawn: its chassis origin is
-- the drawn body origin minus the car's own body offset; then the
-- trailer's body offset and modelScale, as for any part model.
---@param pl TrailerCargo.CarPlace
---@param pose TrailerCargo.CarPose
---@param cbx number  the car's runtime body offset (after its modelScale)
---@param cby number
---@param cbz number
---@param cms number  the car's modelScale
---@param tbx number  the trailer's runtime body offset
---@param tby number
---@param tbz number
---@param tms number  the trailer's modelScale
---@return TrailerCargo.CarSpillPose
function CT.spillPose(pl, pose, cbx, cby, cbz, cms, tbx, tby, tbz, tms)
  local x, y, z = CT.modelAt({ ox = -cbx / cms, oy = -cby / cms, oz = -cbz / cms, rx = 0, ry = 0, rz = 0, scale = 1 }, pl, pose)
  return {
    lx = tbx + tms * x, ly = tby + tms * y, lz = tbz + tms * z,
    R = CT.mul3(CT.rotX(-math.rad(pl.pitch + (pose.tilt or 0))), CT.rotY(math.rad(pose.yaw or 0))),
  }
end

-- addImpulse is one central force over one Bullet step of 0.01 s
-- (BaseVehicle.java:3354, WorldSimulation.java:91): force = mass x v / step
-- gives the car exactly v.
CT.SPILL_K = 1 / 0.01

local xfS, v3S
-- Scratch objects, made on first use (the offline tests load this file).
---@return Transform, Vector3f
local function scratch()
  xfS = xfS or Transform.new()
  v3S = v3S or Vector3f.new()
  return xfS, v3S
end

-- A vehicle's rotation (columns) and origin in the physics frame.
---@param v BaseVehicle
---@return number[][], number, number, number
function CT.basisOf(v)
  local xf, v3 = scratch()
  v:getWorldTransform(xf)
  local o = xf:getOrigin()
  local ox, oy, oz = o:x(), o:y(), o:z()
  local M = { {}, {}, {} }
  for j = 1, 3 do
    v3:set(j == 1 and 1 or 0, j == 2 and 1 or 0, j == 3 and 1 or 0)
    xf:transform(v3)
    M[1][j], M[2][j], M[3][j] = v3:x() - ox, v3:y() - oy, v3:z() - oz
  end
  return M, ox, oy, oz
end

-- Set a live car where it is drawn on `trailer` now; with `vel` (the
-- trailer's velocity, physics frame) also let it go with that speed. The
-- push takes effect only where the car's physics runs (not on a server).
---@param car BaseVehicle
---@param trailer BaseVehicle
---@param sp TrailerCargo.CarSpillPose
---@param vel number[]|nil
function CT.throwCar(car, trailer, sp, vel)
  local B, ox, oy, oz = CT.basisOf(trailer)
  local x = ox + B[1][1] * sp.lx + B[1][2] * sp.ly + B[1][3] * sp.lz
  local y = oy + B[2][1] * sp.lx + B[2][2] * sp.ly + B[2][3] * sp.lz
  local z = oz + B[3][1] * sp.lx + B[3][2] * sp.ly + B[3][3] * sp.lz
  local a, b, c = CT.eulerXYZ(CT.mul3(B, sp.R))
  car:setAngles(0, 0, 0)  -- setAngles skips a call whose whole degrees match
  car:setAngles(a, b, c)
  local xf = scratch()
  car:getWorldTransform(xf)
  xf:getOrigin():set(x, y, z)
  car:setWorldTransform(xf)
  if not vel then return end
  car:setPhysicsActive(true, true)
  local m = car:getMass() * CT.SPILL_K
  car:addImpulse(Vector3f.new(vel[1] * m, vel[2] * m, vel[3] * m), Vector3f.new(0, 0, 0))
end

-- A spill pose as scalars (command args carry no nested tables) and back.
---@param sp TrailerCargo.CarSpillPose
---@param out table
function CT.packPose(sp, out)
  out.lx, out.ly, out.lz = sp.lx, sp.ly, sp.lz
  for i = 1, 3 do for j = 1, 3 do out["r" .. i .. j] = sp.R[i][j] end end
  return out
end

---@param t table
---@return TrailerCargo.CarSpillPose|nil
function CT.unpackPose(t)
  local R = {}
  for i = 1, 3 do
    local row = {}
    for j = 1, 3 do
      local v = tonumber(t["r" .. i .. j])
      if not v then return nil end
      row[j] = v
    end
    R[i] = row
  end
  local lx, ly, lz = tonumber(t.lx), tonumber(t.ly), tonumber(t.lz)
  if not lx or not ly or not lz then return nil end
  return { lx = lx, ly = ly, lz = lz, R = R }
end

-- Which of a car's damage shells a part shows on the trailer, by its
-- condition: the engine's own thresholds (BaseVehicle.checkDamage: under 60
-- light, under 40 heavy). Drawn as a second model with that texture
-- (TrailerCargo_CarDraw, trailercargo_cardmg_<swatch>).
---@param condition number|nil
---@return integer 0, 1 or 2
function CT.wearLevel(condition)
  if not condition then return 0 end
  if condition < 40 then return 2 end
  if condition < 60 then return 1 end
  return 0
end

-- Panels whose condition the body shell shows.
CT.BODY_PANELS = { "Door", "EngineDoor", "TrunkDoor", "Bumper", "Fender", "Panel", "Hood", "Trunklid" }

---@param pid string
local function isPanel(pid)
  for _, k in ipairs(CT.BODY_PANELS) do
    if string.find(pid, k, 1, true) then return true end
  end
  return false
end

-- The body shell's condition: the average of its installed panels', 100
-- with none known.
---@param parts table<string, { item: string|false, cond: number|nil }>|nil
---@return number
function CT.bodyCondition(parts)
  local sum, n = 0.0, 0
  for pid, p in pairs(parts or {}) do
    if p.item and p.cond and isPanel(pid) then
      sum, n = sum + p.cond, n + 1
    end
  end
  return n > 0 and sum / n or 100
end

-- A broken pane or lamp is left out: missing glass reads as broken.
---@param pid string
---@param condition number|nil
function CT.brokenGlass(pid, condition)
  if condition ~= 0 then return false end
  local lower = string.lower(pid)
  return string.find(lower, "window", 1, true) ~= nil or string.find(lower, "windshield", 1, true) ~= nil
    or string.find(lower, "light", 1, true) ~= nil
end

---@class TrailerCargo.SpillTier
---@field name string
---@field chance number  share of spilled cars
---@field keep [number, number]  each part keeps this share of its condition
---@field shatter number  chance a glass part breaks outright

-- How badly a spilled car is hurt, rolled once per car: rarely a wreck,
-- mostly light or normal (the player's shape, 2026-09-27). Each part rolls
-- its own share in the tier; glass (windows, lights) may shatter, else
-- keeps the share squared.
---@type TrailerCargo.SpillTier[]
CT.SPILL_TIERS = {
  { name = "wrecked", chance = 0.03, keep = { 0.05, 0.30 }, shatter = 0.90 },
  { name = "heavy", chance = 0.12, keep = { 0.25, 0.55 }, shatter = 0.65 },
  { name = "normal", chance = 0.40, keep = { 0.45, 0.75 }, shatter = 0.35 },
  { name = "light", chance = 0.45, keep = { 0.70, 0.92 }, shatter = 0.15 },
}

-- `harm` (a slot's) squeezes the roll toward the worst tiers: at 0.6 no
-- car from the upper deck gets off lightly.
---@param r number  uniform 0..1
---@param harm number|nil
---@return TrailerCargo.SpillTier
function CT.spillTier(r, harm)
  r = r * (1 - math.max(0, math.min(1, harm or 0)))
  local acc = 0.0
  for i = 1, #CT.SPILL_TIERS do
    local t = CT.SPILL_TIERS[i]
    acc = acc + t.chance
    if r < acc then return t end
  end
  return CT.SPILL_TIERS[#CT.SPILL_TIERS]
end

-- How hard a thrown car hit, from its fastest speed on the way down (m/s):
-- a lower-deck slide at walking pace hurts little, a car flung at road speed
-- mostly normal, a heavy one in four; never certain to wreck.
CT.IMPACT_HARM_MAX = 0.5
---@param peak number
---@return number harm  0..IMPACT_HARM_MAX
function CT.impactHarm(peak)
  return math.max(0, math.min(CT.IMPACT_HARM_MAX, (peak - 4) / 12))
end

-- Where a car sliding off a tipping trailer takes the hit: it lands on its
-- side or roof, so the outer shell and glass first, the mechanics little
-- (the player's call, 2026-09-27). `weight` scales the damage a part takes;
-- glass may shatter (the tier's chance times `shatter`). First match wins,
-- by part id, case ignored.
---@type { [1]: string[], weight: number, shatter: number|nil }[]
CT.SPILL_ZONES = {
  { { "windshield", "window" }, weight = 1.5, shatter = 1.2 },
  { { "light" }, weight = 1.4, shatter = 1.0 },
  { { "door", "hood", "trunklid", "bumper", "fender", "roof", "mirror", "panel", "armor" }, weight = 1.25 },
  { { "tire", "suspension", "brake" }, weight = 0.6 },
  { { "muffler", "gastank" }, weight = 0.5 },
  { { "engine", "battery", "radiator", "heater" }, weight = 0.3 },
  { { "seat", "radio", "glovebox", "trunk", "truckbed" }, weight = 0.2 },
}
CT.SPILL_DEFAULT = { weight = 0.5 }

---@param pid string
---@return { weight: number, shatter: number|nil }
function CT.spillZone(pid)
  local lower = string.lower(pid)
  for _, z in ipairs(CT.SPILL_ZONES) do
    for _, k in ipairs(z[1]) do
      if string.find(lower, k, 1, true) then return z end
    end
  end
  return CT.SPILL_DEFAULT
end

-- A part's condition after the fall; 0 with `shattered` for broken glass.
---@param tier TrailerCargo.SpillTier
---@param condition number
---@param pid string
---@param rKeep number   uniform 0..1
---@param rBreak number  uniform 0..1
---@param scale number|nil  the sandbox damage scale, 1 when nil
---@return integer condition, boolean shattered
function CT.spillCondition(tier, condition, pid, rKeep, rBreak, scale)
  scale = scale or 1
  local zone = CT.spillZone(pid)
  if zone.shatter and rBreak < tier.shatter * zone.shatter * scale then return 0, true end
  local keep = tier.keep[1] + (tier.keep[2] - tier.keep[1]) * rKeep
  keep = math.max(0, 1 - (1 - keep) * zone.weight * scale)
  -- the epsilon keeps 0.7 * 0.7 * 100 at 49, not 48.999...
  return math.floor(condition * keep + 1e-6), false
end

-- The pivot of a position in part units, where the arrange gizmo sits.
---@param pl TrailerCargo.CarPlace
---@param pose TrailerCargo.CarPose
function CT.pivotAt(pl, pose)
  return pose.x, pl.pivotY + pose.y, pl.pivotZ + pose.z
end
