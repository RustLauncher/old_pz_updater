-- TrailerCargo_CarDraw: the cars loaded on a car trailer drawn as the real
-- cars, sub-models of the trailer on its slot part: each car's body plus
-- the models its parts show, with its own skin and a paint swatch shader.
-- What a car shows comes from replaying its parts' Lua against stand-ins
-- built from the server's copy of the W900 snapshot (TrailerCargo_Server,
-- carSync). A move poses the live Models; only a load, unload or swap
-- rebuilds.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local CT, Tr = TrailerCargo.CarTrailer, TrailerCargo.Trunk

---@class TrailerCargo.CarDrawn
---@field key string        which car and how it is drawn
---@field w integer         its W900 slot
---@field list TrailerCargo.CarModel[]
---@field files string[]
---@field models VehicleScript.Model[]
---@field script VehicleScript  keeps the Models alive
---@field place TrailerCargo.CarPlace
---@field label string

---@class TrailerCargo.CarRec
---@field id number
---@field vehicle BaseVehicle
---@field row TrailerCargo.CarTrailerRow
---@field part VehiclePart
---@field ms number
---@field body { x: number, y: number, z: number }
---@field v0 Vector3f
---@field drawn table<integer, TrailerCargo.CarDrawn>
---@field preview table<integer, TrailerCargo.CarPose>  arrange mode's poses, not yet sent
---@field previewRev number|nil  the layout rev when previews were sent; a newer one replaces them
---@field lift table<integer, number>
---@field rev number
---@field syncAt number
---@field skipped table<integer, string[]>

---@type table<number, TrailerCargo.CarRec>
C.cars = C.cars or {}

-- Cars are drawn only on trailers this close to a local player, tiles.
local RANGE = 60
local SYNC_RETRY_MS = 3000

local serial = 0

local slotRef, refKey, bareName, copy = CT.w900Ref, CT.refKey, CT.bareName, CT.copy

