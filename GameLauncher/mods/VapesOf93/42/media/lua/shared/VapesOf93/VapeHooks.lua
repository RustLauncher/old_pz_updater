require "VapesOf93/VapeShared"
pcall(require, "TimedActions/ISEatFoodAction")

local function wrap(class, name, applyOnClient)
    local orig = class and class[name]
    if type(orig) ~= "function" then return false end
    class[name] = function(self, ...)
        local t
        if self.item then pcall(function() t = self.item:getFullType() end) end
        local vape = t and VapesOf93.KIND[t]
        local before = vape and VapesOf93.read(self.character, "STRESS") or nil
        local r = orig(self, ...)
        if vape and (applyOnClient or not isClient()) then
            pcall(VapesOf93.afterHit, t, self.character, before)
        end
        return r
    end
    return true
end

local a = wrap(ISEatFoodAction, "complete", true)
local b = wrap(ISEatFoodAction, "perform", false)
print("[VapesOf93] smoke hooks: complete=" .. tostring(a) .. " perform=" .. tostring(b))
