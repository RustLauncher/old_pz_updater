CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.HEARTBEAT_MS = 10 * 60 * 1000

---Ids and versions of the active Companion* mods joined by commas, falling back to the breed keys; cached after the first call.
---@return string
function CD.modVersionList()
    if CD._hbMods then return CD._hbMods end
    local parts = {}
    local mods = getActivatedMods()
    if mods then
        for i = 0, mods:size() - 1 do
            local id = tostring(mods:get(i))
            if string.sub(id, 1, 9) == "Companion" then
                local info = getModInfoByID(id)
                local v = info and info:getModVersion()
                parts[#parts + 1] = id .. ((v and v ~= "") and (" " .. tostring(v)) or "")
            end
        end
    end
    if #parts == 0 and CD.BREEDS then
        for key in pairs(CD.BREEDS) do parts[#parts + 1] = tostring(key) end
    end
    CD._hbMods = (#parts > 0) and table.concat(parts, ", ") or "?"
    return CD._hbMods
end

---Logs the build, the side, the dog and companion counts and the active Companion mods.
function CD.logVersionStamp()
    CD.log("running Companion Dogs " .. CD.BUILD ..
           " | " .. (CD.perfSide() or "?") ..
           " | caes=" .. #CD.dogReg.dogs .. " comp=" .. #CD.dogReg.companions ..
           " | mods: " .. CD.modVersionList())
end

CD.evAdd(Events.EveryTenMinutes, function()
    local now = getTimestampMs()
    if CD._hbLast and (now - CD._hbLast) < CD.HEARTBEAT_MS then return end
    CD._hbLast = now
    CD.logVersionStamp()
end, "versionStamp")

local function cdStampOnStart()
    CD._hbLast = getTimestampMs()
    CD.logVersionStamp()
end
CD.evAdd(Events.OnGameStart, cdStampOnStart, "versionStamp")
CD.evAdd(Events.OnServerStarted, cdStampOnStart, "versionStamp")
