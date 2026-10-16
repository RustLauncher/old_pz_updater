require "ProjectALife/World/ALifeEncounterLog"

ProjectALife = ProjectALife or {}
if ProjectALife.SquadMapEncounters then return ProjectALife.SquadMapEncounters end

local Marks = {
    nearTiles = 25,
    metrics = { added = 0, covered = 0, passes = 0 },
}
ProjectALife.SquadMapEncounters = Marks

local function numeric(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function Marks.covered(rows, entry, known)
    if entry.groupId ~= nil and known[tostring(entry.groupId)] == true then return true end
    if entry.groupId ~= nil then return false end
    local limit = Marks.nearTiles * Marks.nearTiles
    for _, row in ipairs(rows) do
        if row.outpost ~= true and row.offline ~= true and row.place ~= true then
            local dx, dy = (numeric(row.x) or math.huge) - entry.x, (numeric(row.y) or math.huge) - entry.y
            if dx * dx + dy * dy <= limit then return true end
        end
    end
    return false
end

function Marks.append(rows, cap)
    Marks.metrics.passes = Marks.metrics.passes + 1
    if type(rows) ~= "table" then return 0 end
    cap = numeric(cap) or 128
    local log = ProjectALife.EncounterLog
    if log == nil or type(log.live) ~= "function" then return 0 end
    local ok, live = pcall(log.live)
    if not ok or type(live) ~= "table" then return 0 end
    local known = {}
    for _, row in ipairs(rows) do
        if row.groupId ~= nil then known[tostring(row.groupId)] = true end
    end
    local added = 0
    for _, mark in ipairs(live) do
        if #rows >= cap then break end
        local x, y = numeric(mark.x), numeric(mark.y)
        if type(mark) == "table" and x ~= nil and y ~= nil then
            local entry = { x = x, y = y, groupId = mark.groupId }
            if Marks.covered(rows, entry, known) then
                Marks.metrics.covered = Marks.metrics.covered + 1
            else
                local members = math.max(0, math.floor(numeric(mark.count) or 0))
                rows[#rows + 1] = {
                    x = math.floor(x),
                    y = math.floor(y),
                    members = members,
                    active = false,
                    encounter = true,
                    persistent = false,
                    groupId = mark.groupId ~= nil and tostring(mark.groupId) or nil,
                    label = tostring(mark.label or mark.id or "encounter"),
                    task = "encounter: " .. tostring(mark.id or "?"),
                    activity = "marked by the encounter arrows",
                }
                added = added + 1
            end
        end
    end
    Marks.metrics.added = Marks.metrics.added + added
    return added
end

return Marks
