require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.CyesPushDoorsAdapter ~= nil then return ProjectALife.CyesPushDoorsAdapter end
local Adapter = { installed = false }
ProjectALife.CyesPushDoorsAdapter = Adapter

function Adapter.isOurs(character)
    if (type(character) ~= "table" and type(character) ~= "userdata")
            or type(character.getModData) ~= "function" then return false end
    if Registry.ask(character, "hasModData") ~= false then
        local data = Registry.ask(character, "getModData")
        if type(data) ~= "table" then return false end
        if data.ProjectALifeOwned == true or data.ProjectALifeActor == true then return true end
    end
    local uid = Registry.ask(character, "GetVariable", "ALifeUID")
    return uid ~= nil and uid ~= ""
end

function Adapter.detect()
    return type(CyesPushDoors) == "table" and type(CyesPushDoors.getImpactTargetType) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    Adapter.installed = Registry.wrap("CyesPushDoors", CyesPushDoors, "getImpactTargetType", function(original, target, ...)
        if Adapter.isOurs(target) then return nil, "alife-npc" end
        return original(target, ...)
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("CyesPushDoors")
    Adapter.installed = false
end

Registry.register({ id = "CyesPushDoors", mods = { "CyesPushDoors" }, phase = "gameStart",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
