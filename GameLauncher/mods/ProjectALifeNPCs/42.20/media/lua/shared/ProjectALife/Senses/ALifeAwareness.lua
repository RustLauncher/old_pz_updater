require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Awareness = {
    levels = {
        asleep = 0.12,      
        busy = 0.3,         
        houseNight = 0.35,  
        resting = 0.45,     
        watch = 1.0,        
    },

    legacySightTiles = 30,
}
ProjectALife.Awareness = Awareness

function Awareness.isSentry(memory)
    if type(memory) ~= "table" then return false end
    if memory.stanceSentry ~= nil then return memory.stanceSentry == true end
    return tonumber(memory.groupIndex) == 1
end

function Awareness.forRole(kind, memory)
    local levels = Awareness.levels
    local share = levels[kind] or levels.watch
    if share < levels.watch and Awareness.isSentry(memory) then return levels.watch end
    return share
end

function Awareness.share(value, sightTiles)
    local number = tonumber(value)
    if number == nil then return nil end
    if number > 1 then
        number = number / math.max(1, tonumber(sightTiles) or Awareness.legacySightTiles)
    end
    return math.max(0, math.min(1, number))
end

function Awareness.shareFor(memory, raw, sightTiles)
    local share = Awareness.share(raw, sightTiles)
    local alert = type(memory) == "table" and memory.hearingAlert or nil
    if not ProjectALife.FeatureGate.flag("Hearing_Enabled", true) then return share end
    if alert ~= nil and type(getTimestampMs) == "function" and getTimestampMs() < alert.untilMs then
        if alert.level == "red" then share = Awareness.levels.watch
        elseif alert.level == "yellow" then share = math.max(share or 0, ProjectALife.FeatureGate.number("Hearing_AlertPercent", 70, 0, 100) / 100) end
    end
    return share
end

function Awareness.sentryOf(members)
    local best
    for _, member in ipairs(type(members) == "table" and members or {}) do
        if member.dead ~= true then
            local index = tonumber(member.groupIndex) or math.huge
            if best == nil or index < best.index
                    or (index == best.index and tostring(member.uid) < tostring(best.uid)) then
                best = { uid = member.uid, index = index }
            end
        end
    end
    return best and best.uid or nil
end

return Awareness
