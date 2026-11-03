require "ProjectALife/Core/ALifeCleanupLock"

ProjectALife = ProjectALife or {}

local Lock = ProjectALife.CleanupLock

local Cleanup = {
    PHRASE = "REMOVE ALIFE",
    PHRASE2 = "I UNDERSTAND",
    adapters = {},
    settings = {
        budgetMs = 4, unitBudget = 24, rowsPerCall = 96, skipCap = 300, siteCap = 150, errorCap = 12,
        logCap = 160, progressMs = 1000, passMs = 3000, guardMs = 60000, listPage = 40, watchCap = 600,
        areaRadius = 20, areaLevels = 4, squaresPerCall = 220,
    },
    volatile = {},
    scopes = { "npcs", "bases", "vehicles", "corpsesAndLoot", "markers", "worldState", "reputation",
        "unverified", "companions", "creatorStore", "safehouses" },
    defaults = { npcs = true, bases = true, vehicles = true, markers = true, worldState = true },
    order = { "npcs", "bodies", "sites", "scenes", "events", "vehicles", "area", "markers", "playerData", "reputation",
        "creatorStore", "worldState" },
    collectors = {},
    job = nil,
    lastScan = nil,
    woken = {},
    wokenCount = 0,
    metrics = { jobs = 0, ticks = 0, errors = 0, removed = 0, skipped = 0, passes = 0, wakes = 0 },
}
ProjectALife.Cleanup = Cleanup

Cleanup.known = {}
for _, name in ipairs(Cleanup.scopes) do Cleanup.known[name] = true end

function Cleanup.reset()
    Cleanup.job = nil
    Cleanup.lastScan = nil
    Cleanup.woken = {}
    Cleanup.wokenCount = 0
    Cleanup.guardAt = nil
    Cleanup.progressAt = nil
    Cleanup.metrics = { jobs = 0, ticks = 0, errors = 0, removed = 0, skipped = 0, passes = 0, wakes = 0 }
end

function Cleanup.configure(adapters)
    Cleanup.adapters = type(adapters) == "table" and adapters or {}
end

function Cleanup.now()
    if type(Cleanup.adapters.nowMs) == "function" then return Cleanup.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Cleanup.hours()
    if type(Cleanup.adapters.hours) == "function" then return Cleanup.adapters.hours() end
    if type(getGameTime) ~= "function" then return 0 end
    local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and type(value) == "number" then return value end
    return 0
end

function Cleanup.log(text)
    if type(Cleanup.adapters.log) == "function" then
        pcall(Cleanup.adapters.log, text)
    elseif type(print) == "function" then
        pcall(print, text)
    end
end

