require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.PixelStrikeAdapter ~= nil then return ProjectALife.PixelStrikeAdapter end
local Adapter = { installed = { note = false, known = false, stamp = false } }
ProjectALife.PixelStrikeAdapter = Adapter

function Adapter.isOurs(character)
    return Registry.isOurs(character)
end

function Adapter.maximumOf(data)
    local maximum = tonumber(type(data) == "table" and data.ProjectALifeMaximumHealth or nil)
    if maximum ~= nil and maximum > 0 then return maximum end
    return nil
end

function Adapter.detect()
    local psi = PixelStrikeIndicator
    return type(psi) == "table" and (type(psi.noteZombieHealth) == "function"
        or type(psi.knownMax) == "function" or type(psi.stampZombie) == "function")
end

function Adapter.install()
    if not Adapter.detect() then return false end
    local psi, done = PixelStrikeIndicator, Adapter.installed
    if not done.note and type(psi.noteZombieHealth) == "function" then
        done.note = Registry.wrap("PixelStrike", psi, "noteZombieHealth", function(original, zombie, data, ...)
            if not Adapter.isOurs(zombie) then return original(zombie, data, ...) end
            data = data or Registry.ask(zombie, "getModData")
            if type(data) ~= "table" then return original(zombie, data, ...) end
            local maximum = Adapter.maximumOf(data)
            if maximum == nil and data.PSIServer == true then maximum = tonumber(data.PSIFull) end
            local full, kept, hp = original(zombie, data, ...)
            if maximum == nil or full == nil then return full, kept, hp end
            data.PSIFull = maximum
            if hp ~= nil and hp > maximum then hp = maximum end
            if data.PSIPrev ~= nil and data.PSIPrev > maximum then data.PSIPrev = maximum end
            return maximum, kept, hp
        end)
    end
    for _, row in ipairs({ { "known", "knownMax" }, { "stamp", "stampZombie" } }) do
        if not done[row[1]] and type(psi[row[2]]) == "function" then
            done[row[1]] = Registry.wrap("PixelStrike", psi, row[2], function(original, zombie, ...)
                if Adapter.isOurs(zombie) then
                    local data = Registry.ask(zombie, "getModData")
                    local maximum = Adapter.maximumOf(data)
                    if maximum ~= nil then data.PSIFull = maximum; return maximum end
                end
                return original(zombie, ...)
            end)
        end
    end
    return done.note or done.known or done.stamp
end

function Adapter.undo()
    Registry.restore("PixelStrike")
    Adapter.installed = { note = false, known = false, stamp = false }
end

Registry.register({ id = "PixelStrike", mods = { "PixelStrikeIndicator" }, phase = "gameStart",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
