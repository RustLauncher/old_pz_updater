-- TrailerCargo_Track: which trailers we draw, when we look at them. Once a
-- second: walk the loaded vehicles (a HashSet: iterator(), no get(i)),
-- track or drop, redraw on a rev change, round-robin one safety check.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local Beds, P, Tr = TrailerCargo.Beds, TrailerCargo.Pack, TrailerCargo.Trunk

---@type table<number, TrailerCargo.Rec>
C.tracked = C.tracked or {}
---@type number[]
C.order = C.order or {}

local PASS_MS = 1000
local REACH2 = 16          -- 4 tiles, squared: the container UI's reach
local lastPass = 0
local rr = 0
local dirty = {}
local dirtyAny = false

---@return IsoPlayer|nil
function C.localPlayer()
  for i = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(i)
    if p then return p end
  end
  return nil
end

-- Logged once per script name: a bed row naming a part the vehicle lacks.
local noPart = {}

---@param vehicle BaseVehicle
---@return TrailerCargo.Rec|nil
local function track(vehicle, bed)
  local part, container = Tr.partOf(vehicle, bed)
  if not part or not container then
    local name = vehicle:getScriptName()
    if not noPart[name] then
      noPart[name] = true
      C.log(name .. ": bed row names part " .. tostring(bed.part)
        .. (part and " but it has no container" or " but the vehicle has no such part") .. "; nothing drawn")
    end
    return nil
  end
  local script = vehicle:getScript()
  local off = script:getModelOffset()
  ---@type TrailerCargo.Rec
  local rec = {
    id = vehicle:getId(), vehicle = vehicle, bed = bed, part = part, container = container,
    ms = script:getModelScale(), body = { x = off:x(), y = off:y(), z = off:z() },
    rev = -1, layers = {}, serial = 0, lastSig = "",
    v0 = Vector3f.new(), v1 = Vector3f.new(), v2 = Vector3f.new(),
  }
  rec.covered = C.coveredNow(rec)
  C.tracked[rec.id] = rec
  C.order[#C.order + 1] = rec.id
  if C.debug() then C.log("tracking " .. vehicle:getScriptName() .. " id " .. rec.id) end
  return rec
end

-- A cover is installed: nothing drawn, the layout kept.
---@param rec TrailerCargo.Rec
function C.coveredNow(rec)
  return TrailerCargo.Bed.covered(rec.bed, Tr.installedType(rec.vehicle))
end

local function untrack(id)
  C.tracked[id] = nil
  dirty[id] = nil
  for i = #C.order, 1, -1 do
    if C.order[i] == id then table.remove(C.order, i) end
  end
end

-- After asking the server, poll every tick this long for its answer.
local PENDING_MS = 3000
-- Quiet time after the last container update before the check goes out.
local SETTLE_MS = 250
local dirtyAt = 0

-- Local diff; ask the server when what we see changed, plus once on first
-- sight. `own`: this client's player changed the trunk, so the check
-- carries the placement mode.
---@param rec TrailerCargo.Rec
---@param own boolean|nil
function C.check(rec, own)
  if C.transferBusy(rec) then return end
  local layout = Tr.layoutOf(rec.part)
  local _, nRemoved, added = P.diff(layout, Tr.list(rec.container, layout))
  local sig = tostring(layout.rev) .. "/" .. nRemoved .. "/" .. #added
  local first = rec.lastSig == ""
  if (first or nRemoved > 0 or #added > 0) and sig ~= rec.lastSig then
    local player = C.localPlayer()
    -- no player yet (early load): leave the signature so a later pass asks
    if not player then return end
    local args = { vehicle = rec.id, debug = C.debug() }
    if own then args.auto = C.opt.auto.value ~= false end
    sendClientCommand(player, Tr.MODULE, "check", args)
    rec.pendingUntil = getTimestampMs() + PENDING_MS
    if C.debug() then C.log("check " .. rec.id .. " sig " .. sig) end
  end
  rec.lastSig = sig
end

-- A local player still has a transfer queued into or out of this trunk,
-- with "Wait for transfers" on.
---@param rec TrailerCargo.Rec
---@return boolean
function C.transferBusy(rec)
  if not C.opt.wait.value or not ISTimedActionQueue or not ISTimedActionQueue.queues then return false end
  for i = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(i)
    local q = p and ISTimedActionQueue.queues[p]
    if q and q.queue then
      for _, act in ipairs(q.queue) do
        -- the stub omits a transfer's container fields
        ---@diagnostic disable-next-line: undefined-field
        if act.srcContainer == rec.container or act.destContainer == rec.container then return true end
      end
    end
  end
  return false
end

-- A trailer whose trunk a local player just changed: checked next tick.
function C.markDirty(id)
  if C.tracked[id] then
    dirty[id] = true
    dirtyAny = true
    dirtyAt = getTimestampMs()
  end
end

-- The size classes the last pass drew with; a change redraws every bed.
local lastFloor = nil

local function pass()
  if not C.opt.enabled.value then
    ---@type number[]
    local ids = {}
    local n = 0
    for id in pairs(C.tracked) do
      n = n + 1
      ids[n] = id
    end
    for i = 1, n do
      local rec = C.tracked[ids[i]]
      if rec then C.clearLayers(rec) end
      untrack(ids[i])
    end
    return
  end
  -- the size classes are this client's draw filter: a change redraws all
  local _, sig = C.hideSizes()
  local floorMoved = sig ~= lastFloor
  lastFloor = sig
  local seen = {}
  local it = getCell():getVehicles():iterator()
  while it:hasNext() do
    local v = it:next()
    local bed = Beds[v:getScriptName()]
    if bed then
      local id = v:getId()
      seen[id] = true
      ---@type TrailerCargo.Rec|nil
      local rec = C.tracked[id]
      local isNew = rec == nil
      if isNew then rec = track(v, bed) end
      if rec then
        local layout = Tr.layoutOf(rec.part)
        local covered = C.coveredNow(rec)
        local coverMoved = covered ~= rec.covered
        rec.covered = covered
        if layout.rev ~= rec.rev or floorMoved or coverMoved then
          rec.rev = layout.rev
          C.queueApply(rec)
        end
        -- first sight: one check, so a trunk changed while unloaded packs
        if isNew then C.check(rec) end
      end
    end
  end
  local gone, ng = {}, 0
  for id in pairs(C.tracked) do
    if not seen[id] then
      ng = ng + 1
      gone[ng] = id
    end
  end
  for i = 1, ng do untrack(gone[i]) end
  -- safety net: the engine can wipe a model list without telling Lua
  local n = #C.order
  if n > 0 then
    rr = rr % n + 1
    local rec = C.tracked[C.order[rr]]
    if rec then
      C.reassert(rec)
      C.check(rec)
    end
  end
end

-- Tipped-trailer watch: every client watches every tracked trailer (not
-- gated on isLocalPhysicSim, which a parked trailer never has). TIPPED is
-- the up vector's cosine (0.35 = about 70 degrees over), held HOLD ticks;
-- a kerb bounce must not dump the load. The server re-checks the angle.
local TIPPED, UPRIGHT = 0.35, 0.8
local HOLD = 60            -- ticks, a second
local FLIP_EVERY = 10      -- ticks between readings
local flipTick = 0
---@type table<number, { down: number, up: number }>
local flipCounters = {}

local function watchFlips()
  flipTick = flipTick + 1
  if flipTick % FLIP_EVERY ~= 0 then return end
  if not C.opt.spill.value then return end
  local player = C.localPlayer()
  if not player then return end
  for id, rec in pairs(C.tracked) do
    local dot = rec.vehicle:getUpVectorDot()
    local c = flipCounters[id]
    if not c then
      c = { down = 0, up = 0 }
      flipCounters[id] = c
    end
    if dot < TIPPED then
      c.down, c.up = c.down + FLIP_EVERY, 0
    elseif dot > UPRIGHT then
      c.up, c.down = c.up + FLIP_EVERY, 0
    else
      c.down, c.up = 0, 0
    end
    local layout = Tr.layoutOf(rec.part)
    -- a cover or tarp holds the load in (Bed.sealed)
    if c.down >= HOLD and not layout.spilled and #layout.list > 0 and TrailerCargo.Sandbox.itemSpill()
      and not TrailerCargo.Bed.sealed(rec.bed, Tr.installedType(rec.vehicle)) then
      c.down = 0
      sendClientCommand(player, Tr.MODULE, "spill", { vehicle = id })
      if C.debug() then C.log(string.format("spill requested for %d, up vector %.2f", id, dot)) end
    elseif c.up >= HOLD and layout.spilled then
      c.up = 0
      sendClientCommand(player, Tr.MODULE, "upright", { vehicle = id })
      if C.debug() then C.log("upright reported for " .. id) end
    end
  end
  -- assigning nil to a key already present is allowed during a pairs walk
  for id in pairs(flipCounters) do
    if not C.tracked[id] then flipCounters[id] = nil end
  end
end

-- Trailers with an answer outstanding: redraw the tick the rev moves.
local function pollPending()
  local now = getTimestampMs()
  for _, rec in pairs(C.tracked) do
    local until_ = rec.pendingUntil
    if until_ then
      local layout = Tr.layoutOf(rec.part)
      if layout.rev ~= rec.rev then
        rec.rev = layout.rev
        rec.pendingUntil = nil
        C.queueApply(rec)
      elseif now > until_ then
        rec.pendingUntil = nil
      end
    end
  end
end

local function tick()
  watchFlips()
  pollPending()
  -- a moved stack arrives one item per update: wait for them to stop,
  -- then pack the batch in priority order
  if dirtyAny and getTimestampMs() - dirtyAt >= SETTLE_MS then
    dirtyAny = false
    ---@type number[]
    local ids = {}
    local n = 0
    for id in pairs(dirty) do
      n = n + 1
      ids[n] = id
    end
    dirty = {}
    for i = 1, n do
      local rec = C.tracked[ids[i]]
      if rec and C.transferBusy(rec) then
        -- checked once the queue is done
        dirty[ids[i]] = true
        dirtyAny = true
      elseif rec then
        C.check(rec, true)
      end
    end
  end
  local now = getTimestampMs()
  if now - lastPass < PASS_MS then return end
  lastPass = now
  pass()
end

-- One pcall: an error is one log line, not a trace sixty times a second.
local function onTick()
  local ok, err = pcall(tick)
  if not ok then C.log("tick error: " .. tostring(err)) end
end

-- OnContainerUpdate has no arguments: mark every trailer within reach.
local function onContainerUpdate()
  for id, rec in pairs(C.tracked) do
    local vx, vy = rec.vehicle:getX(), rec.vehicle:getY()
    for i = 0, getNumActivePlayers() - 1 do
      local p = getSpecificPlayer(i)
      if p then
        local dx, dy = p:getX() - vx, p:getY() - vy
        if dx * dx + dy * dy <= REACH2 then
          dirty[id] = true
          dirtyAny = true
          break
        end
      end
    end
  end
end

-- Every vanilla transfer ends in ISInventoryTransferAction:transferItem,
-- for which OnContainerUpdate does not fire. Wrapped at OnGameStart: the
-- class may not exist yet when this file loads.
local wrapped = false

local function wrapTransfer()
  if wrapped or not ISInventoryTransferAction or not ISInventoryTransferAction.transferItem then return end
  wrapped = true
  local vanillaTransfer = ISInventoryTransferAction.transferItem
  local function trailerOf(container)
    local part = container and container:getVehiclePart()
    local vehicle = part and part:getVehicle()
    return vehicle and vehicle:getId() or nil
  end
  -- the stub omits self and the container fields
  ---@diagnostic disable-next-line: assign-type-mismatch
  ISInventoryTransferAction.transferItem = function(self, item)
    ---@diagnostic disable-next-line: param-type-mismatch
    local result = vanillaTransfer(self, item)
    ---@diagnostic disable-next-line: undefined-field
    local src, dst = trailerOf(self.srcContainer), trailerOf(self.destContainer)
    if src then C.markDirty(src) end
    if dst and dst ~= src then C.markDirty(dst) end
    return result
  end
end

Events.OnTick.Add(onTick)
Events.OnContainerUpdate.Add(onContainerUpdate)
Events.OnGameStart.Add(wrapTransfer)
