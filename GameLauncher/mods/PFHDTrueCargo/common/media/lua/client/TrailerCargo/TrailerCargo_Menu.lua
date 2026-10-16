-- TrailerCargo_Menu: the right-click entries, the radial slice, the debug
-- dump. Arrange itself lives in TrailerCargo_Arrange.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Client = TrailerCargo.Client or {}

---@class (partial) TrailerCargo.Client
local C = TrailerCargo.Client
local B, P, Tr = TrailerCargo.Bed, TrailerCargo.Pack, TrailerCargo.Trunk

local BED_REACH = 2   -- arrange reach, tiles from the bed's edge

---@param vehicle BaseVehicle|nil
---@return TrailerCargo.Rec|nil
function C.recFor(vehicle)
  if not vehicle then return nil end
  return C.tracked[vehicle:getId()]
end

-- The vehicle on any clicked square, else the one the player is near.
---@return BaseVehicle|nil
function C.vehicleAt(playerNum, worldobjects)
  if worldobjects then
    for _, obj in ipairs(worldobjects) do
      local sq = obj:getSquare()
      local v = sq and sq:getVehicleContainer()
      if v then return v end
    end
  end
  local player = getSpecificPlayer(playerNum)
  return player and player:getNearVehicle() or nil
end

-- Within reach of the BED, not the vehicle's origin (a pickup's is mid-cab).
---@param player IsoGameCharacter
---@param rec TrailerCargo.Rec
local function withinReach(player, rec)
  local px, _, pz = C.worldToPart(rec, C.frame(rec), player:getX(), player:getY(), player:getZ())
  return px ~= nil and pz ~= nil and B.bedDistance(rec.bed, px, pz, rec.ms) <= BED_REACH
end

-- BaseVehicle:isStopped() reads the controller, nil while the vehicle has
-- no physics body on this client; the speed getter checks for it.
---@param vehicle BaseVehicle
function C.isStopped(vehicle)
  if not vehicle:getController() then return vehicle:getCurrentAbsoluteSpeedKmHour() < 0.8 end
  return vehicle:isStopped()
end

---@param player IsoGameCharacter
---@param rec TrailerCargo.Rec
function C.canArrange(player, rec)
  local layout = Tr.layoutOf(rec.part)
  return not rec.covered and C.isStopped(rec.vehicle) and rec.vehicle:getUpVectorDot() > 0.9
    and withinReach(player, rec) and #layout.list > 0
end