-- The saved layout, read only: a client never writes the part's modData.
---@param crec TrailerCargo.CarRec
---@return TrailerCargo.CarLayout
function C.carLayout(crec)
  local md = crec.part:getModData()
  local src = type(md[CT.MODDATA]) == "table" and md or {}
  return CT.layoutOf(src, #crec.row.slots)
end

---@param crec TrailerCargo.CarRec
---@param w integer
---@return TrailerCargo.CarInfo|nil
local function infoOf(crec, w)
  local L = C.carLayout(crec)
  local info = L.info and (L.info[w] or L.info[tostring(w)])
  local key = refKey(slotRef(crec.part, w))
  -- the server's key is refKey .. "|" .. the car's own print
  if info and key and type(info.key) == "string" and string.sub(info.key, 1, #key + 1) == key .. "|" then return info end
  return nil
end

-- A cover shows while its slot's marker item is installed (the W900 mod).
---@param crec TrailerCargo.CarRec
local function coverVisible(crec, pair, on)
  local cp = crec.vehicle:getPartById(crec.row.cover .. tostring(pair))
  if not cp then return end
  if on and cp:getInventoryItem() == nil then return end
  local sp = cp:getScriptPart()
  for k = 0, sp:getModelCount() - 1 do
    cp:setModelVisible(sp:getModel(k):getId(), on)
  end
end

local function modelScript(name)
  local sm = getScriptManager()
  return sm:getModelScript(name) or sm:getModelScript("Base." .. name)
end

-- A clone of a car model in module TrailerCargo: its mesh (CT.cloneMesh's
-- spelling), static, with another texture and shader. Once per name.
---@param ms ModelScript
---@return string|nil file, string|nil why
local function clone(ms, name, scale, tex, shader)
  local cname = "TCCar_" .. string.gsub(name .. "_" .. tostring(tex) .. "_" .. shader, "[^%w_]", "_")
  local sm = getScriptManager()
  if sm:getModelScript("TrailerCargo." .. cname) then return "TrailerCargo." .. cname end
  local text = string.format("model %s { mesh = %s, scale = %s, static = true, texture = %s, shader = %s, }",
    cname, CT.cloneMesh(ms:getMeshName(), ms:isStatic()), tostring(scale), tostring(tex), shader)
  local ok, err = pcall(function()
    local c = ModelScript.new()
    c:InitLoadPP(cname)
    c:Load(cname, text)
    c:setModule(sm:getModule("TrailerCargo"))
    sm:addModelScript(c)
  end)
  if not ok then return nil, "clone refused: " .. tostring(err) end
  return "TrailerCargo." .. cname
end

-- The model to draw for a car model: its own script, or a clone on the
-- car's skin and a swatch shader (a vehicle shader would take the TRAILER's
-- textures, Model.DrawVehicle). Clones are static: a skinned sub-model on
-- another shader gets no bone matrices (Model.java:600-606). A damaged
-- part's clone comes with a second one, vanilla's damage marks over it
-- (trailercargo_cardmg_<swatch>, build/gen_car_shaders.py).
---@param wear integer  0, 1 or 2 (CT.wearLevel)
---@param damage string[]|nil  the car's damage shells, light then heavy
---@return string|nil file, string|nil why, string|nil overlay
local function drawable(name, tex, sw, wear, damage)
  local ms = modelScript(name)
  if not ms then return nil, "no model script" end
  local kind = CT.cloneKind(ms:getShaderName())
  if not kind then return name end
  local scale = TrailerCargo.CarModelScale[bareName(name)]
  if not scale then return nil, "no scale in TrailerCargo_Cars" end
  local file, why = clone(ms, name, scale, tex, "trailercargo_car_" .. (kind == "none" and "none" or sw))
  if not file then return nil, why end
  local dtex = wear > 0 and damage and damage[wear] or nil
  local overlay = dtex and clone(ms, name, scale, dtex, "trailercargo_cardmg_" .. sw) or nil
  return file, nil, overlay
end

-- A part model with no file draws the installed item's VehiclePartModel.
local function itemModel(itemType, pid, mid)
  local list = TrailerCargo.CarPartModels[itemType]
  if not list then return nil end
  for k = 1, #list do
    local e = list[k]
    if string.lower(e[1]) == string.lower(pid) and string.lower(e[2]) == string.lower(mid) then return e[3] end
  end
  return nil
end

-- A function a script names by its dotted path, as the engine resolves it.
local function luaFn(path)
  local t = _G
  for piece in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[piece]
  end
  return type(t) == "function" and t or nil
end

-- Anything the stand-ins do not answer is a method that does nothing.
local nop = { __index = function() return function() return nil end end }

-- Which models each part shows, the way a real car arrives at them: the
-- engine's default (every model of an installed setAllModelsVisible part,
-- VehiclePart.java:155), the install hook each installed part ran, then
-- every part's `init` (VehicleParts.java:268), against stand-ins that
-- record setModelVisible. Returns vis[pid][modelId].
---@param car VehicleScript
---@param row table  TrailerCargo.Cars row
---@param info TrailerCargo.CarInfo
local function visibleModels(car, row, info)
  local parts = info.parts or {}
  local rows = row.parts
  local vis, report, mocks, copies = {}, {}, {}, {}
  local veh = setmetatable({}, nop)
  local function item(fullType)
    if not fullType then return nil end
    local typ = string.match(fullType, "%.(.+)$") or fullType
    return setmetatable({
      getType = function() return typ end,
      getFullType = function() return fullType end,
      getCondition = function() return 100 end,
      getModData = function() return {} end,
    }, nop)
  end
  local function mock(pid)
    if mocks[pid] then return mocks[pid] end
    local sp = car:getPartById(pid)
    if not sp then return nil end
    local sn = parts[pid] or {}
    -- a door part's hooks call part:getDoor():setLocked(...) (Vehicles.lua:965)
    local r = rows[pid] or {}
    local door = string.find((r.init or "") .. (r.complete or ""), "Door", 1, true) and setmetatable({}, nop) or nil
    local m = setmetatable({
      getDoor = function() return door end,
      getId = function() return pid end,
      getInventoryItem = function() return item(sn.item or nil) end,
      getCondition = function() return sn.cond or 100 end,
      getModData = function()
        copies[pid] = copies[pid] or copy(sn.md or {})
        return copies[pid]
      end,
      getVehicle = function() return veh end,
      getScriptPart = function() return sp end,
      setModelVisible = function(_, id, on)
        vis[pid] = vis[pid] or {}
        vis[pid][id] = on and true or false
      end,
      setAllModelsVisible = function(_, on)
        vis[pid] = vis[pid] or {}
        for k = 0, sp:getModelCount() - 1 do vis[pid][sp:getModel(k):getId()] = on and true or false end
      end,
    }, nop)
    mocks[pid] = m
    return m
  end
  local vmd = copy(info.vmd or {})
  veh.getPartById = function(_, id) return mock(id) end
  veh.getScript = function() return car end
  veh.getScriptName = function() return "Base." .. car:getName() end
  veh.getModData = function() return vmd end
  veh.getPartCount = function() return car:getPartCount() end
  veh.getPartByIndex = function(_, i) return mock(car:getPart(i):getId()) end
  veh.getSkinIndex = function() return info.skin or 0 end
  local function installed(pid)
    local sn = parts[pid]
    return sn ~= nil and sn.item and true or false
  end
  local function run(pid, kind, path)
    local fn = luaFn(path)
    if not fn then
      report[#report + 1] = pid .. " " .. kind .. " " .. path .. " not found"
      return
    end
    local ok, err = pcall(fn, veh, mock(pid))
    if not ok then report[#report + 1] = pid .. " " .. kind .. " " .. path .. " failed: " .. tostring(err) end
  end
  for p = 0, car:getPartCount() - 1 do
    local pid = car:getPart(p):getId()
    local r = rows[pid] or {}
    if installed(pid) and r.all ~= false then mock(pid):setAllModelsVisible(true) end
  end
  for p = 0, car:getPartCount() - 1 do
    local pid = car:getPart(p):getId()
    local r = rows[pid]
    if r and r.complete and installed(pid) then run(pid, "install", r.complete) end
  end
  for p = 0, car:getPartCount() - 1 do
    local pid = car:getPart(p):getId()
    local r = rows[pid]
    if r and r.init then run(pid, "init", r.init) end
  end
  return vis, report
end

-- Every model the car draws, in its part frame (body frame before modelScale).
---@return TrailerCargo.CarModel[] list, string[] files, string[] skipped
---@param damage string[]|nil  the car's damage shells for its skin
local function carModels(car, row, info, tex, sw, damage)
  local list, files, skipped = {}, {}, {}
  local parts = info.parts or {}
  local function add(label, name, ox, oy, oz, rot, sc, wheel, cond)
    local file, why, overlay = drawable(name, tex, sw, CT.wearLevel(cond), damage)
    if not file then
      skipped[#skipped + 1] = label .. " " .. tostring(name) .. " (" .. tostring(why) .. ")"
      return
    end
    local rx, ry, rz = rot:x(), rot:y(), rot:z()
    -- a wheel model turns y and z the other way (rotateYZ, BaseVehicle:4431)
    if wheel then ry, rz = -ry, -rz end
    list[#list + 1] = { ox = ox, oy = oy, oz = oz, rx = rx, ry = ry, rz = rz, scale = sc }
    files[#files + 1] = file
    if overlay then
      list[#list + 1] = { ox = ox, oy = oy, oz = oz, rx = rx, ry = ry, rz = rz, scale = sc }
      files[#files + 1] = overlay
    end
  end
  local ms = car:getModelScale()
  local bodyCond = CT.bodyCondition(parts)
  add("body", car:getModel():getFile(), 0, 0, 0, car:getModel():getRotate(), 1, false, bodyCond)
  local wheels = {}
  for k = 0, car:getWheelCount() - 1 do
    local w = car:getWheel(k)
    wheels[w:getId()] = w:getOffset()
  end
  local vis, report = visibleModels(car, row, info)
  for k = 1, #report do skipped[#skipped + 1] = report[k] end
  for p = 0, car:getPartCount() - 1 do
    local sp = car:getPart(p)
    local pid = sp:getId()
    local pv = vis[pid]
    if pv then
      local itemType = parts[pid] and parts[pid].item or nil
      local cond = parts[pid] and parts[pid].cond
      -- the body models KI5 hangs on GloveBox show the shell's wear
      if pid == "GloveBox" then cond = bodyCond end
      local r = row.parts[pid] or {}
      local wo = r.wheel and wheels[r.wheel]
      -- a wheel's models sit at the wheel, in the body frame: offset / scale
      local bx, by, bz = 0.0, 0.0, 0.0
      if wo then bx, by, bz = wo:x() / ms, wo:y() / ms, wo:z() / ms end
      for k = 0, sp:getModelCount() - 1 do
        local m = sp:getModel(k)
        if pv[m:getId()] then
          local label = pid .. "/" .. m:getId()
          if CT.brokenGlass(pid, cond) then
            skipped[#skipped + 1] = label .. " (broken glass)"
          elseif m:getAttachmentNameParent() then
            skipped[#skipped + 1] = label .. " (attached to its parent part)"
          else
            local name = m:getFile() or (itemType and itemModel(itemType, pid, m:getId()))
            if not name then
              skipped[#skipped + 1] = label .. " (no model for " .. tostring(itemType) .. ")"
            else
              local o = m:getOffset()
              add(label, name, bx + o:x(), by + o:y(), bz + o:z(), m:getRotate(), m:getScale(), wo ~= nil, cond)
            end
          end
        end
      end
    end
  end
  return list, files, skipped
end

---@param crec TrailerCargo.CarRec
---@param p integer
---@return TrailerCargo.CarPose
function C.carPoseOf(crec, p)
  local pose = crec.preview[p] or CT.poseAt(C.carLayout(crec), p)
  local lift = crec.lift[p] or 0
  if lift == 0 then return pose end
  return { x = pose.x, y = pose.y + lift, z = pose.z, yaw = pose.yaw, tilt = pose.tilt }
end

-- Pose a drawn car's live Models; the render reads them every frame.
---@param crec TrailerCargo.CarRec
---@param p integer
function C.poseCar(crec, p)
  local d = crec.drawn[p]
  if not d then return end
  local pose = C.carPoseOf(crec, p)
  for i = 1, #d.models do
    local x, y, z, rx, ry, rz = CT.modelAt(d.list[i], d.place, pose)
    d.models[i]:getOffset():set(x, y, z)
    d.models[i]:getRotate():set(rx, ry, rz)
  end
end

---@param crec TrailerCargo.CarRec
---@param p integer
local function removeCar(crec, p)
  local d = crec.drawn[p]
  if not d then return end
  for i = 1, #d.models do crec.vehicle:setModelVisible(crec.part, d.models[i], false) end
  crec.drawn[p] = nil
  -- a rebuild drops the vehicle's damage overlay (ModelManager.addVehicle)
  crec.vehicle:updateDamageOverlayLater()
end

-- Build what position p shows: the car of W900 slot w.
---@param crec TrailerCargo.CarRec
---@param p integer
---@param w integer
---@param info TrailerCargo.CarInfo
---@param key string
local function buildCar(crec, p, w, info, key)
  local ref = slotRef(crec.part, w)
  local scriptName = ref and ref.scriptName
  local sm = getScriptManager()
  local car = scriptName and (sm:getVehicle(scriptName) or sm:getVehicle("Base." .. scriptName))
  local row = scriptName and TrailerCargo.Cars[bareName(scriptName)]
  if not car or not row or car:getWheelCount() == 0 then
    crec.skipped[p] = { tostring(scriptName) .. ": " .. (not car and "no vehicle script" or not row and "no TrailerCargo_Cars row" or "no wheels") }
    return
  end
  local show = CT.showAt(C.carLayout(crec), p)
  local sw = CT.swatch(info.h, info.s, info.v)
  -- a hidden car keeps an entry with no models: arrange can still pick it
  local list, files, skipped = {}, {}, {}
  local place = CT.coverPlace(crec.row.slots[p])
  if show == "car" then
    local skin = tonumber(info.skin) or tonumber(ref.skin) or 0
    ---@type string[]
    local skins = row.skins
    ---@type table
    local shells = row.damage or {}
    local dmg = shells[skin + 1] or shells[1]
    -- false in the table: the car's script names none
    ---@type string[]
    local damage = {}
    if dmg then damage[1], damage[2] = dmg[1] or nil, dmg[2] or nil end
    list, files, skipped = carModels(car, row, info, skins[skin + 1] or skins[1], sw, damage)
    place = CT.placeFor(crec.row.slots[p], car, row, crec.ms)
  elseif show == "cover" then
    -- the W900's own tarp shape, modelled at this slot, posed like the car
    for _, prefix in ipairs(crec.row.coverModels or {}) do
      list[#list + 1] = { ox = 0, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, scale = 1 }
      files[#files + 1] = prefix .. tostring(p)
    end
  end
  crec.skipped[p] = skipped
  local pose = C.carPoseOf(crec, p)
  serial = serial + 1
  local vname = "TrailerCargoCar_" .. tostring(crec.id) .. "_" .. tostring(serial)
  local buf = { "vehicle " .. vname .. " { part TCCar { " }
  for n = 1, #list do
    local x, y, z, rx, ry, rz, sc = CT.modelAt(list[n], place, pose)
    buf[#buf + 1] = string.format("model m%d { file = %s, offset = %.4f %.4f %.4f, rotate = %.2f %.2f %.2f, scale = %.5f, } ",
      n, files[n], x, y, z, rx, ry, rz, sc)
  end
  buf[#buf + 1] = "} }"
  local vs = VehicleScript.new()
  local ok, err = pcall(function() vs:Load(vname, table.concat(buf)) end)
  if not ok then
    C.log("car script Load failed: " .. tostring(err))
    return
  end
  -- NOT vs:Loaded(): a VehicleScript.new() has no module (CLAUDE.md)
  local sp = vs:getPartById("TCCar")
  local models, kept, keptFiles = {}, {}, {}
  for n = 0, sp:getModelCount() - 1 do
    local m = sp:getModel(n)
    if crec.vehicle:setModelVisible(crec.part, m, true) then
      models[#models + 1] = m
      kept[#kept + 1] = list[n + 1]
      keptFiles[#keptFiles + 1] = files[n + 1]
    else
      skipped[#skipped + 1] = "refused by the engine: " .. tostring(m:getFile())
    end
  end
  crec.drawn[p] = { key = key, w = w, list = kept, files = keptFiles, models = models, script = vs, place = place,
    label = tostring(scriptName) .. " " .. sw .. (show ~= "car" and (" (" .. show .. ")") or "") }
  crec.vehicle:updateDamageOverlayLater()
  if C.debug() then
    C.log(string.format("car %s at position %d (W900 slot %d): %d models, %d skipped", tostring(scriptName), p, w,
      #models, #skipped))
  end
end

-- Builds wait for the frame's render (the cargo flash, TrailerCargo_Render).
---@type table<number, boolean>
local buildQueue = {}

---@param crec TrailerCargo.CarRec
local function wanted(crec)
  local n = #crec.row.slots
  local L = C.carLayout(crec)
  local out = {}
  for p = 1, n do
    local w = L.map[p] or p
    local key = refKey(slotRef(crec.part, w))
    if key then
      local info = infoOf(crec, w)
      if info then
        out[p] = { w = w, info = info,
          key = info.key .. "@" .. CT.swatch(info.h, info.s, info.v) .. "#" .. w .. "!" .. CT.showAt(L, p) }
      end
    end
  end
  return out
end

-- Make the drawn cars equal the loaded ones; hide the loaded slots' covers.
---@param crec TrailerCargo.CarRec
local function apply(crec)
  local want = wanted(crec)
  for p = 1, #crec.row.slots do
    local d, t = crec.drawn[p], want[p]
    if d and (not t or t.key ~= d.key) then removeCar(crec, p) end
    if t and not crec.drawn[p] then buildCar(crec, p, t.w, t.info, t.key) end
  end
end

local function onPostRender()
  for id in pairs(buildQueue) do
    buildQueue[id] = nil
    local crec = C.cars[id]
    if crec then apply(crec) end
  end
end

---@param crec TrailerCargo.CarRec
local function askSync(crec)
  local now = getTimestampMs()
  if now - crec.syncAt < SYNC_RETRY_MS then return end
  crec.syncAt = now
  local player = C.localPlayer()
  if player then sendClientCommand(player, Tr.MODULE, "carSync", { vehicle = crec.id }) end
end

-- One pass over a trailer: ask for missing car data, queue a rebuild when
-- the loaded cars changed, pose on a layout change, keep covers hidden and
-- Models shown (both no-ops when nothing changed).
---@param crec TrailerCargo.CarRec
local function refresh(crec)
  local n = #crec.row.slots
  local L = C.carLayout(crec)
  local need = false
  for w = 1, n do
    local ref = slotRef(crec.part, w)
    if ref then
      coverVisible(crec, ref.coverPair or w, false)
      if not infoOf(crec, w) then need = true end
    end
  end
  if need then askSync(crec) end
  local want = wanted(crec)
  for p = 1, n do
    local d, t = crec.drawn[p], want[p]
    if (d and not t) or (t and (not d or d.key ~= t.key)) then buildQueue[crec.id] = true end
  end
  if L.rev ~= crec.rev then
    crec.rev = L.rev
    if crec.previewRev and L.rev > crec.previewRev then
      crec.preview, crec.previewRev = {}, nil
    end
    for p in pairs(crec.drawn) do C.poseCar(crec, p) end
  end
  for _, d in pairs(crec.drawn) do
    for i = 1, #d.models do crec.vehicle:setModelVisible(crec.part, d.models[i], true) end
  end
end

---@param crec TrailerCargo.CarRec
local function clearAll(crec)
  for p in pairs(crec.drawn) do removeCar(crec, p) end
  for w = 1, #crec.row.slots do
    local ref = slotRef(crec.part, w)
    if ref then coverVisible(crec, ref.coverPair or w, true) end
  end
end

---@param vehicle BaseVehicle
---@param row TrailerCargo.CarTrailerRow
---@return TrailerCargo.CarRec|nil
local function trackCar(vehicle, row)
  local part = vehicle:getPartById(row.part)
  if not part then return nil end
  local script = vehicle:getScript()
  local off = script:getModelOffset()
  ---@type TrailerCargo.CarRec
  local crec = {
    id = vehicle:getId(), vehicle = vehicle, row = row, part = part, ms = script:getModelScale(),
    body = { x = off:x(), y = off:y(), z = off:z() }, v0 = Vector3f.new(),
    drawn = {}, preview = {}, lift = {}, rev = -1, syncAt = -SYNC_RETRY_MS, skipped = {},
  }
  C.cars[crec.id] = crec
  if C.debug() then C.log("tracking car trailer " .. vehicle:getScriptName() .. " id " .. crec.id) end
  return crec
end

---@param vehicle BaseVehicle
---@return TrailerCargo.CarRec|nil
function C.carRecFor(vehicle)
  return vehicle and C.cars[vehicle:getId()] or nil
end

local function near(v)
  for i = 0, getNumActivePlayers() - 1 do
    local pl = getSpecificPlayer(i)
    if pl then
      local dx, dy = pl:getX() - v:getX(), pl:getY() - v:getY()
      if dx * dx + dy * dy <= RANGE * RANGE then return true end
    end
  end
  return false
end

-- A car trailer held past 50 degrees for HOLD_TICKS asks the server to
-- spill its cars, checked every FLIP_TICKS. The server checks the angle
-- again; a car with no room stays loaded and the next report,
-- SPILL_RETRY_MS on, tries again.
local TIPPED = 0.64
local FLIP_TICKS = 4
local HOLD_TICKS = 12
local SPILL_RETRY_MS = 5000
-- after a request the trailer is rechecked every tick this long, so the
-- drawn car goes the frame its slot empties, not up to 30 ticks later
local SPILL_FAST_MS = 3000
---@type table<number, { down: integer, at: number }>
local flips = {}
---@type table<number, { v: BaseVehicle, row: TrailerCargo.CarTrailerRow }>
local flipWatch = {}

---@param v BaseVehicle
---@param row TrailerCargo.CarTrailerRow
local function watchFlip(v, row)
  local id = v:getId()
  local f = flips[id]
  if not f then
    f = { down = 0, at = -SPILL_RETRY_MS }
    flips[id] = f
  end
  if v:getUpVectorDot() >= TIPPED then
    f.down = 0
    return
  end
  f.down = f.down + FLIP_TICKS
  if f.down < HOLD_TICKS or not C.opt.spill.value or not TrailerCargo.Sandbox.carSpill() then return end
  local now = getTimestampMs()
  if now - f.at < SPILL_RETRY_MS then return end
  local part = v:getPartById(row.part)
  local loaded = false
  for w = 1, #row.slots do
    if part and slotRef(part, w) then loaded = true end
  end
  if not loaded then return end
  f.at = now
  local player = C.localPlayer()
  if player then sendClientCommand(player, Tr.MODULE, "carSpill", { vehicle = id }) end
  if C.debug() then C.log(string.format("car spill requested for %d, up vector %.2f", id, v:getUpVectorDot())) end
end

-- Multiplayer: a car the server spilled for this client to throw (it
-- holds the collide authority). The car arrives a few ticks after the
-- command; given up after THROW_WAIT ticks.
local THROW_WAIT = 300
---@type { args: table, left: integer }[]
local throws = {}
local tv = Vector3f.new()

local function onServerCommand(module, command, args)
  if module ~= Tr.MODULE or command ~= "carThrow" or type(args) ~= "table" then return end
  throws[#throws + 1] = { args = args, left = THROW_WAIT }
end

local function throwPending()
  if #throws == 0 then return end
  local keep = {}
  for _, t in ipairs(throws) do
    local car = getVehicleById(math.floor(tonumber(t.args.car) or -1))
    local trailer = getVehicleById(math.floor(tonumber(t.args.trailer) or -1))
    local sp = CT.unpackPose(t.args)
    local player = C.localPlayer()
    if car and trailer and sp and player and car:getCurrentSquare() then
      car:authorizationClientCollide(player)
      trailer:getLinearVelocity(tv)
      CT.throwCar(car, trailer, sp, { tv:x(), tv:y(), tv:z() })
      if C.debug() then C.log(string.format("car %d thrown from %d after %d ticks", car:getId(), trailer:getId(), THROW_WAIT - t.left)) end
    else
      t.left = t.left - 1
      if t.left > 0 then
        keep[#keep + 1] = t
      elseif C.debug() then
        C.log("car throw given up: car " .. tostring(t.args.car) .. " never arrived")
      end
    end
  end
  throws = keep
end

local ticks = 0
local function onTick()
  throwPending()
  ticks = ticks + 1
  if ticks % FLIP_TICKS == 0 then
    for _, e in pairs(flipWatch) do
      if e.v:getCurrentSquare() then watchFlip(e.v, e.row) end
    end
  end
  local now = getTimestampMs()
  for id, f in pairs(flips) do
    local crec = now - f.at < SPILL_FAST_MS and C.cars[id] or nil
    if crec and crec.vehicle:getCurrentSquare() then refresh(crec) end
  end
  if ticks < 30 then return end
  ticks = 0
  local on = not C.opt.cars or C.opt.cars.value
  local seen = {}
  local watched = {}
  local it = getCell():getVehicles():iterator()
  while it:hasNext() do
    local v = it:next()
    local row = TrailerCargo.CarTrailers[v:getScriptName()]
    if row and near(v) then
      watched[v:getId()] = { v = v, row = row }
      if on then
        local id = v:getId()
        ---@type TrailerCargo.CarRec|nil
        local crec = C.cars[id]
        if crec and crec.vehicle ~= v then
          C.cars[id] = nil
          crec = nil
        end
        crec = crec or trackCar(v, row)
        if crec then
          seen[id] = true
          refresh(crec)
        end
      end
    end
  end
  flipWatch = watched
  for id in pairs(flips) do
    if not watched[id] then flips[id] = nil end
  end
  ---@type number[]
  local gone = {}
  for id in pairs(C.cars) do
    if not seen[id] then gone[#gone + 1] = id end
  end
  for i = 1, #gone do
    local crec = C.cars[gone[i]]
    -- still in the world (out of range, or the option went off): give the
    -- W900 mod its covers back
    if crec and crec.vehicle:getCurrentSquare() then clearAll(crec) end
    C.cars[gone[i]] = nil
  end
end

-- "Log cars here": what each position shows and what was left out.
---@param crec TrailerCargo.CarRec
function C.dumpCars(crec)
  local L = C.carLayout(crec)
  C.log(string.format("cars on %s id %d, layout rev %d", crec.vehicle:getScriptName(), crec.id, L.rev))
  for p = 1, #crec.row.slots do
    local w = L.map[p]
    local ref = slotRef(crec.part, w)
    local d = crec.drawn[p]
    local pose = CT.poseAt(L, p)
    C.log(string.format("  position %d <- W900 slot %d: %s  %s  pose %.3f %.3f %.3f yaw %.1f", p, w,
      ref and tostring(ref.scriptName) or "empty", d and (d.label .. ", " .. #d.models .. " models") or "not drawn",
      pose.x, pose.y, pose.z, pose.yaw))
    for _, s in ipairs(crec.skipped[p] or {}) do C.log("    skipped " .. s) end
  end
end

Events.OnTick.Add(onTick)
Events.OnServerCommand.Add(onServerCommand)
Events.OnPostRender.Add(onPostRender)
