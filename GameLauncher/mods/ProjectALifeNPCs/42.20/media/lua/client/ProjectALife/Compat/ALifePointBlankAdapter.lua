require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.PointBlankAdapter ~= nil then return ProjectALife.PointBlankAdapter end
local Adapter = { installed = false }
ProjectALife.PointBlankAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.detect()
    return type(HF_PointBlank) == "table" and type(HF_PointBlank.CheckIfTargetQualifiesForPointBlank) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    Adapter.installed = Registry.wrap("PointBlank", HF_PointBlank, "CheckIfTargetQualifiesForPointBlank", function(original, player, target, logging, ...)
        if Adapter.isOurs(target) then return false end
        return original(player, target, logging, ...)
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("PointBlank")
    Adapter.installed = false
end

Registry.register({ id = "PointBlank", mods = { "hf_point_blank" }, phase = "client",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