-- Trunk items the bed does not show, with why; read every frame the trunk
-- page is open, so cached against rev, item count and size classes.
---@param rec TrailerCargo.Rec
---@return integer, string
function C.notShown(rec)
  local layout = Tr.layoutOf(rec.part)
  local hide, sig = C.hideSizes()
  local key = tostring(layout.rev) .. "/" .. rec.container:getItems():size() .. "/" .. sig
  if rec.nsKey == key and rec.nsN and rec.nsWhy then return rec.nsN, rec.nsWhy end
  local all = Tr.list(rec.container, nil)
  local onBed = {}
  for i = 1, #layout.list do
    local e = layout.list[i]
    for j = 1, #e.ids do onBed[e.ids[j]] = true end
  end
  local drawn = {}
  for _, it in ipairs(Tr.filter(all, layout, TrailerCargo.Bounds, rec.ms, hide)) do drawn[it.id] = true end
  local hidden, floored, noRoom = 0, 0, 0
  local hid = layout.hidden or {}
  for i = 1, #all do
    local id = all[i].id
    if hid[id] then hidden = hidden + 1
    elseif not onBed[id] then noRoom = noRoom + 1
    elseif not drawn[id] then floored = floored + 1 end
  end
  local _, noModel = Tr.modelless(rec.container)
  local parts = {}
  if hidden > 0 then parts[#parts + 1] = hidden .. " " .. getText("UI_TrailerCargo_Why_Hidden") end
  if noRoom > 0 then parts[#parts + 1] = noRoom .. " " .. getText("UI_TrailerCargo_Why_NoRoom") end
  if noModel > 0 then parts[#parts + 1] = noModel .. " " .. getText("UI_TrailerCargo_Why_NoModel") end
  if floored > 0 then parts[#parts + 1] = floored .. " " .. getText("UI_TrailerCargo_Why_Small") end
  rec.nsKey, rec.nsN, rec.nsWhy = key, hidden + floored + noRoom + noModel, table.concat(parts, "\n")
  rec.nsText = getText("UI_TrailerCargo_NotShown", rec.nsN)
  return rec.nsN, rec.nsWhy
end

-- Everything the mod knows about this trailer ("Log cargo here").
---@param rec TrailerCargo.Rec
function C.dump(rec)
  local layout = Tr.layoutOf(rec.part)
  local v = rec.vehicle
  C.log(string.format("dump %s id %d ms %.3f body %.4f %.4f %.4f rev %s spilled %s dot %.3f localPhysics %s",
    v:getScriptName(), rec.id, rec.ms, rec.body.x, rec.body.y, rec.body.z, tostring(layout.rev),
    tostring(layout.spilled), v:getUpVectorDot(), tostring(v:isLocalPhysicSim())))
  local bed = rec.bed
  local sealed = B.sealed(bed, Tr.installedType(v))
  C.log(string.format("  bed part %s floor %.3f x %.3f..%.3f z %.3f..%.3f hitch %d rail %.3f humps %d%s%s",
    bed.part, bed.floor, bed.x[1], bed.x[2], bed.z[1], bed.z[2], bed.hitch, bed.rail,
    bed.humps and #bed.humps or 0, rec.covered and " COVERED (nothing drawn)" or "",
    (sealed and not rec.covered) and " TARP ON (no spill)" or ""))
  -- the frame arrange mode sees; a level trailer shows y axis 0 0 1.000
  if C.frame then
    local K = B.WORLD_FLOOR
    local fr = C.frame(rec)
    C.log(string.format("  frame o %.3f %.3f %.3f  x %.3f %.3f %.3f  y %.3f %.3f %.3f  z %.3f %.3f %.3f  vehicle z %.3f  det %.2f",
      fr.ox, fr.oy, fr.oz, fr.xx, fr.xy, fr.xz * K, fr.yx, fr.yy, fr.yz * K, fr.zx, fr.zy, fr.zz * K,
      v:getZ(), B.det3(B.sceneFrame(fr))))
  end
  local trunk = Tr.list(rec.container, layout)
  local _, nRemoved, added = P.diff(layout, trunk)
  C.log(string.format("  trunk %d with a model; layout entries %d; diff removed %d added %d; sig %s",
    #trunk, #layout.list, nRemoved, #added, rec.lastSig))
  local ctx = C.ctx(rec)
  local items = Tr.itemsById(rec.container)
  for i = 1, #layout.list do
    local e = layout.list[i]
    local hx, hz, ox, oz = B.footprint(TrailerCargo.Bounds, e.m, rec.ms)
    local r = B.rect(e.x, e.z, e.yaw, hx, hz, ox, oz)
    local gap = math.min(r.minx - bed.x[1], bed.x[2] - r.maxx, r.minz - bed.z[1], bed.z[2] - r.maxz)
    local top = bed.floor + P.topOf(e, ctx)
    -- a model no table measured packs in Bed.DEFAULT_BOX whatever it draws as
    local guessed = B.entry(TrailerCargo.Bounds, e.m)[7] and " GUESSED SIZE (no bounds row)" or ""
    -- the item's own texture where the model script names none
    local first = items[e.ids[1]]
    local tex = first and Tr.textureOf(first, e.m)
    local texNote = tex and (" tex " .. tex) or ""
    -- the weight the packer ranks by (the item plus its contents), plus the size it makes
    local w = first and first:getUnequippedWeight() or 0
    texNote = string.format(" w %.1f size %.3f", w, P.sizeOf(e.m, w, ctx)) .. texNote .. (e.free and " FREE" or "")
    C.log(string.format("  [%d] %s x %.3f z %.3f yaw %.1f lift %.3f lean %.1f %.1f ids %d shown %s  size %.3fx%.3f gap %.3f top %.3f%s%s%s",
      i, e.m, e.x, e.z, e.yaw, e.y or 0, e.rx or 0, e.rz or 0, #e.ids, tostring(rec.layers[e.ids[1]] ~= nil),
      hx * 2, hz * 2, gap, top, top > bed.rail and " ABOVE RAIL" or "", guessed, texNote))
  end
  -- in the trunk but not on the bed
  for i = 1, #trunk do
    local t = trunk[i]
    if not P.entryOf(layout, t.id) then
      C.log(string.format("  unplaced id %d %s", t.id, t.m))
    end
  end
  if layout.hidden then
    local ids, k = {}, 0
    for id in pairs(layout.hidden) do
      k = k + 1
      ids[k] = tostring(id)
    end
    if k > 0 then C.log("  hidden by the player: " .. table.concat(ids, ", ")) end
  end
  local none, nNone = Tr.modelless(rec.container)
  if nNone > 0 then
    local names, k = {}, 0
    for t, c in pairs(none) do
      k = k + 1
      names[k] = t .. " x" .. c
    end
    C.log("  no model at all (or Trunk.HIDDEN), so never drawn: " .. nNone .. " item(s) - " .. table.concat(names, ", "))
  end
  local shown = 0
  for _ in pairs(rec.layers) do shown = shown + 1 end
  C.log("  layers shown " .. shown .. " of cap " .. tostring(C.opt.max.value))
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
  if test then return end
  local vehicle = C.vehicleAt(playerNum, worldobjects)
  local crec = C.carRecFor and vehicle and C.carRecFor(vehicle)
  if crec then
    local player = getSpecificPlayer(playerNum)
    if player and C.canArrangeCars(player, crec) then
      context:addOption(getText("UI_TrailerCargo_ArrangeCars"), playerNum, C.startCarArrange, crec)
    end
    if C.debug() then context:addOption(getText("UI_TrailerCargo_Debug_LogCars"), crec, C.dumpCars) end
    return
  end
  local rec = C.recFor(vehicle)
  if not rec then return end
  local player = getSpecificPlayer(playerNum)
  if C.startArrange and player and C.canArrange(player, rec) then
    context:addOption(getText("UI_TrailerCargo_Arrange"), playerNum, C.startArrange, rec)
  end
  if C.debug() then
    context:addOption(getText("UI_TrailerCargo_Debug_Log"), rec, C.dump)
  end
end

-- The tracked trailer whose BED container is this one, or nil: a
-- trailer's other containers (a toolbox part) are not cargo.
---@param c ItemContainer|nil
---@return TrailerCargo.Rec|nil
local function trunkRec(c)
  local part = c and c:getVehiclePart()
  local rec = part and C.recFor(part:getVehicle())
  if rec and rec.container == c then return rec end
  return nil
end

-- The trailer whose trunk holds every one of these items, or nil.
---@param items InventoryItem[]
---@return TrailerCargo.Rec|nil
local function trunkOf(items)
  local rec
  for _, item in ipairs(items) do
    local r = trunkRec(item:getContainer())
    if not r or (rec and r ~= rec) then return nil end
    rec = r
  end
  return rec
end

-- One hide command per item (args are scalars only), one batch; the
-- server reconciles, the client's next check sees the new rev.
---@param rec TrailerCargo.Rec
---@param items InventoryItem[]
function C.hideItems(playerNum, rec, items, on)
  local player = getSpecificPlayer(playerNum)
  if not player then return end
  local layout = Tr.layoutOf(rec.part)
  local batch = getTimestamp() * 1000 + math.floor(getTimestampMs() % 1000)
  for _, item in ipairs(items) do
    sendClientCommand(player, Tr.MODULE, "hide", {
      vehicle = rec.id, base = layout.rev, batch = batch, id = item:getID(), on = on,
    })
  end
  C.markDirty(rec.id)
end

-- The trunk's own inventory: show, hide or arrange the selection.
local function onFillInventoryObjectContextMenu(playerNum, context, items)
  local actual = ISInventoryPane.getActualItems(items)
  if #actual == 0 then return end
  local rec = trunkOf(actual)
  if not rec then return end
  local layout = Tr.layoutOf(rec.part)
  local hidden = layout.hidden or {}
  local anyOnBed, anyNotDrawn = false, false
  for _, item in ipairs(actual) do
    local id = item:getID()
    if not hidden[id] and P.entryOf(layout, id) then anyOnBed = true end
    -- an item with no model can never be drawn: no Show for it
    if not rec.layers[id] and Tr.modelOf(item) then anyNotDrawn = true end
  end
  -- Show for anything not drawn, Hide for anything on the bed
  if anyNotDrawn then
    context:addOption(getText("UI_TrailerCargo_Show"), playerNum, C.hideItems, rec, actual, false)
  end
  if anyOnBed then
    context:addOption(getText("UI_TrailerCargo_Hide"), playerNum, C.hideItems, rec, actual, true)
  end
  local player = getSpecificPlayer(playerNum)
  -- Arrange only for an item drawn now; the session opens with it selected
  local first = actual[1]:getID()
  if C.startArrange and player and rec.layers[first] and C.canArrange(player, rec) then
    context:addOption(getText("UI_TrailerCargo_Arrange"), playerNum, C.startArrange, rec, first)
  end
end

-- The radial slice is added after vanilla builds the menu. Wrapped at
-- OnGameStart: this file loads before ISVehicleMenu exists.
local wrapped = false

local function wrapRadialMenu()
  if wrapped or not ISVehicleMenu or not ISVehicleMenu.showRadialMenuOutside then return end
  wrapped = true
  local vanillaOutside = ISVehicleMenu.showRadialMenuOutside
  ISVehicleMenu.showRadialMenuOutside = function(playerObj)
    vanillaOutside(playerObj)
    if not C.startArrange then return end
    local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu or not menu:isReallyVisible() then return end
    local crec = C.carRecFor and vehicle and C.carRecFor(vehicle)
    if crec then
      if C.canArrangeCars(playerObj, crec) then
        menu:addSlice(getText("UI_TrailerCargo_ArrangeCars"), getTexture("media/ui/vehicles/vehicle_repair.png"),
          C.startCarArrange, playerObj:getPlayerNum(), crec)
      end
      return
    end
    local rec = C.recFor(vehicle)
    if not rec or not C.canArrange(playerObj, rec) then return end
    menu:addSlice(getText("UI_TrailerCargo_Arrange"), getTexture("media/ui/vehicles/vehicle_repair.png"),
      C.startArrange, playerObj:getPlayerNum(), rec)
  end
end

-- The trunk page's title bar shows the "not on the bed" count, centred;
-- hovering it lists the reasons. Drawn in `render`, after the children, so
-- the item list does not paint over them. Wrapped at OnGameStart.
local pageWrapped = false

local function wrapInventoryPage()
  if pageWrapped or not ISInventoryPage then return end
  pageWrapped = true
  local vanillaRender = ISInventoryPage.render
  ISInventoryPage.render = function(self)
    vanillaRender(self)
    if self.onCharacter or not self.inventoryPane then return end
    local rec = trunkRec(self.inventoryPane.inventory)
    if not rec then return end
    local n, why = C.notShown(rec)
    if n == 0 then return end
    local text = rec.nsText or ""
    local tm = getTextManager()
    local fontHgt = tm:getFontHeight(UIFont.Small)
    local barH = self:titleBarHeight()
    local wid = tm:MeasureStringX(UIFont.Small, text)
    local left = math.floor((self.width - wid) / 2)
    self:drawText(text, left, (barH - fontHgt) / 2, 1, 0.85, 0.5, 1, UIFont.Small)
    local mx, my = getMouseX() - self:getAbsoluteX(), getMouseY() - self:getAbsoluteY()
    if my >= 0 and my <= barH and mx >= left and mx <= left + wid then
      local lines, k, whyWid = {}, 0, 0
      for line in string.gmatch(why, "[^\n]+") do
        k = k + 1
        lines[k] = line
        whyWid = math.max(whyWid, tm:MeasureStringX(UIFont.Small, line))
      end
      local bx = math.floor((self.width - whyWid) / 2)
      self:drawRect(bx - 6, barH, whyWid + 12, k * (fontHgt + 2) + 6, 0.9, 0, 0, 0)
      for i = 1, k do
        self:drawText(lines[i], bx, barH + 3 + (i - 1) * (fontHgt + 2), 1, 1, 1, 1, UIFont.Small)
      end
    end
  end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
Events.OnGameStart.Add(wrapRadialMenu)
Events.OnGameStart.Add(wrapInventoryPage)
