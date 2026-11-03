-- TrailerCargo_Server: the only writer of a trailer's layout. In single
-- player sendClientCommand reaches OnClientCommand too: one code path.
-- Every write bumps `rev` then transmits the trunk part's modData.
---@class (partial) TrailerCargo
---@field Server TrailerCargo.Server
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class TrailerCargo.Server
local S = TrailerCargo.Server or {}
TrailerCargo.Server = S

local Beds, Bounds = TrailerCargo.Beds, TrailerCargo.Bounds
local P, Tr = TrailerCargo.Pack, TrailerCargo.Trunk

S.MAX_NEW = 16

-- vehicle id -> { unfit, batch, batchRev, opts, triedKey, debug }. unfit
-- and triedKey stop a full bed retrying its overflow on every check.
local memo = {}

-- Tiles: a command from a player further away is stale or forged.
S.REACH = 16

local function log(msg)
  print("[TrailerCargo/server] " .. msg)
end

local function rng()
  return ZombRandFloat(0, 1)
end

local function memoOf(id)
  local m = memo[id]
  if not m then
    m = { unfit = {} }
    memo[id] = m
  end
  return m
end

---@class TrailerCargo.CheckOpts
---@field auto boolean  false: Free mode, the placing client's setting

---@param vehicle BaseVehicle
---@param opts TrailerCargo.CheckOpts|nil
---@return TrailerCargo.PackCtx
local function ctxFor(vehicle, opts)
  return {
    bounds = Bounds, capOf = TrailerCargo.stackCap, ms = vehicle:getScript():getModelScale(),
    rng = rng, maxNew = S.MAX_NEW, auto = opts and opts.auto,
  }
end

---@param vehicle BaseVehicle
---@param part VehiclePart
---@param layout TrailerCargo.Layout
local function commit(vehicle, part, layout)
  layout.rev = (layout.rev or 0) + 1
  vehicle:transmitPartModData(part)
end

