-- TrailerCargo_Options: PZAPI.ModOptions, registered at file scope (MainOptions
-- reads it when it builds its page).
---@class (partial) TrailerCargo
---@field Client TrailerCargo.Client
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class (partial) TrailerCargo.Client
---@field startArrange nil|fun(playerNum: integer, rec: TrailerCargo.Rec)
local C = TrailerCargo.Client or {}
TrailerCargo.Client = C

-- Mod id PFHDTrueCargo; the code keeps the name TrailerCargo (saves carry it).

-- A mod is active under its id, which Build 42 may prefix with a backslash.
local function modActive(id)
  local mods = getActivatedMods()
  for i = 0, mods:size() - 1 do
    local m = mods:get(i)
    if m == id or m == "\\" .. id then return true end
  end
  return false
end

local options = PZAPI.ModOptions:create("PFHDTrueCargo", "True Cargo")
options:addDescription("UI_TrailerCargo_Desc")
C.opt = {
  enabled = options:addTickBox("enabled", getText("UI_TrailerCargo_Enabled"), true,
    getText("UI_TrailerCargo_Enabled_tooltip")),
  -- Off is Free mode: drops land scattered. The dropping player's setting wins.
  auto = options:addTickBox("auto", getText("UI_TrailerCargo_Auto"), true,
    getText("UI_TrailerCargo_Auto_tooltip")),
  -- Every add or remove rebuilds the vehicle's sub-model list: the cap bounds
  -- the worst tick.
  max = options:addSlider("max", getText("UI_TrailerCargo_Max"), 8, 128, 8, 64,
    getText("UI_TrailerCargo_Max_tooltip")),
  -- Which size classes not to draw (Trunk.sizeClass).
  hideTiny = options:addTickBox("hideTiny", getText("UI_TrailerCargo_HideTiny"), false,
    getText("UI_TrailerCargo_HideSize_tooltip")),
  hideSmall = options:addTickBox("hideSmall", getText("UI_TrailerCargo_HideSmall"), false,
    getText("UI_TrailerCargo_HideSize_tooltip")),
  hideMedium = options:addTickBox("hideMedium", getText("UI_TrailerCargo_HideMedium"), false,
    getText("UI_TrailerCargo_HideSize_tooltip")),
  hideLarge = options:addTickBox("hideLarge", getText("UI_TrailerCargo_HideLarge"), false,
    getText("UI_TrailerCargo_HideSize_tooltip")),
  -- On: a trailer is neither repacked nor redrawn while a transfer of this
  -- client's touches its trunk (C.transferBusy).
  wait = options:addTickBox("wait", getText("UI_TrailerCargo_Wait"), false,
    getText("UI_TrailerCargo_Wait_tooltip")),
  spill = options:addTickBox("spill", getText("UI_TrailerCargo_Spill"), true,
    getText("UI_TrailerCargo_Spill_tooltip")),
  -- Off by default: adds "Log cargo here" to the right-click menu.
  debug = options:addTickBox("debug", getText("UI_TrailerCargo_Debug"), false,
    getText("UI_TrailerCargo_Debug_tooltip")),
}
-- Cars on the car trailer (TrailerCargo_CarDraw): offered only with the W900
-- Semi-Truck mod on, which has the car trailer. Without the tickbox cars draw.
if modActive("rSemiTruck") then
  C.opt.cars = options:addTickBox("cars", getText("UI_TrailerCargo_Cars"), true, getText("UI_TrailerCargo_Cars_tooltip"))
end

function C.log(msg)
  print("[TrailerCargo] " .. msg)
end

-- The size classes this client does not draw, plus a signature for caches.
---@return table<integer, boolean>, string
function C.hideSizes()
  local h = {
    C.opt.hideTiny.value == true, C.opt.hideSmall.value == true,
    C.opt.hideMedium.value == true, C.opt.hideLarge.value == true,
  }
  return h, (h[1] and "1" or "0") .. (h[2] and "1" or "0") .. (h[3] and "1" or "0") .. (h[4] and "1" or "0")
end

function C.debug()
  return C.opt.debug.value == true
end
