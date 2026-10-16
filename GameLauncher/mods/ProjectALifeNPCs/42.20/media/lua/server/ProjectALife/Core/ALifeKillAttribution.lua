require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}

local Reputation = ProjectALife.Reputation
local Attribution = { adapters = {}, recent = {} }
ProjectALife.KillAttribution = Attribution

local function modData(character)
    local data
    pcall(function() data = character:getModData() end)
    return type(data) == "table" and data or nil
end

function Attribution.playerKey(character)
    return Reputation.playerKey(character)
end

local function position(character)
    local x, y
    pcall(function() x, y = character:getX(), character:getY() end)
    return x, y
end

function Attribution.classify(attacker)
    if attacker == nil then return nil end
    local data = modData(attacker)
    local x, y = position(attacker)
    if data ~= nil and (data.ProjectALifeOwned == true
            or data.ProjectALifeActor == true) then
        return "actor", data.ProjectALifeUID, x, y, attacker
    end
    local key = Attribution.playerKey(attacker)
    if key ~= nil then return "player", key, x, y, attacker end
    return "zombie", nil, x, y, attacker
end

Attribution.recentMs = 1000

function Attribution.clock()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Attribution.remember(shell, kind, key, x, y, killer)
    local recent = Attribution.recent
    recent.shell, recent.kind, recent.key, recent.x, recent.y, recent.killer = shell, kind, key, x, y, killer
    recent.atMs = Attribution.clock()
    return kind, key, x, y, killer
end

function Attribution.resolve(shell)
    if type(Attribution.adapters.resolve) == "function" then
        return Attribution.adapters.resolve(shell)
    end
    local health = ProjectALife.Health
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.reportedKiller) == "function" then
        local ok, kind, key, x, y, killer = pcall(executor.reportedKiller, shell)
        if ok and kind ~= nil then
            if health ~= nil and type(health.lastAttacker) == "table" then
                health.lastAttacker[shell] = nil
            end
            return Attribution.remember(shell, kind, key, x, y, killer)
        end
    end
    local attacker
    pcall(function() attacker = shell:getAttackedBy() end)
    if attacker == nil and health ~= nil and type(health.lastAttacker) == "table" then
        attacker = health.lastAttacker[shell]
    end
    if health ~= nil and type(health.lastAttacker) == "table" then
        health.lastAttacker[shell] = nil
    end
    return Attribution.remember(shell, Attribution.classify(attacker))
end

function Attribution.peek(shell)
    if shell == nil then return nil end
    local recent = Attribution.recent
    local age = recent.atMs ~= nil and Attribution.clock() - recent.atMs or nil
    if recent.shell == shell and age ~= nil and age >= 0 and age < Attribution.recentMs then
        return recent.kind, recent.key, recent.x, recent.y, recent.killer
    end
    local attacker
    if shell.getAttackedBy ~= nil then
        local ok, value = pcall(shell.getAttackedBy, shell)
        if ok then attacker = value end
    end
    local health = ProjectALife.Health
    if attacker == nil and health ~= nil and type(health.lastAttacker) == "table" then
        attacker = health.lastAttacker[shell]
    end
    return Attribution.classify(attacker)
end

function Attribution.configure(adapters)
    Attribution.adapters = adapters or {}
end

return Attribution
