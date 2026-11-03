-- media/lua/client/TrueCigs_PackSmoke.lua
-- "Smoke" on a brand PACK. The pack itself stays non-smokable (compat-spec A.2: a smokable pack would make True Smoking hand out a generic
-- Base.CigaretteSingle and would send it to IDNAL's vanilla eat action), so this is only a shortcut: start the pack's own TCTake_<Id> recipe with an
-- eat percentage of 100. TrueCigs.Recipes.takeFromPack ends in vanilla's RecipeCodeOnCreate.openAndEat, which queues ISEatFoodAction on the new brand
-- single: a vanilla smoke, or True Smoking's LightSmoke when it is installed (in MP the server sends that queueing to the client itself).
require 'TrueCigs_Brands'

TrueCigs = TrueCigs or {}
local TC = TrueCigs
TC.PackSmoke = TC.PackSmoke or {}
local PS = TC.PackSmoke

-- what the brand single's RequireInHandOrInventory accepts; checked like vanilla's own Smoke entry (ISInventoryPaneContextMenu.doEatOption)
local LIGHTS = { "Base.Lighter", "Base.LighterDisposable", "Base.LighterBBQ", "Base.Lighter_Battery", "Base.Matches", "Base.Matchbox", "Base.CandleLit" }
local function notEmpty(item) return item:getCurrentUsesFloat() > 0 end

function PS.hasLight(p)
  local v = p:getVehicle()
  if v and v:canLightSmoke(p) then return true end
  if ISInventoryPaneContextMenu.hasOpenFlame(p) then return true end
  local inv = p:getInventory()
  for _, t in ipairs(LIGHTS) do
    if inv:getFirstTypeEvalRecurse(t, notEmpty) then return true end
  end
  return false
end

--- First brand pack in the clicked selection (entries are InventoryItems or stack tables, as in vanilla's own handlers), or nil.
function PS.packIn(items)
  for _, v in ipairs(items) do
    local it = v
    if not instanceof(v, "InventoryItem") then it = v.items and v.items[1] end
    if it and TC.kindOf and TC.kindOf[it:getFullType()] == "pack" then return it end
  end
end

--- Run the pack's own Take recipe and eat what it makes (see header).
function PS.smoke(pack, playerNum)
  local p = getSpecificPlayer(playerNum)
  local brand = TC.byType[pack:getFullType()]
  if not (p and brand) then return end
  local want = "TCTake_" .. brand.id
  local recipes = CraftRecipeManager.getUniqueRecipeItems(pack, p, ISInventoryPaneContextMenu.getContainers(p))
  for i = 0, recipes:size() - 1 do
    local r = recipes:get(i)
    if r:getName() == want then ISInventoryPaneContextMenu.OnNewCraft(pack, r, playerNum, false, 100); return end
  end
end

local function fill(playerNum, context, items)
  local pack = PS.packIn(items)
  if not pack then return end
  local p = getSpecificPlayer(playerNum)
  local opt = context:addOptionOnTop(getText("ContextMenu_Smoke"), pack, PS.smoke, playerNum)
  local ts = p:getModData().TrueSmoking                -- plain ModData read: True Smoking's own flag, nil when it is absent
  if ts and ts.isSmoking then opt.notAvailable = true; return end
  if not PS.hasLight(p) then
    opt.notAvailable = true
    local tip = ISInventoryPaneContextMenu.addToolTip()
    tip.description = getText("ContextMenu_Require", getItemNameFromFullType("Base.Lighter") .. "/" .. getItemNameFromFullType("Base.Matches"))
    opt.toolTip = tip
  end
end

Events.OnFillInventoryObjectContextMenu.Add(fill)
