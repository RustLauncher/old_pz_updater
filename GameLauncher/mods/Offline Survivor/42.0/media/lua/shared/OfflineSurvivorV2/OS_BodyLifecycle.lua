require "OfflineSurvivorV2/OS_Constants"
local OS = OfflineSurvivorV2
local H = {}
OS.BodyLifecycle = H

function H.isProxy(object)
    if not object then return false end
    local data = object:getModData()
    return data and data[OS.OFFLINE_MARKER] == true and data.renderer == OS.RENDERER
end

function H.freezeAge(object)
    if not H.isProxy(object) or not instanceof(object, "IsoDeadBody") then return false end
    -- Death time is engine world-hours, not getTimestamp() real seconds.
    -- Only the sealed visual proxy is kept fresh. Real death bodies are unmarked.
    object:setDeathTime(getGameTime():getWorldAgeHours())
    object:setReanimateTime(-1)
    return true
end

function H.isAdmin(player)
    return player ~= nil and tostring(player:getAccessLevel() or ""):lower() == "admin"
end

function H.ownerConnected(record)
    if not record or record.testBody then return false end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        if tostring(OS.getSteamId(players:get(i))) == tostring(record.steamId) then return true end
    end
    return false
end

function H.finite(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

function H.cleanupMatches(data, cleanup)
    if not data or data[OS.OFFLINE_MARKER] ~= true then return false end
    if tostring(data.steamId or "") ~= tostring(cleanup.targetSteamId or "") then return false end
    if cleanup.bodyEpoch ~= nil then
        if tostring(data.bodyEpoch or 0) ~= tostring(cleanup.bodyEpoch) then return false end
        if cleanup.bodyRevision ~= nil then
            return tostring(data.bodyRevision or 0) == tostring(cleanup.bodyRevision)
        end
        return true
    end
    -- Legacy packet: no broad SteamID match. An exact native object ID can
    -- still be checked by the caller, without deleting a later logout body.
    return false
end

return H
