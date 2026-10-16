-- TrailerCargo_Render: what is DRAWN on a tracked trailer (item id -> Model).
-- Incremental: every setModelVisible add or remove rebuilds all sub-models
-- (BaseVehicle.java:1745-1770); a layer that only moved is posed through
-- its live offset vector. Nothing else calls setModelVisible.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}
TrailerCargo.Bed = TrailerCargo.Bed or {}
TrailerCargo.Pack = TrailerCargo.Pack or {}
TrailerCargo.Script = TrailerCargo.Script or {}
TrailerCargo.Trunk = TrailerCargo.Trunk or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local B, P, Sc, Tr = TrailerCargo.Bed, TrailerCargo.Pack, TrailerCargo.Script, TrailerCargo.Trunk
local Bounds = TrailerCargo.Bounds

-- Item model units to tiles, / modelScale (BaseVehicle.java:4460).
local ITEM_SCALE = 1.5

---@class TrailerCargo.Layer
---@field model VehicleScript.Model
---@field file string
---@field script VehicleScript

---@class TrailerCargo.Rec
---@field id number
---@field vehicle BaseVehicle
---@field bed TrailerCargo.BedEntry
---@field part VehiclePart
---@field container ItemContainer
---@field ms number
---@field body { x: number, y: number, z: number }
---@field rev number
---@field layers table<number, TrailerCargo.Layer>
---@field serial integer  numbers the carrier scripts, so no two share a name
---@field lastSig string
---@field covered boolean|nil  a cover part is installed: nothing is drawn (Bed.covered)
---@field pendingUntil number|nil  while set, the layout is polled every tick for the server's answer
---@field nsKey string|nil  C.notShown's cache: rev / item count / size floor
---@field nsN integer|nil
---@field nsWhy string|nil
---@field nsText string|nil  the title's "N not on the bed", built with the count
---@field v0 Vector3f
---@field v1 Vector3f
---@field v2 Vector3f

local function halfRng() return 0.5 end

-- maxNew 0: the client never packs, it only tests fits.
---@param rec TrailerCargo.Rec
---@return TrailerCargo.PackCtx
function C.ctx(rec)
  return { bounds = Bounds, capOf = TrailerCargo.stackCap, ms = rec.ms, rng = halfRng, maxNew = 0 }
end

-- A setModelVisible rebuild drops the vehicle's damage overlay
-- (ModelManager.addVehicle); ask for it again.
---@param rec TrailerCargo.Rec
---@param why string|nil  logged in debug; nil for the quiet self-heal
local function redoOverlay(rec, why)
  rec.vehicle:updateDamageOverlayLater()
  if why and C.debug() then C.log("damage overlay redone for " .. tostring(rec.id) .. " after " .. why) end
end

---@param rec TrailerCargo.Rec
local function hideLayer(rec, key)
  local L = rec.layers[key]
  if not L then return end
  rec.vehicle:setModelVisible(rec.part, L.model, false)
  rec.layers[key] = nil
  redoOverlay(rec, "a remove")
end

---@param rec TrailerCargo.Rec
function C.clearLayers(rec)
  local keys, n = {}, 0
  for key in pairs(rec.layers) do
    n = n + 1
    keys[n] = key
  end
  for i = 1, n do hideLayer(rec, keys[i]) end
end

-- Runtime clones by name: true when the engine took it.
---@type table<string, boolean>
local made = {}

-- A model script drawing `bare`'s mesh with the item's texture; it needs
-- a module for addModelScript (ScriptManager.java:646). Once per name.
---@param bare string  model name
---@param tex string   texture path
---@return boolean
function C.ensureTextured(bare, tex)
  local name = Sc.texturedName(bare, tex)
  local known = made[name]
  if known ~= nil then return known end
  local u = TrailerCargo.Untextured[bare]
  local sm = getScriptManager()
  local ok, err = pcall(function()
    local ms = ModelScript.new()
    ms:InitLoadPP(name)
    ms:Load(name, Sc.modelText(name, u, tex))
    ms:setModule(sm:getModule("TrailerCargo"))
    sm:addModelScript(ms)
  end)
  if not ok then C.log("textured clone " .. name .. " refused: " .. tostring(err)) end
  local took = ok == true and sm:getModelScript("TrailerCargo." .. name) ~= nil
  made[name] = took
  if C.debug() and took then C.log("textured clone " .. name .. " for " .. tex) end
  return took
