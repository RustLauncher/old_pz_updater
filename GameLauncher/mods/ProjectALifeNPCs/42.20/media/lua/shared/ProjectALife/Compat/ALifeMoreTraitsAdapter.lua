require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.MoreTraitsAdapter ~= nil then return ProjectALife.MoreTraitsAdapter end
local Adapter = { installed = false }
ProjectALife.MoreTraitsAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.detect()
    return type(MT) == "table" and type(MT.KillZombie) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    Adapter.installed = Registry.wrap("MoreTraits", MT, "KillZombie", function(original, target, player, damage, ...)
        if Adapter.isOurs(target) then return end
        return original(target, player, damage, ...)
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("MoreTraits")
    Adapter.installed = false
end

Registry.register({ id = "MoreTraits", mods = { "moreTraitsDefinitive" }, phase = "gameStart",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