function Cleanup.add(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then return false end
    Cleanup.collectors[spec.id] = spec
    return true
end

function Cleanup.scopeSet(source)
    local set = {}
    if type(source) ~= "table" then return set end
    for key, value in pairs(source) do
        if type(key) == "number" and type(value) == "string" and Cleanup.known[value] then
            set[value] = true
        elseif type(key) == "string" and Cleanup.known[key] and value == true then
            set[key] = true
        end
    end
    return set
end

function Cleanup.scopeList(set)
    local list = {}
    for _, name in ipairs(Cleanup.scopes) do
        if type(set) == "table" and set[name] == true then list[#list + 1] = name end
    end
    return list
end

function Cleanup.enabled(collector, job)
    if collector.scopes == nil then return true end
    for _, name in ipairs(collector.scopes) do
        if job.scopes[name] == true then return true end
    end
    return false
end

function Cleanup.count(job, key, amount)
    local counts = job.counts
    counts[key] = (counts[key] or 0) + (amount or 1)
    return counts[key]
end

function Cleanup.fail(job, where, reason)
    job.errors = (job.errors or 0) + 1
    Cleanup.metrics.errors = Cleanup.metrics.errors + 1
    job.errorList = job.errorList or {}
    if #job.errorList < Cleanup.settings.errorCap then
        job.errorList[#job.errorList + 1] = tostring(where) .. ": " .. string.sub(tostring(reason), 1, 160)
    end
end

function Cleanup.skip(job, category, entry)
    job.skippedTotal = (job.skippedTotal or 0) + 1
    Cleanup.metrics.skipped = Cleanup.metrics.skipped + 1
    Cleanup.count(job, category .. ".skipped")
    job.skipped = job.skipped or {}
    if #job.skipped < Cleanup.settings.skipCap then
        entry.category = category
        job.skipped[#job.skipped + 1] = entry
    end
end

function Cleanup.open(job)
    local budget = job.budget
    if budget == nil then return true end
    if budget.units <= 0 then return false end
    return Cleanup.now() < budget.deadline
end

function Cleanup.spend(job, units)
    local budget = job.budget
    if budget ~= nil then budget.units = budget.units - (units or 1) end
    job.units = (job.units or 0) + (units or 1)
end

function Cleanup.slice(job)
    local settings = Cleanup.settings
    local budgetMs = tonumber(job.budgetMs) or settings.budgetMs
    local units = tonumber(job.unitBudget) or settings.unitBudget
    job.budget = { deadline = Cleanup.now() + budgetMs, units = units }
    return job.budget
end

function Cleanup.activeOrder(job)
    local list = {}
    for _, id in ipairs(Cleanup.order) do
        local collector = Cleanup.collectors[id]
        if collector ~= nil and Cleanup.enabled(collector, job) then list[#list + 1] = id end
    end
    return list
end

function Cleanup.newJob(kind, scopes, options)
    options = type(options) == "table" and options or {}
    Cleanup.metrics.jobs = Cleanup.metrics.jobs + 1
    local job = {
        id = tostring(Cleanup.metrics.jobs) .. ":" .. tostring(math.floor(Cleanup.now())),
        kind = kind,
        run = kind == "run",
        scopes = scopes,
        overrides = type(options.overrides) == "table" and options.overrides or {},
        by = options.by,
        startedMs = Cleanup.now(),
        startedHours = Cleanup.hours(),
        counts = {},
        errors = 0,
        stage = "main",
        phase = 1,
        passes = 0,
        cursor = {},
        begun = {},
        units = 0,
        budgetMs = options.budgetMs,
        unitBudget = options.unitBudget,
        lists = {},
        areaRadius = math.max(4, math.min(60, math.floor(tonumber(options.radius) or Cleanup.settings.areaRadius))),
    }
    job.order = Cleanup.activeOrder(job)
    return job
end

function Cleanup.busy()
    return Cleanup.job ~= nil and Cleanup.job.finished ~= true
end

function Cleanup.pendingCount(job)
    local total = 0
    for _, id in ipairs(job.order) do
        local collector = Cleanup.collectors[id]
        if collector ~= nil and type(collector.pending) == "function" then
            local ok, value = pcall(collector.pending, job)
            if ok then total = total + (tonumber(value) or 0) else Cleanup.fail(job, id .. ".pending", value) end
        end
    end
    job.pending = total
    return total
end

function Cleanup.pendingRows(job, limit)
    local rows = {}
    for _, id in ipairs(job.order) do
        local collector = Cleanup.collectors[id]
        if collector ~= nil and type(collector.pendingList) == "function" then
            local ok, list = pcall(collector.pendingList, job, limit)
            if ok and type(list) == "table" then
                for _, row in ipairs(list) do
                    if #rows >= limit then break end
                    rows[#rows + 1] = row
                end
            end
        end
    end
    return rows
end

function Cleanup.persistRun(job)
    local ok, reason = Lock.set("running", {
        job = job,
        startedMs = job.startedMs,
        startedHours = job.startedHours,
        by = job.by,
    })
    return ok, reason
end

function Cleanup.watchKey(x, y)
    return math.floor(x / 8) .. ":" .. math.floor(y / 8)
end

function Cleanup.watch(job, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local watch = job.nextWatch
    if watch == nil then
        watch = {}
        job.nextWatch = watch
    end
    local size = job.watchSize or 0
    local key = Cleanup.watchKey(x, y)
    if watch[key] ~= true and size < Cleanup.settings.watchCap then
        watch[key] = true
        job.watchSize = size + 1
    end
end

function Cleanup.begin(job)
    job.stage = "main"
    job.phase = 1
    job.begun = {}
    job.nextWatch = {}
    job.watchSize = 0
    job.safehouseList = nil
    Cleanup.volatile = {}
    job.passes = (job.passes or 0) + 1
    Cleanup.metrics.passes = Cleanup.metrics.passes + 1
end

function Cleanup.runCollector(job, id)
    local collector = Cleanup.collectors[id]
    if collector == nil then return true end
    if job.begun[id] ~= true then
        job.begun[id] = true
        if type(collector.begin) == "function" then
            local ok, reason = pcall(collector.begin, job)
            if not ok then
                Cleanup.fail(job, id .. ".begin", reason)
                return true
            end
        end
    end
    local ok, finished = pcall(collector.step, job)
    if not ok then
        Cleanup.fail(job, id .. ".step", finished)
        job.faults = job.faults or {}
        job.faults[id] = (job.faults[id] or 0) + 1
        return job.faults[id] >= 3
    end
    if finished == true then
        if type(collector.finish) == "function" then
            local closed, reason = pcall(collector.finish, job)
            if not closed then Cleanup.fail(job, id .. ".finish", reason) end
        end
        return true
    end
    return false
end

function Cleanup.terminal(id)
    local collector = Cleanup.collectors[id]
    return collector ~= nil and collector.terminal == true
end

function Cleanup.mainFinished(job)
    for index = job.phase, #job.order do
        if not Cleanup.terminal(job.order[index]) then return false end
    end
    return true
end

function Cleanup.complete(job)
    job.stage = "done"
    job.finished = true
    job.finishedMs = Cleanup.now()
    job.finishedHours = Cleanup.hours()
    if job.run then
        job.pending = Cleanup.pendingCount(job)
        Lock.set("done", { job = job, finishedMs = job.finishedMs, finishedHours = job.finishedHours,
            by = job.by })
        Cleanup.audit(job, "done")
        Cleanup.finalReport(job)
    else
        Cleanup.lastScan = Cleanup.summary(job)
        Cleanup.audit(job, "scan_done")
    end
end

function Cleanup.pass(job)
    local settings = Cleanup.settings
    Cleanup.slice(job)
    while Cleanup.open(job) do
        local id = job.order[job.phase]
        if id == nil then
            if job.run then job.pending = Cleanup.pendingCount(job) end
            if job.run and job.pending > 0 and job.abandon ~= true then
                job.stage = "pending"
                job.watch = job.nextWatch
                job.nextPassMs = Cleanup.now() + settings.passMs
            else
                Cleanup.complete(job)
            end
            return
        end
        if Cleanup.terminal(id) and job.run and job.abandon ~= true then
            local pending = Cleanup.pendingCount(job)
            if pending > 0 then
                job.stage = "pending"
                job.watch = job.nextWatch
                job.nextPassMs = Cleanup.now() + settings.passMs
                return
            end
        end
        if Cleanup.runCollector(job, id) then
            job.phase = job.phase + 1
            if job.run then Cleanup.persistRun(job) end
        end
    end
end

function Cleanup.tick()
    local job = Cleanup.job
    if job == nil or job.finished == true then
        Cleanup.guard()
        return 0
    end
    Cleanup.metrics.ticks = Cleanup.metrics.ticks + 1
    if job.cancelled == true then
        Cleanup.finishCancel(job)
        return 0
    end
    local before = job.units or 0
    if job.stage == "pending" then
        local now = Cleanup.now()
        if Cleanup.wokenCount == 0 and now < (job.nextPassMs or 0) then return 0 end
        Cleanup.takeWoken(job)
        Cleanup.begin(job)
    end
    Cleanup.pass(job)
    Cleanup.progress(job)
    return (job.units or 0) - before
end

function Cleanup.onSquareLoaded(square)
    local job = Cleanup.job
    if job == nil or job.run ~= true or job.stage ~= "pending" or square == nil then return false end
    local x, y
    if type(square.getX) == "function" then
        x, y = square:getX(), square:getY()
    end
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local key = math.floor(x / 8) .. ":" .. math.floor(y / 8)
    local watch = job.watch
    if type(watch) ~= "table" or watch[key] ~= true then return false end
    if Cleanup.woken[key] ~= true then
        Cleanup.woken[key] = true
        Cleanup.wokenCount = Cleanup.wokenCount + 1
        Cleanup.metrics.wakes = Cleanup.metrics.wakes + 1
    end
    return true
end

function Cleanup.takeWoken(job)
    job.lastWoken = Cleanup.wokenCount
    Cleanup.woken = {}
    Cleanup.wokenCount = 0
end

function Cleanup.progress(job)
    local now = Cleanup.now()
    if Cleanup.progressAt ~= nil and now - Cleanup.progressAt < Cleanup.settings.progressMs then return false end
    Cleanup.progressAt = now
    if type(Cleanup.adapters.progress) == "function" then
        pcall(Cleanup.adapters.progress, job, Cleanup.status())
    end
    return true
end

function Cleanup.audit(job, tag)
    local counts = job.counts
    local parts = {}
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. tostring(counts[key]) end
    Cleanup.log("[ALIFE-CLEANUP] " .. tostring(tag) .. " job=" .. tostring(job.id) .. " kind=" .. tostring(job.kind)
        .. " scopes=" .. table.concat(Cleanup.scopeList(job.scopes), ",") .. " errors=" .. tostring(job.errors or 0)
        .. " skipped=" .. tostring(job.skippedTotal or 0) .. " pending=" .. tostring(job.pending or 0)
        .. " " .. table.concat(parts, " "))
    Cleanup.auditCategories(job, tag)
end

function Cleanup.auditCategories(job, tag)
    if tag ~= "done" and tag ~= "scan_done" and tag ~= "cancelled" then return end
    local groups, order = {}, {}
    local keys = {}
    for key in pairs(job.counts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local category = string.match(key, "^([^.]+)%.")
        if category ~= nil then
            if groups[category] == nil then
                groups[category] = {}
                order[#order + 1] = category
            end
            groups[category][#groups[category] + 1] = string.sub(key, #category + 2) .. "=" .. tostring(job.counts[key])
        end
    end
    for _, category in ipairs(order) do
        Cleanup.log("[ALIFE-CLEANUP] category=" .. category .. " job=" .. tostring(job.id) .. " kind=" .. tostring(job.kind)
            .. " " .. table.concat(groups[category], " "))
    end
end

function Cleanup.ready()
    if type(Cleanup.adapters.ready) == "function" then return Cleanup.adapters.ready() == true end
    local runtime = ProjectALife.Runtime
    return runtime ~= nil and runtime.started == true
end

function Cleanup.category(job, name)
    local prefix = name .. "."
    local removed, skipped, found = 0, 0, 0
    for key, value in pairs(job.counts) do
        if string.sub(key, 1, #prefix) == prefix then
            local tail = string.sub(key, #prefix + 1)
            if tail == "removed" then removed = value
            elseif tail == "skipped" then skipped = value
            elseif tail == "found" then found = value end
        end
    end
    return found, removed, skipped
end

function Cleanup.estimate(counts)
    local units = 0
    for _, key in ipairs({ "npcs.found", "npcs.squads", "bases.found", "vehicles.found", "loot.corpses", "events.found",
            "bases.area_found", "bases.scenes" }) do
        units = units + (tonumber(counts[key]) or 0)
    end
    local per = math.max(1, Cleanup.settings.unitBudget)
    local ticks = math.ceil(units / per) + 1
    return { units = units, ticks = ticks, seconds = math.ceil(ticks / 30) }
end

function Cleanup.summary(job)
    local result = {
        id = job.id, kind = job.kind, stage = job.stage, finished = job.finished == true,
        scopes = Cleanup.scopeList(job.scopes), counts = {}, errors = job.errors or 0,
        skippedTotal = job.skippedTotal or 0, pending = job.pending or 0, passes = job.passes or 0,
        startedMs = job.startedMs, finishedMs = job.finishedMs, by = job.by,
        sites = job.siteRows, protected = job.protectedRows, errorList = job.errorList,
        abandoned = job.abandon == true,
    }
    for key, value in pairs(job.counts) do result.counts[key] = value end
    result.estimate = Cleanup.estimate(job.counts)
    return result
end

function Cleanup.status()
    local job = Cleanup.job
    local mode = Lock.mode()
    local status = { ok = true, mode = mode, locked = Lock.locked(), version = 1 }
    if job ~= nil then
        status.job = Cleanup.summary(job)
        status.units = job.units or 0
        status.removed, status.skipped = Cleanup.totals(job)
        status.nextPassMs = job.nextPassMs
    end
    if Cleanup.lastScan ~= nil then status.scan = Cleanup.lastScan end
    status.refusals = Lock.refusals()
    return status
end

function Cleanup.totals(job)
    local removed = 0
    for key, value in pairs(job.counts) do
        if string.sub(key, -8) == ".removed" then removed = removed + value end
    end
    return removed, job.skippedTotal or 0
end

function Cleanup.qaLine()
    local job = Cleanup.job
    local mode = Lock.mode()
    local shown = mode
    if mode == "done" and Lock.locked() then shown = "locked" end
    local removed, skipped, pending = 0, 0, 0
    if job ~= nil then
        removed, skipped = Cleanup.totals(job)
        pending = tonumber(job.pending) or 0
    elseif mode ~= "idle" then
        local state = Lock.peek()
        local saved = type(state) == "table" and state.job or nil
        if type(saved) == "table" and type(saved.counts) == "table" then
            removed, skipped = Cleanup.totals(saved)
            pending = tonumber(saved.pending) or 0
        end
    end
    return "[ALIFE-QA] Cleanup: mode=" .. tostring(shown) .. " removed=" .. tostring(removed)
        .. " skipped=" .. tostring(skipped) .. " pending=" .. tostring(pending)
        .. " refused=" .. tostring(Lock.metrics.total) .. " errors=" .. tostring(Cleanup.metrics.errors)
end

function Cleanup.scan(options)
    if Cleanup.busy() then return nil, "cleanup_busy" end
    if Lock.mode() == "running" then return nil, "cleanup_running" end
    if not Cleanup.ready() then return nil, "runtime_not_started" end
    options = type(options) == "table" and options or {}
    local scopes = Cleanup.scopeSet(options.scopes)
    local any = false
    for _ in pairs(scopes) do any = true break end
    if not any then
        for name in pairs(Cleanup.known) do scopes[name] = true end
    end
    local job = Cleanup.newJob("scan", scopes, options)
    job.scanAll = true
    Cleanup.begin(job)
    Cleanup.job = job
    Cleanup.audit(job, "scan_start")
    return job
end

function Cleanup.validate(options)
    options = type(options) == "table" and options or {}
    if options.confirm ~= Cleanup.PHRASE then return false, "confirm_phrase_required" end
    local scopes = Cleanup.scopeSet(options.scopes)
    local any = false
    for _ in pairs(scopes) do any = true break end
    if not any then return false, "no_scope" end
    local overridden = false
    if type(options.overrides) == "table" then
        for _ in pairs(options.overrides) do overridden = true break end
    end
    if scopes.unverified == true or scopes.reputation == true or scopes.creatorStore == true or overridden then
        if options.confirm2 ~= Cleanup.PHRASE2 then return false, "second_confirmation_required" end
    end
    return true, scopes
end

function Cleanup.run(options)
    if Cleanup.busy() then return nil, "cleanup_busy" end
    if Lock.mode() == "running" then return nil, "cleanup_running" end
    if not Cleanup.ready() then return nil, "runtime_not_started" end
    local valid, scopes = Cleanup.validate(options)
    if not valid then return nil, scopes end
    local job = Cleanup.newJob("run", scopes, options)
    Cleanup.begin(job)
    local saved, reason = Cleanup.persistRun(job)
    if not saved then return nil, reason or "persist_failed" end
    Cleanup.job = job
    Cleanup.woken = {}
    Cleanup.wokenCount = 0
    Cleanup.audit(job, "run_start")
    return job
end

function Cleanup.resume()
    if Cleanup.job ~= nil then return Cleanup.job end
    if Lock.mode() ~= "running" then return nil end
    local state = Lock.peek()
    local saved = type(state) == "table" and state.job or nil
    if type(saved) ~= "table" or type(saved.counts) ~= "table" then return nil end
    saved.order = Cleanup.activeOrder(saved)
    saved.resumed = (saved.resumed or 0) + 1
    saved.finished = nil
    saved.cancelled = nil
    saved.safehouseList = nil
    Cleanup.begin(saved)
    Cleanup.job = saved
    Cleanup.audit(saved, "resumed")
    return saved
end

function Cleanup.cancel(options)
    options = type(options) == "table" and options or {}
    local job = Cleanup.job
    local mode = Lock.mode()
    if mode == "done" then
        if options.reopen ~= true then return false, "already_done" end
        Lock.set("idle", { reopenedMs = Cleanup.now() })
        Cleanup.audit(job or { id = "-", kind = "run", scopes = {}, counts = {} }, "reopened")
        return true, "reopened"
    end
    if job == nil or job.finished == true then
        if mode == "running" then
            Lock.set("idle", { cancelledMs = Cleanup.now() })
            return true, "unlocked"
        end
        return false, "nothing_to_cancel"
    end
    job.cancelled = true
    return true, "cancelling"
end

function Cleanup.finishCancel(job)
    job.finished = true
    job.stage = "cancelled"
    job.finishedMs = Cleanup.now()
    if job.run then
        Lock.set("idle", { cancelledMs = job.finishedMs, job = job })
        Cleanup.audit(job, "cancelled")
        Cleanup.finalReport(job)
    else
        Cleanup.audit(job, "scan_cancelled")
    end
end

function Cleanup.finish(options)
    local job = Cleanup.job
    if job == nil or job.run ~= true or job.finished == true then return false, "nothing_to_finish" end
    options = type(options) == "table" and options or {}
    if options.confirm ~= Cleanup.PHRASE then return false, "confirm_phrase_required" end
    job.abandonedRows = Cleanup.pendingRows(job, 200)
    job.abandon = true
    job.nextPassMs = 0
    return true, "abandoning_pending"
end

function Cleanup.guard()
    if Lock.mode() ~= "done" then return 0 end
    local now = Cleanup.now()
    if Cleanup.guardAt ~= nil and now < Cleanup.guardAt then return 0 end
    Cleanup.guardAt = now + Cleanup.settings.guardMs
    local state = Cleanup.collectors.worldState
    if state == nil or type(state.guard) ~= "function" then return 0 end
    local saved = Lock.peek()
    local job = type(saved) == "table" and saved.job or nil
    if type(job) ~= "table" or type(job.scopes) ~= "table" or job.scopes.worldState ~= true then return 0 end
    local ok, removed = pcall(state.guard, job)
    if ok then return tonumber(removed) or 0 end
    Cleanup.fail(job, "guard", removed)
    return 0
end

function Cleanup.finalReport(job)
    local lines = Cleanup.reportLines(job)
    job.report = lines
    for _, line in ipairs(lines) do Cleanup.log("[ALIFE-CLEANUP] report " .. line) end
    if type(Cleanup.adapters.writeReport) == "function" then
        local ok, reason = pcall(Cleanup.adapters.writeReport, lines, job)
        if not ok then Cleanup.fail(job, "report", reason) end
    end
    return lines
end

function Cleanup.reportLines(job)
    local lines = {}
    lines[#lines + 1] = "A-Life cleanup report job=" .. tostring(job.id) .. " kind=" .. tostring(job.kind)
        .. " stage=" .. tostring(job.stage)
    lines[#lines + 1] = "scopes=" .. table.concat(Cleanup.scopeList(job.scopes), ",")
    local keys = {}
    for key in pairs(job.counts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = key .. "=" .. tostring(job.counts[key]) end
    lines[#lines + 1] = "errors=" .. tostring(job.errors or 0) .. " skippedTotal=" .. tostring(job.skippedTotal or 0)
        .. " pending=" .. tostring(job.pending or 0)
    for _, row in ipairs(job.errorList or {}) do lines[#lines + 1] = "error " .. row end
    for _, row in ipairs(job.skipped or {}) do
        lines[#lines + 1] = "skipped " .. tostring(row.category) .. " site=" .. tostring(row.site)
            .. " x=" .. tostring(row.x) .. " y=" .. tostring(row.y) .. " z=" .. tostring(row.z)
            .. " what=" .. tostring(row.what) .. " why=" .. tostring(row.why)
    end
    for _, row in ipairs(job.residual or {}) do lines[#lines + 1] = "residual " .. tostring(row) end
    for _, row in ipairs(job.abandonedRows or {}) do
        lines[#lines + 1] = "abandoned " .. tostring(row.kind) .. " id=" .. tostring(row.id) .. " x=" .. tostring(row.x)
            .. " y=" .. tostring(row.y) .. " z=" .. tostring(row.z) .. " left=" .. tostring(row.left)
    end
    return lines
end

return Cleanup