end

-- Every layer the layout asks for, capped, posed in part space. The
-- texture is each item's own, read here rather than saved.
---@param rec TrailerCargo.Rec
---@param layout TrailerCargo.Layout
---@return TrailerCargo.ScriptLayer[]
local function targets(rec, layout)
  local wanted, n = {}, 0
  -- under a canvas nothing shows; the layout waits for it to come off
  if rec.covered then return wanted end
  local cap = C.opt.max.value or 64
  local list = layout.list
  local items = Tr.itemsById(rec.container)
  local ctx = C.ctx(rec)
  -- the size classes filter what this client draws, not the layout
  local hide, sig = C.hideSizes()
  local drawn = nil
  if sig ~= "0000" then
    local all, k = {}, 0
    for i = 1, #list do
      local e = list[i]
      for li = 1, #e.ids do
        k = k + 1
        local it = items[e.ids[li]]
        all[k] = { id = e.ids[li], m = e.m, w = it and it:getUnequippedWeight() or 0 }
      end
    end
    drawn = {}
    local kept = Tr.filter(all, layout, Bounds, rec.ms, hide)
    for i = 1, #kept do drawn[kept[i].id] = true end
  end
  for i = 1, #list do
    local e = list[i]
    for li = 1, #e.ids do
      local id = e.ids[li]
      if drawn == nil or drawn[id] then
        n = n + 1
        if n > cap then return wanted end
        local item = items[id]
        local tex = item and Tr.textureOf(item, e.m) or nil
        if tex ~= nil and not C.ensureTextured(B.key(e.m) or e.m, tex) then tex = nil end
        local px, pz, pyaw, py = P.drawnPose(e, li, ctx)
        local s = ITEM_SCALE / rec.ms
        local rx, ry, rz, dx, dy, dz = B.pose(pyaw, TrailerCargo.Fixups[B.key(e.m)], TrailerCargo.LayDown[e.m], e.rx, e.rz, s)
        wanted[n] = {
          key = id, file = Sc.fileOf(e.m, tex), x = px + dx, z = pz + dz, yaw = ry,
          y = B.layerY(rec.bed, Bounds, e.m, rec.ms, 0) + py + dy,
          scale = s, rx = rx, rz = rz,
        }
      end
    end
  end
  return wanted
end

-- yaw here is already the composed middle Euler term from B.rotateField.
---@param L TrailerCargo.Layer
local function pose(L, x, y, z, yaw, rx, rz)
  L.model:getOffset():set(x, y, z)
  L.model:getRotate():set(rx or 0, yaw, rz or 0)
end

-- New layers go in one small script: build, Load, show each Model.
---@param rec TrailerCargo.Rec
---@param fresh TrailerCargo.ScriptLayer[]
local function showFresh(rec, fresh)
  rec.serial = rec.serial + 1
  local name = "TrailerCargo_" .. tostring(rec.id) .. "_" .. tostring(rec.serial)
  local text = Sc.text(name, fresh)
  local vs = VehicleScript.new()
  local ok, err = pcall(function() vs:Load(name, text) end)
  if not ok then
    C.log("script Load failed on " .. name .. ": " .. tostring(err))
    return
  end
  -- never vs:Loaded(): a new() script has no module, toBullet() throws
  local sp = vs:getPartById(Sc.PART_ID)
  if not sp then
    C.log("script " .. name .. " has no part")
    return
  end
  local byKey = {}
  for i = 1, #fresh do byKey[fresh[i].key] = fresh[i] end
  for i = 0, sp:getModelCount() - 1 do
    local m = sp:getModel(i)
    local key = tonumber(string.sub(m:getId(), 2))
    local w = key and byKey[key]
    if w then
      local okShow, info = pcall(function() return rec.vehicle:setModelVisible(rec.part, m, true) end)
      if okShow and info then
        -- the layer keeps its script alive: the Model belongs to it
        ---@type TrailerCargo.Layer
        local layer = { model = m, file = w.file, script = vs }
        rec.layers[key] = layer
      else
        C.log("setModelVisible failed for " .. w.file .. ": " .. tostring(info))
      end
    end
  end
  redoOverlay(rec, "an add")
