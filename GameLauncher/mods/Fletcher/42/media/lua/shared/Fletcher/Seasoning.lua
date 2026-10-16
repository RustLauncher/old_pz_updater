--[[
    Fletcher: seasoned wood. A carved Bow Stave or Longbow Stave is green; laid on a Stave Rack (our own
    drying rack entity, Fletcher_Bench.txt, recipe group FletcherStaveRack) for 3 / 5 days it becomes a Seasoned stave (Fletcher_Recipes.txt FL_SeasonBowStave / FL_SeasonLongbowStave).
    A bow (or Hand Crossbow, or recurve limbs) made from seasoned wood is "Seasoned": F.SEASONED's
    bonus on top of the bow's usual stats. Green-wood bows are exactly the old bows: the bonus is an
    upgrade for patience, not a penalty for new players.
    Found wooden bows (loot) and bows from before this existed count as seasoned (well made): only a
    bow crafted from green wood (md.fl_crafted, no md.fl_seasoned) goes without. Compound and steel
    crossbows aren't wood.
    Recipe hooks (F.OnCreate.*) mark what they make; stable wrappers at the end (as FieldRations):
    the crafting engine keeps the function object it looked up.
]]
require "Fletcher/Core"
require "Fletcher/Fletching"
local F = Fletcher

F.SEASONED = {
    damage = 1.15,      -- x min and max damage
    range = 2,          -- + tiles
    wear = 1.5,         -- x ConditionLowerChance (one in N: higher wears slower)
}
F.WOODEN_BOWS = { ["Fletcher.SimpleBow"] = true, ["Fletcher.Longbow"] = true, ["Fletcher.RecurveBow"] = true,
                  ["Fletcher.HandCrossbow"] = true, ["Fletcher.TapedRecurveBow"] = true }
F.SEASONED_PARTS = { ["Fletcher.BowStaveSeasoned"] = true, ["Fletcher.LongbowStaveSeasoned"] = true }

--- Is this bow seasoned (the bonus applies)?
function F.bowSeasoned(bow)
    if not (bow and F.WOODEN_BOWS[bow:getFullType()]) then return false end
    local md = bow:getModData()
    if md.fl_seasoned then return true end
    return md.fl_crafted ~= true
end

--- A seasoned bow's name: "Seasoned <name>" (set once, kept in the save)
function F.nameSeasoned(bow)
    if bow:isCustomName() then return end
    bow:setName(getText("IGUI_Fletcher_SeasonedName", bow:getScriptItem():getDisplayName()))
    bow:setCustomName(true)
end

local function list(jl)
    local out = {}
    for i = 0, (jl and jl:size() or 0) - 1 do table.insert(out, jl:get(i)) end
    return out
end

--- Was any wood that went into this craft seasoned? (a seasoned stave, or limbs made from one)
local function seasonedInput(data)
    for _, it in ipairs(list(data:getAllConsumedItems())) do
        if F.SEASONED_PARTS[it:getFullType()] or it:getModData().fl_seasoned then return true end
    end
    return false
end

F.OnCreate = F.OnCreate or {}

--- A bow, crossbow or recurve limbs: crafted (green unless seasoned wood went in)
function F.OnCreate.markWood(data, character)
    local seasoned = seasonedInput(data)
    for _, it in ipairs(list(data:getAllCreatedItems())) do
        local md = it:getModData()
        md.fl_crafted = true
        md.fl_seasoned = seasoned or nil
        if seasoned and F.WOODEN_BOWS[it:getFullType()] then F.nameSeasoned(it) end
        if isServer() and syncItemModData then pcall(syncItemModData, character, it) end
    end
end

-- stable wrappers (see the header)
F.hookImpl = F.hookImpl or { OnCreate = {} }
F.hookWrapper = F.hookWrapper or { OnCreate = {} }
for name, fn in pairs(F.OnCreate) do
    if fn ~= F.hookWrapper.OnCreate[name] then F.hookImpl.OnCreate[name] = fn end
    if not F.hookWrapper.OnCreate[name] then
        F.hookWrapper.OnCreate[name] = function(...) return F.hookImpl.OnCreate[name](...) end
    end
    F.OnCreate[name] = F.hookWrapper.OnCreate[name]
end

return F
