-- TrailerCargo_Trunk: engine glue both sides share: the bed part, its
-- items, the saved layout. Functions only.
---@class (partial) TrailerCargo
---@field Trunk TrailerCargo.Trunk
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Pack = TrailerCargo.Pack or {}

---@class TrailerCargo.Trunk
local Tr = TrailerCargo.Trunk or {}
TrailerCargo.Trunk = Tr

Tr.MODULE = "TrailerCargo"

-- Items kept off the bed, by bare item type.
Tr.HIDDEN = {}

-- The model script this item draws as on the bed, or nil. A weapon with
-- only a WeaponSprite (the plank, bats) has no world model: getStaticModel
-- gives the bare sprite name, which getModelScript resolves in Base
-- (HandWeapon.java:1978). The name is kept bare or prefixed as given.
---@param item InventoryItem
---@return string|nil
function Tr.modelOf(item)
  if Tr.HIDDEN[item:getType()] then return nil end
  local m = item:getWorldStaticModel()
  if m and m ~= "" and not Tr.isNoModel(m) then return m end
  -- head-worn clothing draws its worn mesh (ItemModelRenderer :364-420);
  -- build/gen_worn.py keys a model by getModel(false), lower case, '/'
  if instanceof(item, "Clothing") then
    ---@cast item Clothing
    local worn = TrailerCargo.Worn
    if not worn or not item:canBe3DRender() then return nil end
    local ci = item:getClothingItem()
    local mesh = ci and ci:getModel(false)
    if not mesh or mesh == "" then return nil end
    local name = worn[string.lower((string.gsub(mesh, "\\", "/")))]
    return name and ("TrailerCargo." .. name) or nil
  end
  -- only a HandWeapon falls back to a hand model on the ground
  -- (ItemModelRenderer.itemHasModel); anything else is a flat sprite
  if not instanceof(item, "HandWeapon") then return nil end
  m = item:getStaticModel()
  if m and m ~= "" and not Tr.isNoModel(m) then return m end
  return nil
end

-- `WorldStaticModel = null` comes back as "Base.null": no model.
---@param m string
function Tr.isNoModel(m)
  return m == "null" or string.sub(m, -5) == ".null"
end

-- The texture for a model whose script names none, found as
-- ItemModelRenderer.init (:198-212) does: the item's texture choice, else
-- its base texture. nil when the script names its own.
---@param item InventoryItem
---@param m string  as modelOf returned it
---@return string|nil
function Tr.textureOf(item, m)
  local dot = string.find(m, ".", 1, true)
  local bare = dot and string.sub(m, dot + 1) or m
  if not (TrailerCargo.Untextured and TrailerCargo.Untextured[bare]) then return nil end
  local ci = item:getClothingItem()
  if not ci then return nil end
  local visual = item:getVisual()
  if not visual then return nil end
  local tex = visual:getTextureChoice(ci)
  if tex == nil or tex == "" then tex = visual:getBaseTexture(ci) end
  if tex == nil or tex == "" then return nil end
  return tex
end

-- The trunk part named by the bed entry, with its container, or nils.
---@param vehicle BaseVehicle
---@return VehiclePart|nil, ItemContainer|nil
function Tr.partOf(vehicle, bed)
  local part = vehicle:getPartById(bed.part)
  if not part then return nil, nil end
  local container = part:getItemContainer()
  if not container then return nil, nil end
  return part, container
end

-- The lookup Bed.covered and Bed.sealed take: the full type of the item
-- installed in a part of this vehicle, or nil.
---@param vehicle BaseVehicle
---@return fun(partId: string): string|nil
function Tr.installedType(vehicle)
  return function(partId)
    local part = vehicle:getPartById(partId)
    local item = part and part:getInventoryItem()
    return item and item:getFullType() or nil
  end
end

-- Size classes for the hide options: 1 tiny to 4 large, the larger of
-- the footprint's longer side in tiles and the weight in kg (weight keeps
-- a car battery out of "tiny").
Tr.SIZE_BANDS = { 0.2, 0.3, 0.45 }
Tr.WEIGHT_BANDS = { 0.3, 1.5, 5 }

