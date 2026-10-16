require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Calm = {
    scanMs = 150,
    radius = 15,
    ceiling = 1000,
    stabCeiling = 590,
    stingName = "ZombieSurprisedPlayer",
    state = {},
    metrics = { scans = 0, held = 0, stabs = 0, errors = 0 },
}
ProjectALife.CalmNearNpcs = Calm

function Calm.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Calm.enabled()
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.calmOn) ~= "function" then return true end
    return prefs.calmOn() == true
end

function Calm.isNpc(zombie)
    if type(zombie.hasModData) == "function" and zombie:hasModData() == true
            and type(zombie.getModData) == "function" then
        local data = zombie:getModData()
        if type(data) == "table" and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true) then
            return true
        end
    end
    if type(zombie.getVariableString) == "function" then
        local uid = zombie:getVariableString("ALifeUID")
        if uid ~= nil and uid ~= "" then return true end
    end
    return false
end

function Calm.npcInReach(player)
    local fence = ProjectALife.AIFence
    local owned = type(fence) == "table" and fence.owned or nil
    if type(owned) ~= "table" then return true end
    local px, py = player:getX(), player:getY()
    local reach = Calm.radius * Calm.radius
    for shell in pairs(owned) do
        if type(shell.getX) == "function" and type(shell.getY) == "function" then
            local dx, dy = shell:getX() - px, shell:getY() - py
            if dx * dx + dy * dy <= reach then return true end
        else
            return true
        end
    end
    return false
end

function Calm.scan(player)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or type(cell.getZombieList) ~= "function" then return false end
    local list = cell:getZombieList()
    if list == nil then return false end
    local px, py = player:getX(), player:getY()
    local reach = Calm.radius * Calm.radius
    local npcNear = false
    for index = 0, list:size() - 1 do
        local zombie = list:get(index)
        if zombie ~= nil then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy <= reach then
                if Calm.isNpc(zombie) then
                    npcNear = true
                elseif not zombie:isDead() then
                    return false
                end
            end
        end
    end
    return npcNear
end

function Calm.hold(player)
    local body = player:getBodyDamage()
    if body ~= nil and type(body.setOldNumZombiesVisible) == "function" then
        body:setOldNumZombiesVisible(Calm.ceiling)
        Calm.metrics.held = Calm.metrics.held + 1
    end
    if type(player.getTimeSinceLastStab) == "function" and type(player.setTimeSinceLastStab) == "function"
            and player:getTimeSinceLastStab() > Calm.stabCeiling then
        player:setTimeSinceLastStab(Calm.stabCeiling)
        Calm.metrics.stabs = Calm.metrics.stabs + 1
    end
end

function Calm.hush(player)
    if type(player.getEmitter) ~= "function" then return end
    local emitter = player:getEmitter()
    if emitter ~= nil and type(emitter.stopSoundByName) == "function" then
        emitter:stopSoundByName(Calm.stingName)
    end
end

function Calm.update(player)
    local number = type(player.getPlayerNum) == "function" and player:getPlayerNum() or 0
    local state = Calm.state[number]
    if state == nil then
        state = { active = false, nextScanMs = 0 }
        Calm.state[number] = state
    end
    local now = Calm.nowMs()
    if now >= state.nextScanMs or now < state.nextScanMs - Calm.scanMs * 4 then
        state.nextScanMs = now + Calm.scanMs
        Calm.metrics.scans = Calm.metrics.scans + 1
        state.active = Calm.npcInReach(player) and Calm.scan(player) == true
        if state.active then Calm.hush(player) end
    end
    if state.active then Calm.hold(player) end
end

function Calm.onPlayerUpdate(player)
    if player == nil or type(player.isLocalPlayer) ~= "function" or player:isLocalPlayer() ~= true then return end
    if not Calm.enabled() then return end
    if type(player.isAlive) == "function" and player:isAlive() ~= true then return end
    local ok = pcall(Calm.update, player)
    if not ok then Calm.metrics.errors = Calm.metrics.errors + 1 end
end

function Calm.reset()
    Calm.state = {}
end

if type(Events) == "table" then
    if Events.OnPlayerUpdate ~= nil then Events.OnPlayerUpdate.Add(Calm.onPlayerUpdate) end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(Calm.reset) end
end

return Calm
