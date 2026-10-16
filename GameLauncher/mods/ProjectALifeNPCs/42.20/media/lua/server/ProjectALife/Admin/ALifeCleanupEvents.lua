require "ProjectALife/Admin/ALifeCleanup"
require "ProjectALife/Admin/ALifeCleanupWorld"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup
local World = Cleanup.World

local Events = { id = "events", scopes = { "bases" }, kinds = { "wallMarks", "traces", "markDebt", "traceDebt" } }
Cleanup.Events = Events

function Events.store()
    local persistence = ProjectALife.Persistence
    local tag = persistence ~= nil and persistence.TAG or "ProjectALife.World.v1"
    if type(ModData) ~= "table" or type(ModData.exists) ~= "function" or type(ModData.get) ~= "function" then return nil end
    local ok, found = pcall(ModData.exists, tag)
    if not ok or found ~= true then return nil end
    local fine, data = pcall(ModData.get, tag)
    if not fine or type(data) ~= "table" or type(data.stores) ~= "table" then return nil end
    local bucket = data.stores.baseHeat
    if type(bucket) == "table" then return bucket end
    return nil
end

function Events.collect()
    local rows = {}
    local store = Events.store()
    if store == nil then return rows end
    local function take(kind, list)
        if type(list) ~= "table" then return end
        for _, entry in ipairs(list) do
            if type(entry) == "table" then rows[#rows + 1] = { kind = kind, list = list, entry = entry } end
        end
    end
    local keys = {}
    for key in pairs(type(store.houses) == "table" and store.houses or {}) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local house = store.houses[key]
        if type(house) == "table" then
            take("wallMarks", house.wallMarks)
            take("traces", house.traces)
        end
    end
    take("markDebt", store.markDebt)
    take("traceDebt", store.traceDebt)
    return rows
end

function Events.drop(row)
    for index = #row.list, 1, -1 do
        if row.list[index] == row.entry then
            table.remove(row.list, index)
            return true
        end
    end
    return false
end

function Events.begin(job)
    Cleanup.volatile.events = Events.collect()
    job.cursor.event = 1
end

function Events.handle(job, row)
    local entry = row.entry
    local x, y = tonumber(entry.x), tonumber(entry.y)
    if x == nil or y == nil then
        if job.run then Events.drop(row) end
        return
    end
    if World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
        if entry.cs ~= "safehouse" then
            Cleanup.count(job, "events.protected")
            if job.run then
                entry.cs = "safehouse"
                Cleanup.skip(job, "events", { x = x, y = y, z = entry.z or 0, what = row.kind, why = "safehouse" })
            end
        end
        return
    end
    if not World.loaded(x, y) then
        Cleanup.watch(job, x, y)
        if not job.run then Cleanup.count(job, "events.unloaded") end
        return
    end
    if not job.run then
        Cleanup.count(job, "events.found")
        return
    end
    local result
    if row.kind == "wallMarks" or row.kind == "markDebt" then
        local marks = ProjectALife.SafehouseMarks
        if marks ~= nil and type(marks.remove) == "function" then result = marks.remove(entry) end
    else
        local door = ProjectALife.SafehouseDoor
        if door ~= nil and type(door.removeTrace) == "function" then result = door.removeTrace(entry) end
    end
    if result == nil then
        entry.cf = (tonumber(entry.cf) or 0) + 1
        Cleanup.fail(job, "event_" .. row.kind, "square_unavailable")
        if entry.cf >= 3 and entry.cs ~= "unreadable" then
            entry.cs = "unreadable"
            Cleanup.skip(job, "events", { x = x, y = y, z = entry.z or 0, what = row.kind, why = "unreadable" })
        end
        return
    end
    Events.drop(row)
    if result == true then Cleanup.count(job, "events.removed") else Cleanup.count(job, "events.absent") end
    Cleanup.spend(job, 1)
end

function Events.step(job)
    local rows = Cleanup.volatile.events or {}
    while Cleanup.open(job) do
        local row = rows[job.cursor.event]
        if row == nil then return true end
        local ok, reason = pcall(Events.handle, job, row)
        if not ok then Cleanup.fail(job, "event", reason) end
        job.cursor.event = job.cursor.event + 1
        Cleanup.spend(job, 0.2)
    end
    return false
end

function Events.pending(job)
    if not job.run then return 0 end
    local count = 0
    for _, row in ipairs(Events.collect()) do
        if row.entry.cs == nil then count = count + 1 end
    end
    return count
end

function Events.pendingList(job, limit)
    local list = {}
    if not job.run then return list end
    for _, row in ipairs(Events.collect()) do
        if row.entry.cs == nil and #list < limit then
            list[#list + 1] = { kind = row.kind, id = row.kind, x = row.entry.x, y = row.entry.y, z = row.entry.z or 0, left = 1 }
        end
    end
    return list
end

Cleanup.add(Events)

return Events
