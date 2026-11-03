ProjectALife = ProjectALife or {}

local Log = {
    entries = {},
    settings = {

        ttlMs = 45 * 60 * 1000,

        maximum = 24,

        spawnGraceMs = 15000,
    },
}
ProjectALife.EncounterLog = Log

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Log.record(definition, point, count, reason, groupId)
    if type(point) ~= "table" then return false end
    local now = nowMs()
    local entry = {
        id = type(definition) == "table" and tostring(definition.id or "?") or "?",
        label = type(definition) == "table"
            and tostring(definition.label or definition.id or "?") or "?",
        stance = type(definition) == "table" and definition.stance or nil,
        placement = type(definition) == "table" and definition.placement or nil,
        x = tonumber(point.x) or 0,
        y = tonumber(point.y) or 0,
        z = tonumber(point.z) or 0,
        count = tonumber(count) or 0,
        atMs = now,
        reason = reason ~= nil and tostring(reason) or nil,
        groupId = groupId ~= nil and tostring(groupId) or nil,
    }
    table.insert(Log.entries, 1, entry)
    while #Log.entries > Log.settings.maximum do
        table.remove(Log.entries)
    end
    return true
end

function Log.live(suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local result = {}
    local registry = ProjectALife.ActorRegistry
    local aliveGroups = {}
    if registry ~= nil and type(registry.list) == "function" then
        pcall(function()
            for _, actor in ipairs(registry.list()) do
                local groupId = actor.memory and actor.memory.groupId
                if groupId ~= nil and actor.lifecycle ~= "dead" then
                    aliveGroups[tostring(groupId)] = true
                end
            end
        end)
    end
    local kept = {}
    for _, entry in ipairs(Log.entries) do
        local age = now - entry.atMs
        local groupLive = entry.groupId == nil or age <= Log.settings.spawnGraceMs
            or aliveGroups[entry.groupId] == true
        if age <= Log.settings.ttlMs and groupLive then
            kept[#kept + 1] = entry
            result[#result + 1] = {
                id = entry.id, label = entry.label, stance = entry.stance,
                placement = entry.placement, count = entry.count,
                x = entry.x, y = entry.y, z = entry.z,
                groupId = entry.groupId,
                ageMs = age,
            }
        end
    end
    Log.entries = kept
    return result
end

function Log.reset()
    Log.entries = {}
end

return Log