-- Prune what left, pack what arrived. Without `opts` the trailer's last
-- ones are reused, so a bystander's mode never decides someone's drop.
-- The size floor is each client's render filter, never applied here.
---@param vehicle BaseVehicle
---@param opts TrailerCargo.CheckOpts|nil
---@param debug boolean|nil  log what this reconcile saw and did (the client's Debug tools option rides its check)
---@return boolean changed
function S.reconcile(vehicle, opts, debug)
  local bed = Beds[vehicle:getScriptName()]
  if not bed then
    if debug then log("reconcile " .. vehicle:getId() .. ": no bed for " .. tostring(vehicle:getScriptName())) end
    return false
  end
  local part, container = Tr.partOf(vehicle, bed)
  if not part or not container then
    if debug then log("reconcile " .. vehicle:getId() .. ": no part or container " .. tostring(bed.part)) end
    return false
  end
  local layout = Tr.layoutOf(part)
  local mm = memoOf(vehicle:getId())
  if opts then mm.opts = opts end
  opts = mm.opts
  -- ids whose item left the trunk leave the hidden and shown lists with it
  local present = {}
  for id in pairs(Tr.itemsById(container)) do present[id] = true end
  local forgot = P.forget(layout, present)
  local trunk = Tr.list(container, layout)
  -- items the bed already rejected are held back
  local held, n = {}, #trunk
  for i = 1, #trunk do
    local t = trunk[i]
    if mm.unfit[t.id] and not P.entryOf(layout, t.id) then
      held[t.id] = true
      n = n - 1
    end
  end
  -- a repack that failed for this trunk and layout is not retried
  local key = tostring(layout.rev) .. "/" .. #trunk .. "/" .. #layout.list
  local ctx = ctxFor(vehicle, opts)
  ctx.noRepack = mm.triedKey == key
  local changed, unfit = P.reconcile(bed, layout, trunk, ctx, held)
  for i = 1, #unfit do mm.unfit[unfit[i]] = true end
  mm.triedKey = (not changed and #unfit > 0) and key or nil
  if debug then
    log(string.format("reconcile %d: trunk %d offered %d held %d (unfit before) mode %s changed %s unfit now %d forgot %s entries %d rev %s%s",
      vehicle:getId(), #trunk, n, #trunk - n, (opts and opts.auto == false) and "free" or "auto",
      tostring(changed), #unfit, tostring(forgot), #layout.list, tostring(layout.rev), ctx.noRepack and " (repack skipped, tried)" or ""))
    for i = 1, #unfit do
      local t
      for j = 1, #trunk do
        if trunk[j].id == unfit[i] then t = trunk[j] end
      end
      if t then
        log(string.format("  unfit id %d %s w %.1f size %.3f", unfit[i], t.m, t.w or 0, P.sizeOf(t.m, t.w, ctx)))
      end
    end
  end
  -- any change can free space: forget what did not fit
  if changed or forgot then
    mm.unfit = {}
    commit(vehicle, part, layout)
  end
  return changed or forgot
end

-- A move is accepted against the rev its client saw, or the rev its own
-- batch (one Done) last left; any other change in between drops it.
---@param vehicle BaseVehicle
---@param part VehiclePart
local function onMove(vehicle, bed, part, args)
  local layout = Tr.layoutOf(part)
  local mm = memoOf(vehicle:getId())
  local sameBatch = args.batch ~= nil and args.batch == mm.batch and layout.rev == mm.batchRev
  if args.base ~= layout.rev and not sameBatch then
    log("move dropped: base " .. tostring(args.base) .. " rev " .. tostring(layout.rev))
    return
  end
  if type(args.id) ~= "number" or type(args.x) ~= "number"
    or type(args.z) ~= "number" or type(args.yaw) ~= "number" then
    return
  end
  -- lift and leans are optional (older clients)
  local y, rx, rz = args.y, args.rx, args.rz
  if (y ~= nil and type(y) ~= "number") or (rx ~= nil and type(rx) ~= "number")
    or (rz ~= nil and type(rz) ~= "number") then
    return
  end
  if P.move(layout, bed, ctxFor(vehicle), args.id, args.x, args.z, args.yaw, y, rx, rz) then
    commit(vehicle, part, layout)
    mm.batch, mm.batchRev = args.batch, layout.rev
  else
    log("move dropped: outside the bed")
  end
end

-- An unstack, batched like moves.
---@param vehicle BaseVehicle
---@param part VehiclePart
local function onUnstack(vehicle, part, args)
  local layout = Tr.layoutOf(part)
  local mm = memoOf(vehicle:getId())
  local sameBatch = args.batch ~= nil and args.batch == mm.batch and layout.rev == mm.batchRev
  if args.base ~= layout.rev and not sameBatch then
    log("unstack dropped: base " .. tostring(args.base) .. " rev " .. tostring(layout.rev))
    return
  end
  if type(args.id) ~= "number" then return end
  if P.unstack(layout, ctxFor(vehicle), args.id) then
    commit(vehicle, part, layout)
    mm.batch, mm.batchRev = args.batch, layout.rev
  else
    log("unstack dropped: " .. tostring(args.id) .. " is in no pile")
  end
end

-- A hide or show, batched like moves; reconciles at once.
---@param vehicle BaseVehicle
---@param bed TrailerCargo.BedEntry
---@param part VehiclePart
---@param container ItemContainer
local function onHide(vehicle, bed, part, container, args)
  local layout = Tr.layoutOf(part)
  local mm = memoOf(vehicle:getId())
  local sameBatch = args.batch ~= nil and args.batch == mm.batch and layout.rev == mm.batchRev
  if args.base ~= layout.rev and not sameBatch then
    log("hide dropped: base " .. tostring(args.base) .. " rev " .. tostring(layout.rev))
    return
  end
  if type(args.id) ~= "number" or type(args.on) ~= "boolean" then return end
  local did
  if args.on then
    did = P.hide(layout, ctxFor(vehicle), args.id)
  else
    local item = Tr.itemsById(container)[args.id]
    local m = item and Tr.modelOf(item)
    if m then
      did = P.show(layout, bed, ctxFor(vehicle), args.id, m)
    else
      did = P.setHidden(layout, args.id, false)
    end
  end
  if mm.debug then
    local e = P.entryOf(layout, args.id)
    log(string.format("%s id %d: %s, parked %s, now %s", args.on and "hide" or "show", args.id, did and "done" or "no change",
      (layout.parked and layout.parked[args.id]) and "yes" or "no", e and string.format("at %.3f %.3f free %s", e.x, e.z, tostring(e.free)) or "off the bed"))
  end
  if did then
    commit(vehicle, part, layout)
    -- the batch's next command is checked against the rev the reconcile leaves
    S.reconcile(vehicle, nil, mm.debug)
    mm.batch, mm.batchRev = args.batch, layout.rev
  end
end

-- A tipped trailer drops its whole load past the rail on the low side,
-- once per flip (`spilled` holds until upright). The server checks the
-- angle itself; a cover or tarp (Bed.sealed) holds the load in.
S.SPILL_DOT = 0.5
local SCATTER = 0.7   -- tiles, radius of the scatter around the landing point
local PUSH = 0.8      -- tiles past the rail
local wp0, wp1, wp = Vector3f.new(), Vector3f.new(), Vector3f.new()

---@param vehicle BaseVehicle
---@param bed TrailerCargo.BedEntry
---@param part VehiclePart
---@param container ItemContainer
function S.spill(vehicle, bed, part, container, _args)
  local layout = Tr.layoutOf(part)
  if layout.spilled or #layout.list == 0 then return end
  if not TrailerCargo.Sandbox.itemSpill() then
    log(string.format("spill refused for %d: off in the sandbox options", vehicle:getId()))
    return
  end
  local dot = vehicle:getUpVectorDot()
  if dot > S.SPILL_DOT then
    log(string.format("spill refused for %d: up vector %.2f", vehicle:getId(), dot))
    return
  end
  if TrailerCargo.Bed.sealed(bed, Tr.installedType(vehicle)) then
    log(string.format("spill refused for %d: a cover or tarp holds the load in", vehicle:getId()))
    return
  end
  layout.spilled = true
  local ms = vehicle:getScript():getModelScale()
  local body = vehicle:getScript():getModelOffset()
  vehicle:getWorldPos(0, 0, 0, wp0)
  vehicle:getWorldPos(1, 0, 0, wp1)
  local side = (wp1:z() - wp0:z()) < 0 and 1 or -1
  local items = Tr.itemsById(container)
  local z = math.floor(vehicle:getZ())
  local dropped = 0
  for i = 1, #layout.list do
    local e = layout.list[i]
    for j = 1, #e.ids do
      local item = items[e.ids[j]]
      if item then
        local lx, lz = TrailerCargo.Bed.partToLocal(e.x, e.z, body:x(), body:z(), ms)
        lx = lx + side * (bed.x[2] * ms + PUSH)
        vehicle:getWorldPos(lx, 0, lz, wp)
        local a = ZombRandFloat(0, 6.2831853)
        local r = ZombRandFloat(0, SCATTER)
        local wx, wy = wp:x() + math.cos(a) * r, wp:y() + math.sin(a) * r
        local sq = getCell():getGridSquare(math.floor(wx), math.floor(wy), z)
        if not sq or not sq:isFree(false) then
          -- blocked landing square: drop beside the trailer instead
          sq = vehicle:getSquare()
          if sq then
            wx, wy = sq:getX() + ZombRandFloat(0.2, 0.8), sq:getY() + ZombRandFloat(0.2, 0.8)
          end
        end
        -- no square at all: the item stays in the trunk
        if sq then
          sendRemoveItemFromContainer(container, item)
          container:Remove(item)
          sq:AddWorldInventoryItem(item, wx - sq:getX(), wy - sq:getY(), 0)
          dropped = dropped + 1
        end
      end
    end
  end
  layout.list = {}
  memoOf(vehicle:getId()).unfit = {}
  commit(vehicle, part, layout)
  log(string.format("spilled %d items from %d to side %d, up vector %.2f", dropped, vehicle:getId(), side, dot))
end

-- Same shape as S.spill so onClientCommand dispatches both alike.
---@param vehicle BaseVehicle
---@param part VehiclePart
function S.upright(vehicle, _bed, part, _container, _args)
  local layout = Tr.layoutOf(part)
  if not layout.spilled then return end
  layout.spilled = false
  commit(vehicle, part, layout)
  log("upright again: " .. vehicle:getId())
end

-- Car trailers (TrailerCargo_CarTrailers). The W900 mod keeps each loaded
-- car's full snapshot in global ModData the server never sends; what a
-- client needs to draw a car (paint, skin, installed parts and their data)
-- is copied into our key on the slot part, which transmitPartModData
-- carries to every client.
local CT = TrailerCargo.CarTrailer

-- Tells two cars of one model in one slot apart; the ref cannot.
local function snapPrint(snap)
  return string.format("%s:%s:%.3f,%.3f,%.3f", tostring(snap.keyId), tostring(snap.skin),
    tonumber(snap.h) or -1, tonumber(snap.s) or -1, tonumber(snap.v) or -1)
end

-- Copy every loaded slot's snapshot, once per car.
---@param part VehiclePart
---@param L TrailerCargo.CarLayout
---@param n integer
---@return boolean changed
local function syncCars(part, L, n)
  local ok, got = pcall(function() return ModData.get("MSW_VehicleStorage_v2") end)
  ---@type table|nil
  local root = ok and type(got) == "table" and got or nil
  L.info = type(L.info) == "table" and L.info or {}
  local changed = false
  for w = 1, n do
    local ref = CT.w900Ref(part, w)
    local base = CT.refKey(ref)
    local have = L.info[w] or L.info[tostring(w)]
    if not base then
      if have then
        L.info[w], L.info[tostring(w)] = nil, nil
        changed = true
      end
    else
      local store = root and root.trailers and ref.storageId and root.trailers[ref.storageId]
      local snap = store and store.slots and (store.slots[w] or store.slots[tostring(w)])
      local key = snap and (base .. "|" .. snapPrint(snap))
      if snap and (not have or have.key ~= key) then
        local parts = {}
        for pid, p in pairs(snap.parts or {}) do
          if type(p) == "table" then
            parts[pid] = { item = p.InventoryItem or false, cond = p.Condition, md = CT.copy(p.modData) }
          end
        end
        L.info[tostring(w)] = nil
        L.info[w] = {
          key = key, h = snap.h, s = snap.s, v = snap.v, skin = snap.skin,
          parts = parts, vmd = CT.copy(snap.vehicleModData),
        }
        changed = true
      end
    end
  end
  return changed
end

-- A tipped car trailer loses its cars (the player's call, 2026-09-27: with
-- damage). Each is unloaded through the W900 mod's own launchVehicle, so
-- its storage stays whole, then thrown from the deck: set on the pose it is
-- drawn at, in the trailer's current frame, with the trailer's speed, for
-- physics to drop (CT.throwCar). Single player throws directly. A server
-- has no Bullet: it poses the car, hands it to the reporting client as a
-- collide (the engine's own handover when a driver bumps a parked car) and
-- that client throws it. A car the trailer cannot draw (no TrailerCargo_Cars
-- row) is set down beside the trailer instead: the placed spill.
S.CAR_SPILL_DOT = 0.7   -- the client asks past 50 degrees (up 0.64)

-- The placed spill: a random spot in a band out from the trailer's centre
-- line (tiles) on the side the deck faces, beyond the lower deck's for the
-- upper deck, within ALONG of the car's place; each try widens the band.
-- The car faces along the trailer, twisted by up to TWIST degrees. No two
-- closer than APART: a car just launched is on its squares only after the
-- next update, so the W900's own free-space check cannot see it.
S.CAR_SPILL_OUT = { 3.0, 3.0 }        -- lower deck: from, width
S.CAR_SPILL_OUT_UPPER = { 6.0, 3.5 }  -- upper deck
S.CAR_SPILL_TRIES = 12
S.CAR_SPILL_TWIST = { 35, 60 }        -- lower, upper
S.CAR_SPILL_APART = 3.0
S.CAR_SPILL_ALONG = 2.0
-- A thrown car leaves its spawn square the same tick: any free square
-- within this ring will do (tiles, widened per try).
S.CAR_THROW_RING = { 4.0, 0.5 }
S.CAR_THROW_TRIES = 36

-- Turn a car upright to face world yaw `want` (radians, atan2 of y over x).
-- The engine's Euler y has its own zero and sense: both are read off the
-- car itself (two setAngles, its forward axis measured each time). A
-- tipped trailer's own getAngleY is no heading at all (cars came off at 90).
---@param car BaseVehicle
---@param want number
local function faceCar(car, want)
  local a, b = Vector3f.new(), Vector3f.new()
  local function yaw()
    car:getWorldPos(0, 0, 0, a)
    car:getWorldPos(0, 0, 1, b)
    return math.atan2(b:y() - a:y(), b:x() - a:x())
  end
  car:setAngles(0, 0, 0)
  local y0 = yaw()
  car:setAngles(0, 90, 0)
  local turn = math.sin(yaw() - y0)
  if math.abs(turn) < 0.5 then
    log("car spill: could not read a car's heading; it keeps 90")
    return
  end
  car:setAngles(0, (turn > 0 and 1 or -1) * math.deg(want - y0), 0)
end

-- Where W900 slot w's car is drawn, as a CarSpillPose; nil for a car the
-- trailer cannot draw.
---@return TrailerCargo.CarSpillPose|nil
local function drawnPose(vehicle, row, part, L, w, pos)
  local ref = CT.w900Ref(part, w)
  local name = ref and ref.scriptName
  if not name then return nil end
  local sm = getScriptManager()
  local car = sm:getVehicle(name) or sm:getVehicle("Base." .. name)
  local crow = TrailerCargo.Cars[CT.bareName(name)]
  if not car or not crow or car:getWheelCount() == 0 then return nil end
  local ts = vehicle:getScript()
  local pl = CT.placeFor(row.slots[pos], car, crow, ts:getModelScale())
  local cb, tb = car:getModelOffset(), ts:getModelOffset()
  return CT.spillPose(pl, CT.poseAt(L, pos), cb:x(), cb:y(), cb:z(), car:getModelScale(), tb:x(), tb:y(), tb:z(),
    ts:getModelScale())
end

---@param car BaseVehicle
---@param vehicle BaseVehicle  the trailer
---@param sp TrailerCargo.CarSpillPose
---@param player IsoPlayer
local function handOff(car, vehicle, sp, player)
  car:authorizationServerCollide(player:getOnlineID(), true)
  sendServerCommand(player, Tr.MODULE, "carThrow", CT.packPose(sp, { car = car:getId(), trailer = vehicle:getId() }))
end

-- The W900 launch makes the car with the global addVehicleDebug
-- (MSW_Common_Commands.lua:2289); wrapped for the call, it hands us that car.
-- A car is on its square only after the next update, so a scan misses it.
---@return BaseVehicle|nil
local function launch(player, args)
  local orig = addVehicleDebug
  local spawned = nil
  addVehicleDebug = function(...)
    local v = orig(...)
    spawned = v
    return v
  end
  local ok, err = pcall(triggerEvent, "OnClientCommand", "msw", "launchVehicle", player, args)
  addVehicleDebug = orig
  if not ok then log("car spill: the W900 launch failed: " .. tostring(err)) end
  return spawned
end

-- One damage tier per car (CT.SPILL_TIERS), each part weighted by where a
-- rollover hits (CT.SPILL_ZONES). A shattered window goes through
-- VehicleWindow.damage: glass item gone, smash sound, broken glass.
---@param car BaseVehicle
---@param harm number|nil  the slot's (an upper deck falls harder)
---@return string tier
local function wreck(car, harm)
  local tier = CT.spillTier(ZombRandFloat(0, 1), harm)
  local scale = TrailerCargo.Sandbox.carDamage()
  if scale <= 0 then return "unharmed (sandbox)" end
  for i = 0, car:getPartCount() - 1 do
    local p = car:getPartByIndex(i)
    local c = p:getCondition()
    if c > 0 then
      local window = p:getWindow()
      local nc, shattered = CT.spillCondition(tier, c, p:getId(), ZombRandFloat(0, 1), ZombRandFloat(0, 1), scale)
      if shattered and window and window:isHittable() then
        window:damage(c)
      else
        p:setCondition(nc)
        car:transmitPartCondition(p)
      end
    end
  end
  return tier.name
end

-- Damage comes when the car has landed: at rest (under REST_SPEED for
-- REST_TICKS) or WRECK_MAX ticks on, never before WRECK_DELAY: the W900
-- launch re-applies the car's saved part conditions 70 ticks later
-- (MSW_Common_Commands.lua:1158-1188) over anything done sooner. The tier
-- follows the fastest speed seen on the way down (CT.impactHarm); where
-- none was seen (a placed car, a server that never learnt the speed) the
-- slot's own harm.
S.WRECK_DELAY = 90
S.WRECK_MAX = 360
S.REST_SPEED = 0.5
S.REST_TICKS = 10
---@type { car: BaseVehicle, harm: number|nil, slot: integer, age: integer, peak: number, rest: integer }[]
local wrecks = {}

local function onWreckTick()
  if #wrecks == 0 then return end
  local keep = {}
  for _, e in ipairs(wrecks) do
    e.age = e.age + 1
    e.car:getLinearVelocity(wp)
    local speed = math.sqrt(wp:x() ^ 2 + wp:y() ^ 2 + wp:z() ^ 2)
    if speed > e.peak then e.peak = speed end
    e.rest = speed < S.REST_SPEED and e.rest + 1 or 0
    if e.age < S.WRECK_DELAY or (e.rest < S.REST_TICKS and e.age < S.WRECK_MAX) then
      keep[#keep + 1] = e
    elseif e.car:getCurrentSquare() then
      local harm = e.peak > S.REST_SPEED and CT.impactHarm(e.peak) or e.harm
      log(string.format("car %s from slot %d: %s (peak %.1f m/s, harm %.2f, %d ticks)", e.car:getScriptName(), e.slot,
        wreck(e.car, harm), e.peak, harm or 0, e.age))
    end
  end
  wrecks = keep
end

-- The trailer's axes in the world, flattened, for the placed spill: `out`
-- is where the deck faces if the trailer lies on its side, else its lower
-- side; `along` runs the length of the trailer. On its side the local x
-- points up or down, so x alone would drop the cars into the trailer.
---@param vehicle BaseVehicle
---@return number dx, number dy, number ax, number ay
local function spillAxes(vehicle)
  vehicle:getWorldPos(0, 0, 0, wp0)
  local ox, oy, oz = wp0:x(), wp0:y(), wp0:z()
  local function axis(lx, ly, lz)
    vehicle:getWorldPos(lx, ly, lz, wp1)
    return wp1:x() - ox, wp1:y() - oy, wp1:z() - oz
  end
  ---@return number, number, number
  local function flat(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 1e-6 then return 0, 0, 0 end
    return x / l, y / l, l
  end
  local yx, yy = axis(0, 1, 0)
  local dx, dy, hl = flat(yx, yy)
  local xx, xy, xz = axis(1, 0, 0)
  local side = xz < 0 and 1 or -1
  if hl < 0.5 then dx, dy = flat(side * xx, side * xy) end
  local zx, zy = axis(0, 0, 1)
  local ax, ay = flat(zx, zy)
  return dx, dy, ax, ay
end

---@param vehicle BaseVehicle
---@param row TrailerCargo.CarTrailerRow
---@param part VehiclePart
---@param player IsoPlayer|nil
local function carSpill(vehicle, row, part, player)
  if not TrailerCargo.Sandbox.carSpill() then
    log(string.format("car spill refused for %d: off in the sandbox options", vehicle:getId()))
    return
  end
  local dot = vehicle:getUpVectorDot()
  if dot > S.CAR_SPILL_DOT then
    log(string.format("car spill refused for %d: up vector %.2f", vehicle:getId(), dot))
    return
  end
  local n = #row.slots
  local L = CT.layoutOf(part:getModData(), n)
  local script = vehicle:getScript()
  local ms, body = script:getModelScale(), script:getModelOffset()
  local dx, dy, ax, ay = spillAxes(vehicle)
  local physics = not isServer()
  vehicle:getLinearVelocity(wp)
  local vel = { wp:x(), wp:y(), wp:z() }
  local spilled, thrown = 0, 0
  local used = {}
  local function free(x, y)
    for _, u in ipairs(used) do
      if (u[1] - x) ^ 2 + (u[2] - y) ^ 2 < S.CAR_SPILL_APART ^ 2 then return false end
    end
    return true
  end
  for w = 1, n do
    local pos = CT.positionOf(L, w) or w
    ---@cast pos integer
    local slot = row.slots[pos]
    ---@cast slot TrailerCargo.CarSlot
    -- read before the launch: it clears the slot
    local sp = CT.w900Ref(part, w) and (physics or player) and drawnPose(vehicle, row, part, L, w, pos) or nil
    local _, lz = TrailerCargo.Bed.partToLocal(0, slot.z, body:x(), body:z(), ms)
    vehicle:getWorldPos(0, 0, lz, wp)
    local bx, by = wp:x(), wp:y()
    local upper = slot.harm ~= nil
    local band = upper and S.CAR_SPILL_OUT_UPPER or S.CAR_SPILL_OUT
    local twist = upper and S.CAR_SPILL_TWIST[2] or S.CAR_SPILL_TWIST[1]
    -- a square the W900 may spawn the car on, per try
    local function square(t)
      if sp then
        local a, r = ZombRandFloat(0, 2 * math.pi), S.CAR_THROW_RING[1] + t * S.CAR_THROW_RING[2]
        return math.floor(bx + r * math.cos(a)), math.floor(by + r * math.sin(a))
      end
      local out = band[1] + ZombRandFloat(0, band[2] + t * 0.25)
      local along = ZombRandFloat(-S.CAR_SPILL_ALONG, S.CAR_SPILL_ALONG)
      return math.floor(bx + dx * out + ax * along), math.floor(by + dy * out + ay * along)
    end
    local done = not CT.w900Ref(part, w)
    local t = 0
    while not done and t < (sp and S.CAR_THROW_TRIES or S.CAR_SPILL_TRIES) do
      t = t + 1
      local x, y = square(t)
      if sp or free(x, y) then
        local car = launch(player, { trailer = vehicle:getId(), slot = w, x = x, y = y })
        if not CT.w900Ref(part, w) then
          done = true
          spilled = spilled + 1
          used[#used + 1] = { x, y }
          if not car then
            log("car spill: slot " .. w .. " unloaded but its car was not seen")
          else
            if sp and physics then
              CT.throwCar(car, vehicle, sp, vel)
            elseif sp and player then
              CT.throwCar(car, vehicle, sp, nil)
              handOff(car, vehicle, sp, player)
            else
              -- upright now (the launch copies the trailer's angles)
              faceCar(car, math.atan2(ay, ax) + math.rad(ZombRandFloat(-twist, twist)))
            end
            if sp then thrown = thrown + 1 end
            wrecks[#wrecks + 1] = { car = car, harm = slot.harm, slot = w, age = 0, peak = 0, rest = 0 }
          end
        end
      end
    end
    if not done then log(string.format("car spill: no room beside %d for slot %d", vehicle:getId(), w)) end
  end
  log(string.format("spilled %d cars from %d toward %.2f %.2f, up vector %.2f; %d thrown from the deck at %.1f m/s",
    spilled, vehicle:getId(), dx, dy, dot, thrown, math.sqrt(vel[1] ^ 2 + vel[2] ^ 2 + vel[3] ^ 2)))
end

---@param vehicle BaseVehicle
---@param row TrailerCargo.CarTrailerRow
local function onCarCommand(vehicle, row, command, args, player)
  local part = vehicle:getPartById(row.part)
  if not part then return end
  local n = #row.slots
  local L = CT.layoutOf(part:getModData(), n)
  local changed = false
  if command == "carSync" then
    changed = syncCars(part, L, n)
  elseif command == "carSpill" then
    -- the W900 launch transmits what it changes
    carSpill(vehicle, row, part, player)
  elseif command == "carPose" then
    local p = tonumber(args.pos)
    if p and p >= 1 and p <= n then
      CT.setPose(L, math.floor(p), {
        x = tonumber(args.x) or 0, y = tonumber(args.y) or 0, z = tonumber(args.z) or 0, yaw = tonumber(args.yaw) or 0,
        tilt = tonumber(args.tilt) or 0,
      })
      changed = true
    end
  elseif command == "carShow" then
    local p = tonumber(args.pos)
    if p and p >= 1 and p <= n then
      CT.setShow(L, math.floor(p), args.show)
      changed = true
    end
  elseif command == "carSwap" then
    local a, b = tonumber(args.a), tonumber(args.b)
    if a and b and a >= 1 and b >= 1 and a <= n and b <= n then
      changed = CT.swap(L, math.floor(a), math.floor(b))
    end
  elseif command == "carReset" then
    local p = tonumber(args.pos) or 0
    for q = 1, n do
      if p == 0 or p == q then CT.setPose(L, q, nil) end
    end
    changed = true
  end
  if changed then
    CT.fixMap(L, n)
    vehicle:transmitPartModData(part)
  end
end

-- Trailers the W900 just loaded a car onto: synced a tick later, after its
-- own handler stored the snapshot.
local loadedOnto = {}

local function onLoadedTick()
  for id in pairs(loadedOnto) do
    loadedOnto[id] = nil
    local vehicle = getVehicleById(id)
    local carRow = vehicle and TrailerCargo.CarTrailers[vehicle:getScriptName()]
    if carRow then onCarCommand(vehicle, carRow, "carSync", {}, nil) end
  end
end

local function onClientCommand(module, command, player, args)
  if module == "msw" and command == "loadVehicle" then
    local id = type(args) == "table" and tonumber(args.trailer)
    if id then loadedOnto[math.floor(id)] = true end
    return
  end
  if module ~= Tr.MODULE then return end
  if type(args) ~= "table" or type(args.vehicle) ~= "number" then return end
  local vehicle = getVehicleById(math.floor(args.vehicle))
  if not vehicle then return end
  local carRow = TrailerCargo.CarTrailers[vehicle:getScriptName()]
  -- a sync only copies what is loaded: any client drawing the trailer asks;
  -- a spill checks the angle itself, the driver may sit far up a long rig
  if carRow and (command == "carSync" or command == "carSpill") then
    onCarCommand(vehicle, carRow, command, args, player)
    return
  end
  -- the server's own idea of where the player is, against its own vehicle
  if player then
    local dx, dy = player:getX() - vehicle:getX(), player:getY() - vehicle:getY()
    if dx * dx + dy * dy > S.REACH * S.REACH then return end
  end
  if carRow then
    onCarCommand(vehicle, carRow, command, args, player)
    return
  end
  local bed = Beds[vehicle:getScriptName()]
  if not bed then return end
  local part, container = Tr.partOf(vehicle, bed)
  if not part or not container then return end
  if command == "check" then
    -- remembered so flagless commands (hide, move) log too
    memoOf(vehicle:getId()).debug = args.debug == true
    S.reconcile(vehicle, args.auto ~= nil and { auto = args.auto == true } or nil, args.debug == true)
  elseif command == "move" then
    onMove(vehicle, bed, part, args)
  elseif command == "unstack" then
    onUnstack(vehicle, part, args)
  elseif command == "hide" then
    onHide(vehicle, bed, part, container, args)
  elseif command == "spill" then
    S.spill(vehicle, bed, part, container, args)
  elseif command == "upright" then
    S.upright(vehicle, bed, part, container, args)
  end
end

-- In multiplayer the server does the transfer (ISTransferAction) and the
-- client hook never runs: reconcile after a settle longer than the
-- client's 250 ms, so the client's check (with its mode) lands first.
local SERVER_SETTLE_MS = 600
---@type table<number, number>  vehicle id -> when its trunk last changed
local due = {}
local transferWrapped = false

local function wrapServerTransfer()
  if transferWrapped or not isServer() or not ISTransferAction or not ISTransferAction.transferItem then return end
  transferWrapped = true
  local vanilla = ISTransferAction.transferItem
  local function bedOf(container)
    local part = container and container:getVehiclePart()
    local vehicle = part and part:getVehicle()
    if vehicle and Beds[vehicle:getScriptName()] then return vehicle:getId() end
    return nil
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  ISTransferAction.transferItem = function(self, character, item, srcContainer, destContainer, dropSquare)
    -- the stub omits self; the returned item is passed on
    ---@diagnostic disable-next-line: param-type-mismatch
    local result = vanilla(self, character, item, srcContainer, destContainer, dropSquare)
    local src, dst = bedOf(srcContainer), bedOf(destContainer)
    local now = getTimestampMs()
    if src then due[src] = now end
    if dst then due[dst] = now end
    return result
  end
end

local function onServerTick()
  if not transferWrapped then return end
  local now = getTimestampMs()
  for id, at in pairs(due) do
    if now - at >= SERVER_SETTLE_MS then
      due[id] = nil
      local vehicle = getVehicleById(math.floor(id))
      if vehicle then S.reconcile(vehicle) end
    end
  end
end

-- Forget unloaded vehicles' memos. getVehicles() is a HashSet: iterate it.
local function onEveryOneMinute()
  local alive = {}
  local it = getCell():getVehicles():iterator()
  while it:hasNext() do
    local v = it:next()
    alive[v:getId()] = true
  end
  local drop, n = {}, 0
  for id in pairs(memo) do
    if not alive[id] then
      n = n + 1
      drop[n] = id
    end
  end
  for i = 1, n do memo[drop[i]] = nil end
end

Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnServerStarted.Add(wrapServerTransfer)
Events.OnGameStart.Add(wrapServerTransfer)
Events.OnTick.Add(onServerTick)
Events.OnTick.Add(onWreckTick)
Events.OnTick.Add(onLoadedTick)
