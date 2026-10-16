ProjectALife = ProjectALife or {}

local Lock = {
    TAG = "ProjectALife.Cleanup.v1",
    SCHEMA = 1,
    adapters = {},
    state = nil,
    cachedMode = nil,
    metrics = { total = 0, refused = {}, said = {} },
}
ProjectALife.CleanupLock = Lock

Lock.creators = {
    director = true, population = true, offline_director = true, outposts = true, base_heat = true,
    raid_director = true, meta_director = true, populate = true, populate_scan = true,
    town_welcome = true, encounter_director = true, safehouse = true, activities = true,
    admin_queue = true,
}

function Lock.skips(name)
    if Lock.creators[name] ~= true or not Lock.locked() then return false end
    local metrics = Lock.metrics
    metrics.skipped = (metrics.skipped or 0) + 1
    metrics.skippedBy = metrics.skippedBy or {}
    metrics.skippedBy[name] = (metrics.skippedBy[name] or 0) + 1
    return true
end

function Lock.reset()
    Lock.state = nil
    Lock.cachedMode = nil
    Lock.metrics = { total = 0, refused = {}, said = {} }
end

function Lock.configure(adapters)
    Lock.adapters = type(adapters) == "table" and adapters or {}
    Lock.state = nil
    Lock.cachedMode = nil
end

function Lock.refresh()
    Lock.state = nil
    Lock.cachedMode = nil
    return Lock.mode()
end

local function tagExists()
    local adapters = Lock.adapters
    if type(adapters.exists) == "function" then return adapters.exists(Lock.TAG) == true end
    if type(ModData) ~= "table" or type(ModData.exists) ~= "function" then return false end
    local ok, found = pcall(ModData.exists, Lock.TAG)
    return ok and found == true
end

function Lock.peek()
    if Lock.state ~= nil then return Lock.state end
    if not tagExists() then return nil end
    local adapters = Lock.adapters
    local ok, value
    if type(adapters.get) == "function" then
        ok, value = pcall(adapters.get, Lock.TAG)
    elseif type(ModData) == "table" and type(ModData.get) == "function" then
        ok, value = pcall(ModData.get, Lock.TAG)
    end
    if ok and type(value) == "table" then Lock.state = value end
    return Lock.state
end

function Lock.create()
    if Lock.state ~= nil then return Lock.state end
    local adapters = Lock.adapters
    local ok, value
    if type(adapters.getOrCreate) == "function" then
        ok, value = pcall(adapters.getOrCreate, Lock.TAG)
    elseif type(ModData) == "table" and type(ModData.getOrCreate) == "function" then
        ok, value = pcall(ModData.getOrCreate, Lock.TAG)
    end
    if not ok or type(value) ~= "table" then return nil, "mod_data_unavailable" end
    if value.schema == nil then value.schema = Lock.SCHEMA end
    Lock.state = value
    return value
end

function Lock.mode()
    if Lock.cachedMode ~= nil then return Lock.cachedMode end
    local state = Lock.peek()
    local mode = "idle"
    if state ~= nil and type(state.mode) == "string" then mode = state.mode end
    Lock.cachedMode = mode
    return mode
end

function Lock.respawnAfter()
    local adapters = Lock.adapters
    if type(adapters.respawnAfter) == "function" then return adapters.respawnAfter() == true end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) == "table" and vars.Cleanup_RespawnAfter == true
end

function Lock.locked()
    local mode = Lock.mode()
    if mode == "running" then return true end
    if mode == "done" then return not Lock.respawnAfter() end
    return false
end

function Lock.set(mode, fields)
    local state, reason = Lock.create()
    if state == nil then return false, reason end
    state.mode = mode
    if type(fields) == "table" then
        for key, value in pairs(fields) do state[key] = value end
    end
    Lock.cachedMode = mode
    return true
end

function Lock.refuse(kind)
    if not Lock.locked() then return false end
    kind = tostring(kind or "unknown")
    local metrics = Lock.metrics
    metrics.total = metrics.total + 1
    metrics.refused[kind] = (metrics.refused[kind] or 0) + 1
    if not metrics.said[kind] then
        metrics.said[kind] = true
        local log = Lock.adapters.log
        if type(log) == "function" then pcall(log, "[ALIFE-CLEANUP] spawn refused kind=" .. kind .. " mode=" .. Lock.mode())
        elseif type(print) == "function" then
            pcall(print, "[ALIFE-CLEANUP] spawn refused kind=" .. kind .. " mode=" .. Lock.mode())
        end
    end
    return true
end

function Lock.refusals()
    local rows = {}
    for kind, count in pairs(Lock.metrics.refused) do rows[#rows + 1] = { kind = kind, count = count } end
    table.sort(rows, function(a, b) return a.kind < b.kind end)
    return rows
end

return Lock
