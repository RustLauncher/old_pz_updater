require "ProjectALife/Compat/ALifeCompatRegistry"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}
if ProjectALife.JeemResidentsAdapter ~= nil then return ProjectALife.JeemResidentsAdapter end

local Registry = ProjectALife.CompatRegistry
local Interop = ProjectALife.Interop
local Adapter = { installed = false }
ProjectALife.JeemResidentsAdapter = Adapter

function Adapter.test(body)
    local uid = Interop.uidOf(body)
    if uid == nil then return false end
    local registry = ProjectALife.ActorRegistry
    if type(registry) ~= "table" then return false end
    local getter = registry.peek
    if type(getter) ~= "function" then getter = registry.read end
    if type(getter) ~= "function" then return false end
    local actor = getter(uid)
    return type(actor) == "table" and type(actor.memory) == "table"
        and type(actor.memory.jimmyResident) == "table" and actor.lifecycle ~= "dead"
end

function Adapter.resident(body)
    return Registry.call("JeemResidents", Adapter.test, body) == true
end

function Adapter.detect()
    return type(Interop.registerResidentTest) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    Adapter.installed = Interop.registerResidentTest(Adapter.resident) == true
    return Adapter.installed
end

function Adapter.undo()
    Adapter.installed = false
end

Registry.register({ id = "JeemResidents", mods = { "ProjectALifeJimmy" }, phase = "gameStart",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
