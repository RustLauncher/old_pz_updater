require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.GaelGunStoreAdapter ~= nil then return ProjectALife.GaelGunStoreAdapter end
local Adapter = { installed = false, metrics = { stamped = 0 } }
ProjectALife.GaelGunStoreAdapter = Adapter

Adapter.markers = { "SimWorldLoadoutOwner", "GGS_WeaponAutoUpgraded", "GGS_RandomConditionDone" }

function Adapter.stamp(item)
    if item == nil or type(instanceof) ~= "function" or not instanceof(item, "HandWeapon") then return false end
    local data = Registry.ask(item, "getModData")
    if type(data) ~= "table" then return false end
    for _, key in ipairs(Adapter.markers) do data[key] = true end
    Adapter.metrics.stamped = Adapter.metrics.stamped + 1
    return true
end

function Adapter.stampShell(shell)
    Adapter.stamp(Registry.ask(shell, "getPrimaryHandItem"))
    Adapter.stamp(Registry.ask(shell, "getSecondaryHandItem"))
    Registry.each(Registry.ask(shell, "getAttachedItems"), function(entry)
        Adapter.stamp(Registry.ask(entry, "getItem"))
    end)
    Registry.each(Registry.ask(Registry.ask(shell, "getInventory"), "getItems"), Adapter.stamp)
end

function Adapter.detect()
    local hydrator = ProjectALife.ProfileHydrator
    return type(GGSWeaponUpgrades) == "table" and type(hydrator) == "table" and type(hydrator.hydrate) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    Adapter.installed = Registry.wrap("GaelGunStore", ProjectALife.ProfileHydrator, "hydrate", function(original, shell, actor, ...)
        local ok, reason = original(shell, actor, ...)
        if ok == true and shell ~= nil then Adapter.stampShell(shell) end
        return ok, reason
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("GaelGunStore")
    Adapter.installed = false
end

Registry.register({ id = "GaelGunStore", mods = { "GaelGunStore_B42" }, phase = "server",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
