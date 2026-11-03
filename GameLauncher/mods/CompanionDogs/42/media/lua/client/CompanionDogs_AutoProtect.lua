CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local active = {}
local lastSendMin = {}

local function hasBlockingAction(player)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    if not q or not q.queue then return false end
    for i = 1, #q.queue do
        local a = q.queue[i]
        local t = a and a.Type
        if t then
            if CD.AUTO_PROTECT_ACTIONS[t] then return true end
            if string.find(t, "Fish", 1, true) then return true end
        end
    end
    return false
end

local function isOwnerVulnerable(player)
    if player:isAsleep() or player:isReading() or player:isSitOnGround() then return true end
    return hasBlockingAction(player)
end

local function onPlayerUpdate(player)
    if not player then return end
    if not CD.autoProtectEnabled() then return end
    local pn = player:getPlayerNum()

    if isOwnerVulnerable(player) then
        local dog = CD.getCompanionAnimal(player)
        if dog and CD.getAutoProtect(dog) then
            local now = math.floor(CD.worldMinutes())
            if lastSendMin[pn] == nil or now ~= lastSendMin[pn] then
                CD.request("setprotectactive", dog, {}, player)
                lastSendMin[pn] = now
            end
            active[pn] = true
            return
        end
    end

    if active[pn] then
        local dog = CD.getCompanionAnimal(player)
        if dog then
            CD.request("setprotectactive", dog, { off = true }, player)
        end
        active[pn] = nil
        lastSendMin[pn] = nil
    end
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onPlayerUpdate, "cli.autoprotect")
end