---@param bounds table<string, TrailerCargo.BoundsEntry>
---@param m string
---@param ms number
---@param w number|nil  the item's weight, kg
---@return integer  1 to 4
function Tr.sizeClass(bounds, m, ms, w)
  local hx, hz = TrailerCargo.Bed.footprint(bounds, m, ms)
  local side = 2 * math.max(hx, hz) * ms
  local bySize = #Tr.SIZE_BANDS + 1
  for i = 1, #Tr.SIZE_BANDS do
    if side < Tr.SIZE_BANDS[i] then
      bySize = i
      break
    end
  end
  local byWeight = #Tr.WEIGHT_BANDS + 1
  for i = 1, #Tr.WEIGHT_BANDS do
    if (w or 0) < Tr.WEIGHT_BANDS[i] then
      byWeight = i
      break
    end
  end
  return math.max(bySize, byWeight)
end

-- The pure part of Tr.list: drops layout-hidden ids and the size classes
-- the player hides; "Show on trailer" (layout.shown) overrides the classes.
---@param items { id: number, m: string, w: number|nil }[]
---@param layout TrailerCargo.Layout|nil
---@param bounds table<string, TrailerCargo.BoundsEntry>|nil
---@param ms number|nil
---@param hide table<integer, boolean>|nil  size classes not to draw
---@return { id: number, m: string }[]
function Tr.filter(items, layout, bounds, ms, hide)
  local hidden = layout and layout.hidden
  local shown = layout and layout.shown
  local any = false
  if hide and bounds and ms then
    for i = 1, #Tr.SIZE_BANDS + 1 do
      if hide[i] then any = true end
    end
  end
  if not hidden and not any then return items end
  local out, n = {}, 0
  for i = 1, #items do
    local it = items[i]
    local keep = not (hidden and hidden[it.id])
    if keep and any and hide and bounds and ms and not (shown and shown[it.id]) then
      keep = not hide[Tr.sizeClass(bounds, it.m, ms, it.w)]
    end
    if keep then
      n = n + 1
      out[n] = it
    end
  end
  return out
end

-- Top-level items with a model, as the packer wants them, less the ones
-- the layout hides or the size classes keep back (Tr.filter).
---@param container ItemContainer
---@param layout TrailerCargo.Layout|nil
---@param bounds table<string, TrailerCargo.BoundsEntry>|nil
---@param ms number|nil
---@param hide table<integer, boolean>|nil
---@return { id: number, m: string }[]
function Tr.list(container, layout, bounds, ms, hide)
  local items = container:getItems()
  local out, n = {}, 0
  for i = 0, items:size() - 1 do
    local item = items:get(i)
    local m = Tr.modelOf(item)
    if m then
      n = n + 1
      -- item plus contents (getUnequippedWeight): a packed bag is heavy
      out[n] = { id = item:getID(), m = m, w = item:getUnequippedWeight() }
    end
  end
  return Tr.filter(out, layout, bounds, ms, hide)
end

-- Top-level items with NO model at all, by type, with a count (a
-- generator has only an Icon); for the debug dump.
---@param container ItemContainer
---@return table<string, integer>, integer
function Tr.modelless(container)
  local items = container:getItems()
  local out, n = {}, 0
  for i = 0, items:size() - 1 do
    local item = items:get(i)
    if not Tr.modelOf(item) then
      local t = item:getFullType()
      out[t] = (out[t] or 0) + 1
      n = n + 1
    end
  end
  return out, n
end

---@param container ItemContainer
---@return table<number, InventoryItem>
function Tr.itemsById(container)
  local items = container:getItems()
  local out = {}
  for i = 0, items:size() - 1 do
    local item = items:get(i)
    out[item:getID()] = item
  end
  return out
end

-- The saved layout on the trunk part (VehiclePart.save writes part modData;
-- the vehicle's own modData is not saved).
---@param part VehiclePart
---@return TrailerCargo.Layout
function Tr.layoutOf(part)
  local md = part:getModData()
  local layout = md.TrailerCargo
  local P = TrailerCargo.Pack
  if type(layout) == "table" and layout.v == 1 then
    -- an older format: forget its places but keep its rev, so every client
    -- still sees the repack as a change (P.LAYOUT_V)
    layout.v, layout.list = P.LAYOUT_V, {}
  elseif type(layout) ~= "table" or layout.v ~= P.LAYOUT_V then
    layout = P.newLayout()
    md.TrailerCargo = layout
  end
  if type(layout.list) ~= "table" then layout.list = {} end
  return layout
end
