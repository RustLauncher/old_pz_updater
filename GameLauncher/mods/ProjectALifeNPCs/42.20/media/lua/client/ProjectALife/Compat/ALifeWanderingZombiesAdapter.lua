require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.WanderingZombiesAdapter ~= nil then return ProjectALife.WanderingZombiesAdapter end
local Adapter = { installed = false }
ProjectALife.WanderingZombiesAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.detect()
    return type(_G) == "table" and type(_G.wzIsValidZombie) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    Adapter.installed = Registry.wrap("WanderingZombies", _G, "wzIsValidZombie", function(original, zombie, ...)
        if Adapter.isOurs(zombie) then return false end
        return original(zombie, ...)
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("WanderingZombies")
    Adapter.installed = false
end

Registry.register({ id = "WanderingZombies", mods = { "WanderingZombies" }, phase = "client",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
