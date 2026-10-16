-- media/lua/server/TrueCigs_LootPatch.lua      (unique relative path: Lua files are keyed by lower-cased path, LuaManager.java:1201-1205)
-- Swaps vanilla cigarette entries for weighted brand entries in EVERY table ItemPickerJava.Parse() reads, whoever put the vanilla entry there
-- (vanilla, Smokes n Guns in any variant, vehicle mods, ...). Order independent: runs on events, never at file load.
require 'TrueCigs_Brands'

TrueCigs = TrueCigs or {}
local TC = TrueCigs

-- Config: pre-set any key from a shared/ file (shared loads before server) to override; sandbox cannot be used (not loaded yet at these events).
TC.Config = TC.Config or {}
do
  local defaults = {
    replacePacks = true, replaceCartons = true, replaceSingles = true,
    reviveLegacyCigarettesName = false,  -- treat "Base.Cigarettes" (does not exist in 42.21) like a pack
    keepVanillaShare = 0.0,              -- fraction of each vanilla weight left on the generic Base item
    assumedLootMod = 0.6,                -- SandboxOptions.load() runs AFTER these events (IsoWorld.java:1799-1803); presets use 0.4-1.2
    minChance = 10,                      -- every emitted entry should have c = w*100*mod >= this (ceil quantisation, see spec C.3)
    boost = {},                          -- e.g. { Viceroy = 3.0 } multiplies a brand's share before normalising
    audit = false,                       -- true: print a before/after census and a weight-conservation verdict (console.txt) on every pass
  }
  for k, v in pairs(defaults) do if TC.Config[k] == nil then TC.Config[k] = v end end
end

local VANILLA = { CigarettePack = "pack", CigaretteCarton = "carton", CigaretteSingle = "single" }   -- EXACT short names only
local FLAG    = { pack = "replacePacks", carton = "replaceCartons", single = "replaceSingles" }
local KINDS   = { "pack", "carton", "single" }
local PHI = 0.6180339887498949
local counter = 0                        -- low-discrepancy sequence index shared by all entries
local replaced = { pack = 0, carton = 0, single = 0 }

local function shortName(n) return (n:gsub("^Base%.", "")) end       -- vanilla lists use bare names, SnG/mods use "Base."

local function kindOf(name)
  local s = shortName(name)
  local k = VANILLA[s]
  if not k and s == "Cigarettes" and TC.Config.reviveLegacyCigarettesName then k = "pack" end
  if k and TC.Config[FLAG[k]] then return k end
  return nil
end

