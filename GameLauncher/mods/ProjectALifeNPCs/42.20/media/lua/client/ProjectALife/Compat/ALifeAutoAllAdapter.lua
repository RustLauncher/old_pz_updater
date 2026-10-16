require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.AutoAllAdapter ~= nil then return ProjectALife.AutoAllAdapter end
local Adapter = { installed = false, nearRadius = 20 }
ProjectALife.AutoAllAdapter = Adapter

function Adapter.uidOf(character)
    return Registry.uidOf(character)
end

function Adapter.harmless(character, player)
    local uid = Adapter.uidOf(character)
    if uid == nil or uid == true then return false end
    local registry, relations = ProjectALife.ActorRegistry, ProjectALife.Relations
    if registry == nil or type(registry.read) ~= "function" or relations == nil
            or type(relations.hostileToPlayer) ~= "function" then return false end
    if Registry.ask(character, "getTarget") == player then return false end
    local ok, hostile = pcall(function()
        local actor = registry.read(tostring(uid))
        if actor == nil then return true end
        return relations.hostileToPlayer(actor, player) == true
    end)
    return ok and hostile == false
end

function Adapter.bystandersOnly(player)
    if player == nil or type(getCell) ~= "function" then return false end
    local registry, relations = ProjectALife.ActorRegistry, ProjectALife.Relations
    if registry == nil or type(registry.read) ~= "function" or relations == nil
            or type(relations.hostileToPlayer) ~= "function" then return false end
    local stats = Registry.ask(player, "getStats")
    local visible = (tonumber(Registry.ask(stats, "getNumVisibleZombies")) or 0) > 0
        or (tonumber(Registry.ask(stats, "getNumChasingZombies")) or 0) > 0
        or (tonumber(Registry.ask(stats, "getNumVeryCloseZombies")) or 0) > 0
    if not visible then return false end
    local ok, cell = pcall(getCell)
    if not ok then return false end
    local px, py = Registry.ask(player, "getX"), Registry.ask(player, "getY")
    if type(px) ~= "number" or type(py) ~= "number" then return false end
    local reach, seen, threat = Adapter.nearRadius * Adapter.nearRadius, false, false
    Registry.each(Registry.ask(cell, "getZombieList"), function(character)
        if type(character) ~= "table" and type(character) ~= "userdata" then return false end
        if type(character.isDead) ~= "function" or type(character.getX) ~= "function"
                or type(character.getY) ~= "function" then return false end
        local dead, x, y = character:isDead(), character:getX(), character:getY()
        if dead ~= false or type(x) ~= "number" or type(y) ~= "number" then return false end
        local dx, dy = x - px, y - py
        if dx * dx + dy * dy > reach then return false end
        seen = true
        if not Adapter.harmless(character, player) then threat = true end
        return threat
    end, true)
    return seen and not threat
end

function Adapter.detect()
    return type(AutoAll) == "table" and type(AutoAll.checkSafety) == "function" and type(AutoAll.opt) == "function"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.detect() then return false end
    local auto = AutoAll
    Adapter.installed = Registry.wrap("AutoAll", auto, "checkSafety", function(original, task, ...)
        local player = type(task) == "table" and task.player or nil
        if not (auto.opt("stopZombie") and auto.opt("ignoreNpcs") and Adapter.bystandersOnly(player)) then
            return original(task, ...)
        end
        local opt = auto.opt
        auto.opt = function(key, ...)
            if key == "stopZombie" then return false end
            return opt(key, ...)
        end
        local result = Registry.pack(pcall(original, task, ...))
        auto.opt = opt
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end)
    return Adapter.installed
end

function Adapter.undo()
    Registry.restore("AutoAll")
    Adapter.installed = false
end

Registry.register({ id = "AutoAll", mods = { "AutoAll" }, phase = "client",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
