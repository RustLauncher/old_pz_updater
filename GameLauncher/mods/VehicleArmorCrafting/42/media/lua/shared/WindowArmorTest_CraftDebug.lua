--[[
    Temporary crafting diagnostics for multiplayer.
    Wraps the vanilla crafting action and logs which side reaches which step.
    Useful to find out why inputs get consumed in MP while no output item
    is created. Can be deleted once everything works.
]]
require "WindowArmorTest_Shared"
require "Entity/TimedActions/ISHandcraftAction"

local WAT = WindowArmorTest
if not WAT.CRAFT_DEBUG or not ISHandcraftAction then return end  -- switched on in WindowArmorTest_Shared.lua

local function side()
    return isServer() and "SERVER" or (isClient() and "CLIENT" or "SP")
end

local function recipeName(self)
    local ok, name = pcall(function() return self.craftRecipe and self.craftRecipe:getName() end)
    return ok and tostring(name) or "?"
end

-- only our own recipes, so the log does not get flooded
local function ours(self)
    local n = recipeName(self)
    return string.find(n, "WAT_", 1, true) ~= nil
end

local function wrap(name)
    local orig = ISHandcraftAction[name]
    if type(orig) ~= "function" then
        WAT.log("craft-debug: no such method " .. name)
        return
    end
    ISHandcraftAction[name] = function(self, ...)
        local res = orig(self, ...)
        if ours(self) then
            WAT.log("craft-debug [" .. side() .. "] " .. name .. " recipe=" .. recipeName(self)
                .. " result=" .. tostring(res)
                .. " logic=" .. tostring(self.logic ~= nil)
                .. " bench=" .. tostring(self.craftBench ~= nil)
                .. " iso=" .. tostring(self.isoObject ~= nil))
        end
        return res
    end
end

for _, m in ipairs({ "isValid", "serverStart", "start", "perform", "complete", "performRecipe" }) do
    wrap(m)
end

WAT.log("craft-debug loaded [" .. side() .. "], DebugType.CraftLogic="
    .. tostring(DebugType ~= nil and DebugType.CraftLogic ~= nil)
    .. ", enabled=" .. tostring(DebugLog ~= nil and DebugLog.isEnabled ~= nil
        and select(2, pcall(function() return DebugLog.isEnabled(DebugType.CraftLogic) end))))
