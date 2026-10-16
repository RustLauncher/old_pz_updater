-- media/lua/client/TrueCigs_TrueSmoking.lua
-- TRUE SMOKING (workshop 3423984426, mod id TrueSmoking) integration. client/ only: TS reads its smokable registry and runs the burn loop client-side
-- (SmokableItem.lua:183, :793-798), and client/ Lua is never loaded on a dedicated server. No `require` of any TS file; no wrapping of any TS function.
-- Everything is wired from events, so mod load order does not matter. Detection is by feature, not by mod id.
require 'TrueCigs_Brands'
require 'TrueCigs_Effects'

TrueCigs = TrueCigs or {}
local TC = TrueCigs
TC.TS = TC.TS or {}
local TS = TC.TS
local FX = TC.Effects

local warned = {}
local function warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  print("[TrueCigs] TrueSmoking integration: " .. msg)
end

--- True when the True Smoking API we rely on exists (names verified against TS 42.20: Core.lua:277, Data.lua:36).
function TS.present()
  return type(TrueSmoking) == "table"
     and (type(TrueSmoking.registerSmokables) == "function" or type(TrueSmoking.setSmokableObjects) == "function")
     and type(TrueSmoking.Data) == "table" and type(TrueSmoking.Data.getSmoking) == "function"
end

--- Sandbox switch (default on). Off => brand singles still work through TS with TS's defaults, but get no extras and ignore EffectMultiplier.
function TS.enabled()
  local o = SandboxVars and SandboxVars.TrueCigs
  return not (o and o.TrueSmokingIntegration == false)
end

-- TS sandbox EffectMultiplier (Init.lua:168,214). Read from SandboxVars (public option), not from TS internals.
local function tsEffect()
  local o = SandboxVars and SandboxVars.TrueSmoking
  local e = o and o.EffectMultiplier
  if type(e) ~= "number" then return 1.0 end
  return e
end

-- Per-tick callback. TS calls it UNPROTECTED every tick while the cigarette is lit (SmokableItem.lua:588): an error here would stop the
-- cigarette from ever finishing, hence the pcall. s.puffPercent = fraction of the whole cigarette burnt THIS tick (game speed included,
-- SmokableItem.lua:565), so the sum over one cigarette is exactly 1.0 at any game speed => per-cigarette dose == `extras` value.
local function tick(s)
  local b = TC.byType and TC.byType[s.itemFullType]
  local pct = s.puffPercent
  if not b or type(pct) ~= "number" or pct <= 0 then return end
  if not s._tcAdd then s._tcAdd = true; pcall(FX.addiction, s.player, b) end   -- ponytail: a relit partial cigarette counts again
  if not FX.enabled() then return end
  if not s._tcSeen then s._tcSeen = true; FX.debug("TS path: callback live for " .. tostring(s.itemFullType)) end
  local player = s.player
  local list = FX.listFor(b, player:hasTrait(CharacterTrait.SMOKER))
  if not list or #list == 0 then return end
  local data = TrueSmoking.Data.getSmoking(player)
  if not data then return end
  local buf = data.statsToApply                       -- re-read every tick: TS replaces the table after each flush (client/Network.lua:162)
  if type(buf) ~= "table" then buf = {}; data.statsToApply = buf end
  local k = pct * FX.scale() * tsEffect()
  for i = 1, #list do
    local key = list[i].stat
    -- TS buffer convention (server/Smoking.lua:63-79): positive REMOVES from the stat, negative ADDS. Our deltas use stats:add() sign -> subtract.
    buf[key] = (type(buf[key]) == "number" and buf[key] or 0) - list[i].delta * k
  end
end

local function onTick(s)
  local ok, err = pcall(tick, s)
  if not ok then warnOnce("tick", "callback error (further errors suppressed): " .. tostring(err)) end
end

--- Register every brand single with TS. Idempotent (registerSmokables replaces by key, Core.lua:277-281). Safe to call repeatedly.
function TS.register()
  if not TS.present() then return false end
  if not TS.enabled() then return false end
  local opt = TrueSmoking.Options or {}
  local baseLen = type(opt.SmokeLength) == "number" and opt.SmokeLength or 1.0   -- Init.lua:203; 1.0 = one vanilla cigarette
  local baseEffect = tsEffect()
  local defs = {}
  for _, b in ipairs(TC.Brands) do
    if b.single then
      local t = b.ts or {}
      -- ONLY the keys we want to change. Everything else (burn rates, factors, conditions, visualItem) is filled from the sandbox-driven
      -- defaults in SmokableItem:loadConfig (SmokableItem.lua:200-221), which equal TS's own Base.CigaretteSingle entry.
      defs[b.single] = {
        smokeLength      = baseLen * (t.length or 1.0),
        effectMultiplier = baseEffect * (t.strength or 1.0),
        nicotineContent  = t.nicotine or 100,
        callback         = onTick,
      }
    end
  end
  local ok, err = pcall(function()
    if type(TrueSmoking.registerSmokables) == "function" then TrueSmoking.registerSmokables(defs)
    else TrueSmoking:setSmokableObjects(defs) end      -- legacy colon-style alias (Core.lua:287)
  end)
  if not ok then warnOnce("register", "registerSmokables failed: " .. tostring(err)); return false end
  if not TS.registered then print("[TrueCigs] TrueSmoking integration: registered brand singles with True Smoking") end
  TS.registered = true
  return true
end

Events.OnCreatePlayer.Add(function() TS.register() end)   -- TS registers its own six types in OnCreatePlayer too (Config.lua:14)
Events.OnGameStart.Add(function() TS.register() end)      -- second chance; registry is only read when a smoke starts