-- only brands whose script item really exists (ItemPicker silently drops unknown names, ItemPickerJava.java:421-428)
local function buildModel()
  local m = {}
  for _, kind in ipairs(KINDS) do
    local list, sum = {}, 0
    for _, b in ipairs(TC.Brands) do
      local full = b[kind]
      if full and ScriptManager.instance:getItem(full) then
        local s = b.share * (TC.Config.boost[b.id] or 1.0)
        list[#list + 1] = { item = full, share = s }
        sum = sum + s
      end
    end
    local acc, minp = 0, 1
    for _, e in ipairs(list) do
      e.p = e.share / sum
      acc = acc + e.p; e.cdf = acc
      if e.p < minp then minp = e.p end
    end
    m[kind] = { list = list, minp = minp }
  end
  TC.model = m
end

local function pick(list, u)             -- u in [0,1)
  for i = 1, #list do if u <= list[i].cdf + 1e-12 then return i end end
  return #list
end

-- one vanilla entry (kind, w) -> flat {name, weight, name, weight, ...}
local function emit(kind, w)
  local mdl = TC.model[kind]
  local list, N = mdl.list, #mdl.list
  local out = {}
  if N == 0 then return nil end          -- no brand available: keep the vanilla entry
  counter = counter + 1
  local cTotal = w * 100 * TC.Config.assumedLootMod
  if cTotal * mdl.minp >= TC.Config.minChance then
    for i = 1, N do out[#out + 1] = list[i].item; out[#out + 1] = w * list[i].p end      -- exact proportional split
  else
    local K = math.max(1, math.min(N - 1, math.floor(cTotal / TC.Config.minChance)))      -- few big entries
    local u0, acc = (counter * PHI) % 1, {}
    for j = 0, K - 1 do                                  -- systematic sampling: unbiased over the whole world
      local i = pick(list, (u0 + j / K) % 1)
      acc[i] = (acc[i] or 0) + w / K
    end
    for i = 1, N do if acc[i] then out[#out + 1] = list[i].item; out[#out + 1] = acc[i] end end  -- fixed order
  end
  return out
end

-- items array -> { [index of the NAME slot] = true }: vanilla-share entries left behind on purpose (keepVanillaShare > 0). A later pass must not
-- split them again (without this the OnInitWorld pass would turn a kept share k into k^2).
local kept = {}

-- mutate ONE items array in place (the array object may be shared by many owners: never replace the table object)
local function patchItems(items)
  local out, changed = {}, false
  local ks, nks = kept[items], {}
  for i = 1, #items, 2 do
    local name, w = items[i], items[i + 1]
    local isKept = ks and ks[i]
    local kind = (not isKept and type(name) == "string" and type(w) == "number" and w > 0) and kindOf(name) or nil
    local e = kind and emit(kind, w * (1 - TC.Config.keepVanillaShare)) or nil
    if e then
      for _, v in ipairs(e) do out[#out + 1] = v end
      if TC.Config.keepVanillaShare > 0 then nks[#out + 1] = true; out[#out + 1] = name; out[#out + 1] = w * TC.Config.keepVanillaShare end
      replaced[kind] = replaced[kind] + 1
      changed = true
    else
      if isKept then nks[#out + 1] = true end
      out[#out + 1] = name; if w ~= nil then out[#out + 1] = w end
    end
  end
  if changed then
    for i = #items, 1, -1 do items[i] = nil end          -- no holes: ItemPicker uses len()
    for i = 1, #out do items[i] = out[i] end
    kept[items] = nks
  end
end

local function sortedKeys(t)             -- Lua hash order may differ between server and client: sort for determinism
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end

local function walk(t, seen, visit)      -- identity based: ClutterTables.*, BagsAndContainers.*, room aliases, vehicle blocks are shared
  if type(t) ~= "table" or seen[t] then return end
  seen[t] = true
  if type(t.items) == "table" and not seen[t.items] then seen[t.items] = true; (visit or patchItems)(t.items) end
  for _, k in ipairs(sortedKeys(t)) do
    if k ~= "items" and k ~= "procList" then walk(t[k], seen, visit) end   -- junk, bags, rooms, containers, Normal, Specific[i], ...
  end
end

-- every root ItemPickerJava.Parse() reads; `visit(items)` defaults to the swap pass
local function walkAll(visit)
  local seen = {}
  if SuburbsDistributions then walk(SuburbsDistributions, seen, visit) end                                  -- == Distributions[1] after the merge event
  if ProceduralDistributions and ProceduralDistributions.list then walk(ProceduralDistributions.list, seen, visit) end   -- start at .list (SnG keeps a boolean table beside it)
  if VehicleDistributions and VehicleDistributions[1] then walk(VehicleDistributions[1], seen, visit) end  -- the only vehicle root Parse reads (ItemPickerJava.java:287-296)
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- Optional self-audit (TC.Config.audit = true). Same identity walk as the pass; counts entries and weights of vanilla-named vs brand-named
-- cigarette entries per kind, in total and per ProceduralDistributions list; verdict = weight conserved (only meaningful when keepVanillaShare = 0).
local function snapshot()
  local snap = { arrays = 0, odd = 0, van = {}, brand = {}, perList = {} }
  for _, k in ipairs(KINDS) do snap.van[k] = { n = 0, w = 0 }; snap.brand[k] = { n = 0, w = 0 } end
  local seen = {}
  local function scan(items, listName)
    snap.arrays = snap.arrays + 1
    if #items % 2 ~= 0 then snap.odd = snap.odd + 1 end   -- vanilla ships exactly one odd array (ClothingStorageAllJackets); only NEW ones are a failure
    local pl
    if listName then pl = snap.perList[listName]; if not pl then pl = {}; snap.perList[listName] = pl end end
    for i = 1, #items - 1, 2 do
      local name, w = items[i], items[i + 1]
      if type(name) == "string" and type(w) == "number" then
        local vk, bk = VANILLA[shortName(name)], TC.BrandIndex and TC.BrandIndex[name]
        local kind, bucket = vk or bk, nil
        if vk then bucket = snap.van[vk] elseif bk then bucket = snap.brand[bk] end
        if bucket then
          bucket.n = bucket.n + 1; bucket.w = bucket.w + w
          if pl then pl[kind] = (pl[kind] or 0) + w end
        end
      end
    end
  end
  local function awalk(t, listName)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    if type(t.items) == "table" and not seen[t.items] then seen[t.items] = true; scan(t.items, listName) end
    for k, v in pairs(t) do if k ~= "items" and k ~= "procList" and type(v) == "table" then awalk(v, listName) end end
  end
  if ProceduralDistributions and ProceduralDistributions.list then for name, t in pairs(ProceduralDistributions.list) do awalk(t, name) end end
  if SuburbsDistributions then awalk(SuburbsDistributions, nil) end
  if VehicleDistributions and VehicleDistributions[1] then awalk(VehicleDistributions[1], nil) end
  return snap
end

local function auditReport(tag, snap)
  for _, k in ipairs(KINDS) do
    print(string.format("[TrueCigs] AUDIT %s %-6s vanillaNamed n=%d w=%.4f | brandNamed n=%d w=%.4f", tag, k, snap.van[k].n, snap.van[k].w, snap.brand[k].n, snap.brand[k].w))
  end
end

local function auditCompare(pre, post)
  local bad = 0
  for _, k in ipairs(KINDS) do
    local a, b = pre.van[k].w + pre.brand[k].w, post.van[k].w + post.brand[k].w
    if math.abs(a - b) > 1e-6 then bad = bad + 1; print(string.format("[TrueCigs] AUDIT FAIL total %s weight %.6f -> %.6f", k, a, b)) end
  end
  for L, a in pairs(pre.perList) do
    local b = post.perList[L] or {}
    for _, k in ipairs(KINDS) do
      if math.abs((a[k] or 0) - (b[k] or 0)) > 1e-6 then bad = bad + 1; print(string.format("[TrueCigs] AUDIT FAIL list %s %s %.6f -> %.6f", L, k, a[k] or 0, b[k] or 0)) end
    end
  end
  if post.odd > pre.odd then bad = bad + 1; print("[TrueCigs] AUDIT FAIL new odd-length items arrays") end
  print("[TrueCigs] AUDIT compare " .. (bad == 0 and "PASS" or ("FAIL x" .. bad)))
end

function TC.patchDistributions(tag)
  if not TC.Brands or #TC.Brands == 0 then return end
  buildModel()
  replaced.pack, replaced.carton, replaced.single = 0, 0, 0
  local pre = TC.Config.audit and snapshot() or nil
  walkAll()
  print(string.format("[TrueCigs] distribution pass '%s' done: swapped pack=%d carton=%d single=%d", tostring(tag), replaced.pack, replaced.carton, replaced.single))
  if pre then
    local post = snapshot()
    if not TC._auditShown then TC._auditShown = true; auditReport("pre-" .. tostring(tag), pre); auditReport("post-" .. tostring(tag), post) end
    auditCompare(pre, post)
  end
end

Events.OnPostDistributionMerge.Add(function() TC.patchDistributions("post") end)   -- after Pre+Merge: sees every mod's inserts and the merged addon tables
Events.OnInitWorld.Add(function() TC.patchDistributions("initworld") end)          -- idempotent net for handlers registered after ours; still before Parse() (IsoWorld.java:1798-1805)

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- SANDBOX SPAWN RATES (TrueCigs.LootRate = every brand, TrueCigs.Rate_<brand id> = one brand; the two multiply, 0 removes). SandboxVars only hold the real values AFTER
-- SandboxOptions.load() (IsoWorld.java:1801), but Parse() has already run (1805) on the tables built above, so the passes above cannot use them.
-- OnInitGlobalModData (IsoWorld.java:1908, still world init; SP, host and dedicated server) is the first event with valid values: scale OUR entries
-- in place and have the game re-read the tables, the way GydeTraitMagazines / Talis New Music do. At the defaults (everything 1.0) nothing is touched and
-- Parse() is not re-run. Weights are independent roll chances (spec E8): x2 = twice the chance per roll, capped at 100 percent by the engine.
-- ponytail: rate 0 deletes the entries for this session (reload the world to get them back); values below about 0.1 are rounded up by the engine's
-- ceil() quantisation (compat-spec C.3).
local built = setmetatable({}, { __mode = "k" })   -- items array -> { [index of a brand weight] = the weight the passes above built }

local function scaleItems(items, rate, per)
  local base = built[items]
  if not base then
    base = {}
    for i = 1, #items - 1, 2 do
      if TC.byType[items[i]] and type(items[i + 1]) == "number" then base[i + 1] = items[i + 1] end
    end
    built[items] = base
  end
  local function factor(i)
    local b = TC.byType[items[i - 1]]
    return rate * ((b and per[b.id]) or 1.0)
  end
  local drop = false
  for pos, w0 in pairs(base) do
    local f = factor(pos)
    if f > 0 then items[pos] = w0 * f else drop = true end
  end
  if drop then                                    -- no holes: ItemPicker uses len()
    local out = {}
    for i = 1, #items - 1, 2 do
      if not (base[i + 1] and factor(i + 1) <= 0) then out[#out + 1] = items[i]; out[#out + 1] = items[i + 1] end
    end
    for i = #items, 1, -1 do items[i] = nil end
    for i = 1, #out do items[i] = out[i] end
    built[items] = nil
  end
end

local function rateOf(v)                          -- missing / nonsense -> 1.0 (as designed)
  v = tonumber(v)
  return (v and v >= 0) and v or 1.0
end

function TC.applySandboxLoot()
  if not TC.Brands or #TC.Brands == 0 then return end
  local o = SandboxVars and SandboxVars.TrueCigs
  local rate, per, key, odd = rateOf(o and o.LootRate), {}, {}, false
  for _, b in ipairs(TC.Brands) do
    per[b.id] = rateOf(o and o["Rate_" .. b.id])                 -- one slider per brand; 0 = never spawns
    key[#key + 1] = per[b.id]
    if per[b.id] ~= 1.0 then odd = true end
  end
  key = rate .. "/" .. table.concat(key, ",")
  if TC.lootScaled == nil and rate == 1.0 and not odd then return end         -- defaults: tables stay as built, no re-parse
  if TC.lootScaled == key then return end                                      -- same values again (event fired twice)
  TC.lootScaled = key
  walkAll(function(items) scaleItems(items, rate, per) end)
  print(string.format("[TrueCigs] sandbox spawn rates applied to brand loot entries (all x%g; per brand: %s)", rate, odd and "some differ from 1.0" or "all 1.0"))
  if ItemPickerJava and ItemPickerJava.Parse then
    local ok, err = pcall(ItemPickerJava.Parse)
    if ok and ItemPickerJava.InitSandboxLootSettings then ok, err = pcall(ItemPickerJava.InitSandboxLootSettings) end
    if not ok then print("[TrueCigs] re-reading the loot tables failed: " .. tostring(err)) end
  end
end

Events.OnInitGlobalModData.Add(function() TC.applySandboxLoot() end)
