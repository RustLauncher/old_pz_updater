-- media/lua/shared/TrueCigs_Recipes.lua
-- OnCreate handlers for the brand "Take" / "Add" recipes. shared/ because recipe OnCreate runs server-side in MP.
-- They keep True Smoking's partial-cigarette bookkeeping working for brand items. TS's own handlers (Recipes.lua:35-117) only recognise
-- 'Base.CigarettePack' / 'Base.CigaretteSingle' by exact full type, so brand recipes MUST use these instead. Without TS the ModData
-- fields simply never exist and both functions degrade to the plain vanilla behaviour (+1 use / no restore).
-- OnCreate signature in B42.21 is (CraftRecipeData data, IsoGameCharacter character) (CraftRecipeData.java:429-437).
require 'TrueCigs_Brands'

TrueCigs = TrueCigs or {}
local TC = TrueCigs
TC.Recipes = TC.Recipes or {}
local R = TC.Recipes

local function kindOfItem(item)
  if not item or not TC.kindOf then return nil end
  return TC.kindOf[item:getFullType()]
end

--- OnCreate of `TCAdd_<Brand>`: inputs = 1 brand single (consumed) + 1 brand pack (mode:keep).
function R.addToPack(data, character)
  local inputs = data:getAllInputItems()
  local pack, cig
  for i = 0, inputs:size() - 1 do
    local it = inputs:get(i)
    local kind = kindOfItem(it)
    if kind == "pack" then pack = it elseif kind == "single" then cig = it end
  end
  if not pack then return end
  -- +1 use, same arithmetic TS uses (Recipes.lua:47-49), capped at a full pack.
  local step = pack:getUseDelta()
  if step and step > 0 then pack:setUsedDelta(math.min(1.0, pack:getCurrentUsesFloat() + step)) end
  -- remember a partly smoked single (TS writes these two fields while smoking: SmokableItem.lua:238-239, 627)
  if cig then
    local cd = cig:getModData()
    if cd.OriginalSmokeLength and cd.SmokeLength and cd.SmokeLength < cd.OriginalSmokeLength then
      local pd = pack:getModData()
      pd.Cigs = pd.Cigs or {}                           -- same key/shape TS uses (Recipes.lua:62-68)
      pd.Cigs[cig:getID()] = { OriginalSmokeLength = cd.OriginalSmokeLength, SmokeLength = cd.SmokeLength }
    end
  end
end

--- Hand back a stored partly smoked single (part of TCTake_<Brand>).
local function restorePartial(data, character)
  local inputs, outputs = data:getAllInputItems(), data:getAllCreatedItems()
  local pack
  for i = 0, inputs:size() - 1 do
    local it = inputs:get(i)
    if kindOfItem(it) == "pack" then pack = it; break end
  end
  local cigs = pack and pack:getModData().Cigs
  if not cigs then return end
  for i = 0, outputs:size() - 1 do
    local out = outputs:get(i)
    if kindOfItem(out) == "single" then
      for id, info in pairs(cigs) do                    -- hand back the first stored partial cigarette (TS Recipes.lua:104-112)
        local md = out:getModData()
        md.OriginalSmokeLength, md.SmokeLength = info.OriginalSmokeLength, info.SmokeLength
        cigs[id] = nil
        break
      end
      break
    end
  end
end

--- OnCreate of `TCTake_<Brand>`: input = 1 brand pack (one use), output = 1 brand single.
--- When the recipe was started with an eat percentage (the "Smoke" entry on a pack, client/TrueCigs_PackSmoke.lua) vanilla's own
--- RecipeCodeOnCreate.openAndEat then queues ISEatFoodAction on the new single (True Smoking turns that into its LightSmoke). It returns at once
--- when the percentage is 0, so a plain Take / the K hotkey are unaffected.
function R.takeFromPack(data, character)
  restorePartial(data, character)
  local open = RecipeCodeOnCreate and RecipeCodeOnCreate.openAndEat
  if open then pcall(open, data, character) end
end

--- OnTest of `TCPack_<Brand>` (20 singles -> new full pack): refuse partly smoked singles, otherwise 20 half-smoked cigarettes would become a
--- full pack. (Add-to-pack keeps partial cigarettes instead, see addToPack.) Called per candidate input item: (InventoryItem, IsoGameCharacter).
function R.wholeCigarettesOnly(item, character)
  if kindOfItem(item) ~= "single" then return true end
  local md = item:getModData()
  return not (md.OriginalSmokeLength and md.SmokeLength and md.SmokeLength < md.OriginalSmokeLength)
end
