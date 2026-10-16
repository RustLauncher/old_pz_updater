-- media/lua/shared/TrueCigs_Effects.lua
-- VANILLA-PATH delivery of brand extras. Runs where ISEatFoodAction:complete() runs: SP in-process, dedicated server in MP (never on a pure MP client).
-- Under True Smoking this wrapper is never reached for a smoke: TS's ISEatFoodAction:new returns a LightSmoke instead (TS_Hooks.lua:182-201),
-- so ISEatFoodAction:complete() never executes for it -> no double application. The TS path is client/TrueCigs_TrueSmoking.lua.
require 'TimedActions/ISEatFoodAction'
require 'TrueCigs_Brands'

TrueCigs = TrueCigs or {}
local TC = TrueCigs
TC.Effects = TC.Effects or {}
local FX = TC.Effects

local function opts() return SandboxVars and SandboxVars.TrueCigs or nil end

--- Debug trace: set `TrueCigs.DEBUG = true` from the in-game Lua console (debug mode) to see which path delivered what.
function FX.debug(msg) if TC.DEBUG then print("[TrueCigs] " .. tostring(msg)) end end

--- Sandbox scale for ALL extras (both paths). 1.0 if the option is absent.
function FX.scale()
  local o = opts()
  local s = o and o.EffectScale
  if type(s) ~= "number" then return 1.0 end
  return s
end

--- Sandbox master switch for extras (both paths). Default on.
function FX.enabled()
  local o = opts()
  return not (o and o.BrandExtras == false)
end

--- Flattened extras list for this character class (see TrueCigs_Brands.lua rebuildIndex).
function FX.listFor(brand, isSmoker)
  if not brand then return nil end
  return isSmoker and brand._xs or brand._xn
end

--- Apply `fraction` (0..1) of the brand's per-cigarette extras directly to the character's stats. Vanilla path: fraction = 1.
function FX.applyNow(character, brand, fraction)
  if isClient() then return end                       -- MP client: server is stat-authoritative (NetworkPlayerManager pushes stats every 1 s)
  if not character or not FX.enabled() then return end
  local list = FX.listFor(brand, character:hasTrait(CharacterTrait.SMOKER))
  if not list or #list == 0 then return end
  local stats = character:getStats()
  local k = FX.scale() * (fraction or 1.0)
  for i = 1, #list do
    local cs = CharacterStat[list[i].stat]            -- same string indexing TS's server uses (server/Smoking.lua:66)
    if cs then stats:add(cs, list[i].delta * k) end   -- Stats.add clamps to the stat's own range
  end
  FX.debug(string.format("VANILLA path: %s extras x%.3f (%d stats)", tostring(brand.id), k, #list))
end

--- Infirmities2 nicotine addiction. Its own hook (ISEatFoodAction:perform, exact vanilla types only) never fires for brand singles, and True
--- Smoking bypasses that action anyway, so credit the cigarette ourselves, ONCE per cigarette: AddAddiction rolls a chance on every call.
--- Vanilla single = amount 1.5, factor 1.0 (AddPersoTraitHooks.lua:28); scaled by the brand's nicotine (ts.nicotine, 100 = vanilla).
--- AddictionsFramework is client Lua: absent on a dedicated server (ponytail: MP vanilla path is not credited; the True Smoking path runs on the client).
function FX.addiction(character, brand)
  local AF = AddictionsFramework
  if not (character and brand and AF and AF.AddAddiction) then return end
  local n = ((brand.ts and brand.ts.nicotine) or 100) / 100
  AF.AddAddiction(character, "nicotine", 1.5 * n, n)
end

--- Brand and kind ("pack"|"single"|"carton") of an inventory item, or nil. Never throws.
function FX.brandOf(item)
  if not item then return nil end
  local ok, ft = pcall(function() return item:getFullType() end)     -- same guard idiom as IDNAL (IDNALUtils.lua:81)
  if not ok or not ft or not TC.byType then return nil end
  return TC.byType[ft], TC.kindOf[ft]
end

-- Wrap ISEatFoodAction:complete exactly once per Lua environment. Chains with any other mod's wrapper (we call the captured original).
-- Only singles can arrive here (packs are drainable and non-smokable by design, cartons are not edible).
if ISEatFoodAction and not ISEatFoodAction.__tcWrapped then
  ISEatFoodAction.__tcWrapped = true
  local origComplete = ISEatFoodAction.complete
  function ISEatFoodAction:complete()
    local brand, kind = FX.brandOf(self.item)         -- resolve BEFORE the original: Eat() consumes the item
    local character, fraction = self.character, self.percentage or 1.0
    local result = origComplete(self)
    if brand and kind == "single" then
      local ok, err = pcall(FX.applyNow, character, brand, fraction)
      if not ok and not FX._warned then FX._warned = true; print("[TrueCigs] extras failed: " .. tostring(err)) end
      pcall(FX.addiction, character, brand)
    end
    return result
  end
end
