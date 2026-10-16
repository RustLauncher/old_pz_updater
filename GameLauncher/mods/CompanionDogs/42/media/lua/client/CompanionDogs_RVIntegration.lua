CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local MINX = CD.RV_INTERIOR_MIN_X
local MINY = CD.RV_INTERIOR_MIN_Y

local function isInRV(player)
    return player:getX() > MINX and player:getY() > MINY
end

local wasInRV = {}
local function onRVTransition(player)
    if not player then return end
    local pn = player:getPlayerNum()
    local now = isInRV(player)
    local prev = wasInRV[pn]
    if prev == nil then
        wasInRV[pn] = now
        return
    end
    if now == prev then return end
    wasInRV[pn] = now
    if now then
        CD.request("rventer", nil, {}, player)
    else
        CD.request("rvexit", nil, {}, player)
    end
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onRVTransition, "cli.rv")
end
