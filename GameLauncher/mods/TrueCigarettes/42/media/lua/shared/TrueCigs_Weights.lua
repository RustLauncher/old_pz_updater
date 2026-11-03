-- media/lua/shared/TrueCigs_Weights.lua
-- TotalWeightRebalance (TWR) parity (compat-spec observation O1). TWR halves the vanilla cigarette weights BY FULL TYPE (Base.CigarettePack 0.2 -> 0.1,
-- Base.CigaretteCarton 2 -> 1, Base.CigaretteSingle 0.01); brand items are not in its table, so without this step a brand pack would be twice as
-- heavy as the pack the player is used to.  When TWR is active, every brand pack / carton / single copies the CURRENT script weight of its vanilla
-- counterpart (so a customised TWR preset is followed too).  Same script-item idiom TWR itself uses (ScriptManager.instance:getItem(id), setActualWeight;
-- Item.DoParam('Weight = x') is the equivalent text form).  Item weights are NOT saved with the item unless they are custom weights, so existing
-- items pick the new script weight up on the next load; items already in memory keep the weight they were created with until then.
--
-- Safety: shared/ (runs on SP, MP client and dedicated server); fully pcall-guarded; silent when TWR is absent; prints exactly one line when it
-- actually changed something.  TWR installs its weights in its own OnInitGlobalModData handler and, in MP, when the server's state arrives, and
-- Lua event handlers run in mod load order, so the sync is repeated at several events (idempotent, a few dozen table lookups) and once more one tick
-- after a TWR server command.  Switch off with TrueCigs.Config.matchTotalWeightRebalance = false.
require 'TrueCigs_Brands'

TrueCigs = TrueCigs or {}
local TC = TrueCigs
TC.Weights = TC.Weights or {}
local W = TC.Weights

local VANILLA = { pack = "Base.CigarettePack", carton = "Base.CigaretteCarton", single = "Base.CigaretteSingle" }
local KINDS = { "pack", "carton", "single" }
local TWR_IDS = { "TotalWeightRebalance", "\\TotalWeightRebalance" }     -- B42 mod ids as listed in mods.txt; the backslash form is a belt and braces guard
local TWR_COMMAND_MODULE = "TotalWeightRebalance"                        -- sendServerCommand module TWR uses for its state sync (apply_weights.lua)
local TOLERANCE = 1e-4

--- True when the TotalWeightRebalance mod is in the active mod list. Never throws.
function W.twrActive()
  local ok, res = pcall(function()
    local mods = getActivatedMods()
    if not mods then return false end
    for _, id in ipairs(TWR_IDS) do
      if mods:contains(id) then return true end
    end
    return false
  end)
  return ok and res == true
end

function W.enabled()
  local c = TC.Config
  return not (c and c.matchTotalWeightRebalance == false)
end

local function setWeight(item, w)
  local text = tostring(w)
  if text:find("^%d+%.?%d*$") then                       -- plain decimal: the documented text form
    local ok = pcall(function() item:DoParam("Weight = " .. text) end)
    if ok then return true end
  end
  return pcall(function() item:setActualWeight(w) end)  -- exponent notation / DoParam refused: TWR's own call
end

--- Copy the current vanilla cigarette script weights onto the brand items. Returns the number of items changed. Idempotent, never throws.
function W.sync(tag)
  if not W.enabled() or not W.twrActive() then return 0 end
  local changed, report = 0, {}
  local ok, err = pcall(function()
    local sm = ScriptManager and ScriptManager.instance
    if not sm or not TC.Brands then return end
    for _, kind in ipairs(KINDS) do
      local vanilla = sm:getItem(VANILLA[kind])
      local target = vanilla and vanilla:getActualWeight()
      if type(target) == "number" and target > 0 and target < 100 then
        for _, b in ipairs(TC.Brands) do
          local full = b[kind]
          local item = full and sm:getItem(full)
          if item and math.abs(item:getActualWeight() - target) > TOLERANCE and setWeight(item, target) then
            changed = changed + 1
            report[kind] = math.floor(target * 1000 + 0.5) / 1000      -- float -> double noise (0.1f = 0.10000000149) stays out of the log line
          end
        end
      end
    end
  end)
  if not ok then
    if not W._warned then W._warned = true; print("[TrueCigs] TotalWeightRebalance parity failed (ignored): " .. tostring(err)) end
    return changed
  end
  if changed > 0 and not W._announced then
    W._announced = true
    print(string.format("[TrueCigs] TotalWeightRebalance detected: brand weights follow the vanilla cigarette weights (pack %s, carton %s, single %s) [%s]",
      tostring(report.pack or "unchanged"), tostring(report.carton or "unchanged"), tostring(report.single or "unchanged"), tostring(tag)))
  end
  return changed
end

-- One more sync after the NEXT tick (the handler that triggered us may have run before TWR's own handler for the same event).
local pending = false
local function later(tag)
  if pending or not W.enabled() then return end
  pending = true
  local fn
  fn = function()
    Events.OnTick.Remove(fn)
    pending = false
    W.sync(tag)
  end
  Events.OnTick.Add(fn)
end

local function onEvent(tag)
  return function() W.sync(tag); later(tag) end
end

Events.OnInitGlobalModData.Add(onEvent("OnInitGlobalModData"))   -- TWR's own install point (all realms)
Events.OnGameStart.Add(onEvent("OnGameStart"))                   -- SP and MP client
if Events.OnServerStarted then Events.OnServerStarted.Add(onEvent("OnServerStarted")) end   -- dedicated server
if Events.OnServerCommand then                                   -- MP client: TWR's state (re)sync arrives as a server command
  Events.OnServerCommand.Add(function(module)
    if module == TWR_COMMAND_MODULE then later("TWR command") end
  end)
end
