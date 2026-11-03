require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.AdvancedTrajectoryAdapter ~= nil then return ProjectALife.AdvancedTrajectoryAdapter end
local Adapter = { installed = false, modId = "Advanced_trajectorys_Realistic_Overhaul" }
ProjectALife.AdvancedTrajectoryAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.isLocal(player)
    return Registry.ask(player, "isLocalPlayer") == true
end

function Adapter.module()
    local ok, module = pcall(require, "Advanced_trajectory_core")
    if not ok then error(module, 0) end
    if type(module) == "table" then return module end
    return nil
end

function Adapter.detect()
    Adapter.trajectory = Adapter.module()
    return Adapter.trajectory ~= nil and type(Adapter.trajectory.damageZombie) == "function"
        and type(Adapter.trajectory.killZombie) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not ProjectALife.ModCompat.isActive(Adapter.modId) then return false end
    local trajectory = Adapter.trajectory or Adapter.module()
    if trajectory == nil then return false end
    Registry.wrap("AdvancedTrajectory", trajectory, "damageZombie", function(original, zombie, amount, isCrit, limbShot, player, ...)
        if Adapter.isOurs(zombie) and not Adapter.isLocal(player) then return end
        return original(zombie, amount, isCrit, limbShot, player, ...)
    end)
    Registry.wrap("AdvancedTrajectory", trajectory, "killZombie", function(original, zombie, player, amount, ...)
        if Adapter.isOurs(zombie) then return end
        return original(zombie, player, amount, ...)
    end)
    Adapter.installed = true
    return true
end

function Adapter.undo()
    Registry.restore("AdvancedTrajectory")
    Adapter.installed = false
end

Registry.register({ id = "AdvancedTrajectory", mods = { "Advanced_trajectorys_Realistic_Overhaul" }, phase = "client",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
