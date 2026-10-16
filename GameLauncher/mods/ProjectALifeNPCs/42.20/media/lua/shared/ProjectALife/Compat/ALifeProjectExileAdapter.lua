require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.ProjectExileAdapter ~= nil then return ProjectALife.ProjectExileAdapter end
local Adapter = { installed = false }
ProjectALife.ProjectExileAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.detect()
    local combat = type(ProjectExile) == "table" and ProjectExile.CombatService or nil
    local hits = type(Events) == "table" and Events.OnWeaponHitXp or nil
    return type(combat) == "table" and type(combat.onWeaponHit) == "function"
        and hits ~= nil and type(hits.Remove) == "function" and type(hits.Add) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    local combat, hits = ProjectExile.CombatService, Events.OnWeaponHitXp
    Adapter.hits, Adapter.original = hits, combat.onWeaponHit
    Registry.wrap("ProjectExile", combat, "onWeaponHit", function(original, player, weapon, target, damage, ...)
        if Adapter.isOurs(target) then return end
        return original(player, weapon, target, damage, ...)
    end)
    Adapter.wrapper = combat.onWeaponHit
    hits.Remove(Adapter.original)
    Adapter.removed = true
    hits.Add(Adapter.wrapper)
    Adapter.installed = true
    return true
end

function Adapter.undo()
    local hits = Adapter.hits
    if hits ~= nil and type(hits.Remove) == "function" then hits.Remove(Adapter.wrapper) end
    if Adapter.removed and hits ~= nil and type(hits.Add) == "function" then hits.Add(Adapter.original) end
    Registry.restore("ProjectExile")
    Adapter.installed, Adapter.removed = false, false
end

Registry.register({ id = "ProjectExile", mods = { "ProjectExile" }, phase = "gameStart",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