end

-- Make the drawn set equal the layout: hide what left, move what moved,
-- show what is new.
---@param rec TrailerCargo.Rec
---@param layout TrailerCargo.Layout
function C.applyLayout(rec, layout)
  local wanted = targets(rec, layout)
  local keep, fresh, nf = {}, {}, 0
  for i = 1, #wanted do
    local w = wanted[i]
    keep[w.key] = true
    local L = rec.layers[w.key]
    if L and L.file == w.file then
      pose(L, w.x, w.y, w.z, w.yaw, w.rx, w.rz)
    else
      if L then hideLayer(rec, w.key) end
      nf = nf + 1
      fresh[nf] = w
    end
  end
  local gone, ng = {}, 0
  for key in pairs(rec.layers) do
    if not keep[key] then
      ng = ng + 1
      gone[ng] = key
    end
  end
  for i = 1, ng do hideLayer(rec, gone[i]) end
  if nf > 0 then showFresh(rec, fresh) end
end

-- Arrange mode: pose one entry's layers without a layout pass. `lift`
-- raises it (the item under the mouse).
---@param rec TrailerCargo.Rec
---@param entry TrailerCargo.Entry
---@param lift number|nil  part units above its resting height
function C.applyEntryPose(rec, entry, lift)
  lift = lift or 0
  local ctx = C.ctx(rec)
  for li = 1, #entry.ids do
    local L = rec.layers[entry.ids[li]]
    if L then
      local px, pz, pyaw, py = P.drawnPose(entry, li, ctx)
      local rx, ry, rz, dx, dy, dz = B.pose(pyaw, TrailerCargo.Fixups[B.key(entry.m)],
        TrailerCargo.LayDown[entry.m], entry.rx, entry.rz, ITEM_SCALE / rec.ms)
      pose(L, px + dx, B.layerY(rec.bed, Bounds, entry.m, rec.ms, 0) + py + lift + dy, pz + dz, ry, rx, rz)
    end
  end
end

-- Adds and removes run in OnPostRender, not OnTick: a model added in
-- OnTick draws once untransformed before the next world update (a flash;
-- IngameState.java:1507, :1625, :1173).
---@type table<number, TrailerCargo.Rec>
local applyQueue = {}

---@param rec TrailerCargo.Rec
function C.queueApply(rec)
  applyQueue[rec.id] = rec
end

local function onPostRender()
  for id, rec in pairs(applyQueue) do
    -- held until the transfer is done ("Wait for transfers")
    if not C.transferBusy(rec) then
      applyQueue[id] = nil
      if C.tracked[id] == rec then C.applyLayout(rec, Tr.layoutOf(rec.part)) end
    end
  end
end

Events.OnPostRender.Add(onPostRender)

-- Self-heal: a still-shown Model returns without a rebuild
-- (BaseVehicle.java:1738); one the engine wiped comes back.
---@param rec TrailerCargo.Rec
function C.reassert(rec)
  local any = false
  for _, L in pairs(rec.layers) do
    rec.vehicle:setModelVisible(rec.part, L.model, true)
    any = true
  end
  if any then redoOverlay(rec) end
end
