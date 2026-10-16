require "ProjectALife/Records/ALifeRecordCodec"
require "ProjectALife/Visitors/ALifeVisitorSchema"

ProjectALife = ProjectALife or {}

local Codec = ProjectALife.RecordCodec
local Schema = ProjectALife.VisitorSchema
local Text = {
    caps = { people = 4, nodes = 4, lines = 6, static = 8 },
    idleMs = { people = 600000, nodes = 600000, lines = 600000, static = 1800000 },
    retryMs = 60000,
    queueCap = 16,
    tickBudgetMs = 2,
    readBurst = 128,
    entries = {},
    seq = 0,
    useSeq = 0,
    adapters = {},
    pumping = false,
    metrics = { reads = 0, readLines = 0, bytesRead = 0, decodeSlices = 0, decodeMs = 0, evictions = 0,
        idleDrops = 0, failures = 0, rejects = 0, lastWhy = "-" },
}
ProjectALife.VisitorText = Text

function Text.clock()
    if type(Text.adapters.nowMs) == "function" then return Text.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) end
    return nil
end

function Text.nowMs()
    local now = Text.clock()
    if now ~= nil then return now end
    return os.time() * 1000
end

function Text.modId()
    if type(Text.adapters.modId) == "function" then return Text.adapters.modId() end
    local catalog = ProjectALife.Catalog
    if type(catalog) == "table" and type(catalog.MOD_ID) == "string" and catalog.MOD_ID ~= "" then
        return catalog.MOD_ID
    end
    return nil
end

function Text.valid(path)
    if type(path) ~= "string" or #path < 7 or #path > 80 then return false end
    if string.find(path, "..", 1, true) ~= nil or string.sub(path, 1, 1) == "/" then return false end
    if string.sub(path, -6) ~= ".alife" then return false end
    return string.match(path, "^[%w_%-%./]+$") ~= nil
end

function Text.classOf(path)
    local name = string.match(path, "([^/]+)$") or path
    if string.sub(name, 1, 7) == "people_" then return "people" end
    if string.sub(name, 1, 6) == "nodes_" then return "nodes" end
    if string.sub(name, 1, 6) == "lines_" or string.sub(name, 1, 8) == "generic_" then return "lines" end
    if string.sub(name, 1, 10) == "archetypes" then return "lines" end
    return "static"
end

function Text.open(path)
    local modId = Text.modId()
    if modId == nil then return nil, "mod_id_unavailable" end
    local opener = Text.adapters.reader
    if type(opener) ~= "function" then opener = getModFileReader end
    if type(opener) ~= "function" then return nil, "mod_file_reader_unavailable" end
    local ok, reader = pcall(opener, modId, Schema.DIR .. path, false)
    if not ok or reader == nil then return nil, "not_found" end
    if type(reader.readLine) ~= "function" then return nil, "reader_invalid" end
    return reader
end

function Text.pending()
    local count = 0
    for _, entry in pairs(Text.entries) do
        if entry.state ~= "ready" and entry.state ~= "failed" then count = count + 1 end
    end
    return count
end

function Text.admit(path, priority, now)
    if Text.pending() >= Text.queueCap then return nil, "queue_full" end
    Text.seq = Text.seq + 1
    local entry = { path = path, class = Text.classOf(path), state = "queued", priority = tonumber(priority) or 0,
        seq = Text.seq, requestedMs = now, used = Text.useSeq, lastUseMs = now, lines = {}, lineCount = 0 }
    Text.entries[path] = entry
    return entry
end

function Text.touch(entry)
    Text.useSeq = Text.useSeq + 1
    entry.used = Text.useSeq
    entry.lastUseMs = Text.nowMs()
end

function Text.arm()
    if Text.pumping then return end
    if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
        Events.OnTick.Add(Text.pump)
        Text.pumping = true
    end
end

function Text.pump()
    if Text.pending() == 0 then
        if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Remove) == "function" then
            Events.OnTick.Remove(Text.pump)
        end
        Text.pumping = false
        return
    end
    Text.step(Text.tickBudgetMs)
end

function Text.ensure(path, priority)
    if not Text.valid(path) then
        Text.metrics.lastWhy = "path_invalid"
        return false
    end
    local now = Text.nowMs()
    local entry = Text.entries[path]
    if entry ~= nil then
        if entry.state == "ready" then
            Text.touch(entry)
            return true
        end
        if entry.state == "failed" then
            if now - (entry.failedMs or 0) < Text.retryMs then return false end
            Text.entries[path] = nil
            entry = nil
        else
            local urgency = tonumber(priority)
            if urgency ~= nil and urgency > entry.priority then entry.priority = urgency end
            Text.arm()
            return false
        end
    end
    local admitted, reason = Text.admit(path, priority, now)
    if admitted == nil then
        Text.metrics.lastWhy = reason
        return false
    end
    Text.arm()
    return false
end

function Text.get(path)
    local entry = Text.entries[path]
    if entry == nil then return nil, "not_requested" end
    if entry.state == "ready" then
        Text.touch(entry)
        return entry.result
    end
    if entry.state == "failed" then return nil, "failed:" .. tostring(entry.why) end
    return nil, "loading"
end

function Text.memo(path, name, build)
    local result = Text.get(path)
    if result == nil then return nil end
    local value = result.memo[name]
    if value == nil then
        value = build(result)
        result.memo[name] = value
    end
    return value
end

function Text.fail(entry, why)
    entry.state, entry.why, entry.failedMs = "failed", why, Text.nowMs()
    entry.lines, entry.decode, entry.reader = nil, nil, nil
    Text.metrics.failures = Text.metrics.failures + 1
    Text.metrics.lastWhy = entry.path .. ":" .. tostring(why)
end

function Text.readLoop(entry, deadline)
    local reader, lines, count = entry.reader, entry.lines, entry.lineCount
    while true do
        for _ = 1, Text.readBurst do
            local line = reader:readLine()
            if line == nil then
                entry.lineCount = count
                return true
            end
            count = count + 1
            lines[count] = tostring(line)
        end
        entry.lineCount = count
        if deadline ~= nil then
            local now = Text.clock()
            if now == nil or now >= deadline then return false end
        end
    end
end

function Text.advance(entry, deadline)
    if entry.state == "queued" then
        local reader, reason = Text.open(entry.path)
        if reader == nil then
            Text.fail(entry, reason)
            return
        end
        Text.metrics.reads = Text.metrics.reads + 1
        entry.reader, entry.state = reader, "reading"
        return
    end
    if entry.state == "reading" then
        local ok, finished = pcall(Text.readLoop, entry, deadline)
        if not ok then
            if type(entry.reader.close) == "function" then pcall(entry.reader.close, entry.reader) end
            Text.fail(entry, "read_failed:" .. tostring(finished))
            return
        end
        if not finished then return end
        if type(entry.reader.close) == "function" then pcall(entry.reader.close, entry.reader) end
        local joined = table.concat(entry.lines, "\n")
        Text.metrics.readLines = Text.metrics.readLines + entry.lineCount
        Text.metrics.bytesRead = Text.metrics.bytesRead + #joined
        entry.bytes, entry.reader, entry.lines = #joined, nil, nil
        entry.rejects = {}
        local state, reason = Codec.decodeStart(joined, { lenient = true, text = true, rejects = entry.rejects, source = entry.path })
        if state == nil then
            Text.fail(entry, "decode_failed:" .. tostring(reason))
            return
        end
        entry.decode, entry.state = state, "decoding"
        return
    end
    if entry.state == "decoding" then
        local started = Text.clock()
        local budget = nil
        if deadline ~= nil and started ~= nil then budget = math.max(0.5, deadline - started) end
        local done, result, failure = Codec.decodeStep(entry.decode, budget)
        Text.metrics.decodeSlices = Text.metrics.decodeSlices + 1
        local ended = Text.clock()
        if started ~= nil and ended ~= nil and ended >= started then
            Text.metrics.decodeMs = Text.metrics.decodeMs + (ended - started)
        end
        if not done then return end
        if result == nil then
            Text.fail(entry, "decode_failed:" .. tostring(failure))
            return
        end
        result.memo = {}
        result.rejected = #entry.rejects
        result.path = entry.path
        Text.metrics.rejects = Text.metrics.rejects + #entry.rejects
        entry.result, entry.decode, entry.state = result, nil, "ready"
        Text.touch(entry)
        Text.enforce(entry.class, entry)
    end
end

function Text.nextEntry()
    local best = nil
    for _, entry in pairs(Text.entries) do
        if entry.state ~= "ready" and entry.state ~= "failed" then
            if best == nil or entry.priority > best.priority
                    or (entry.priority == best.priority and entry.seq < best.seq) then
                best = entry
            end
        end
    end
    return best
end

function Text.step(budgetMs)
    local budget = tonumber(budgetMs)
    if budget == nil then budget = Text.tickBudgetMs end
    local started = Text.clock()
    local deadline = nil
    if started ~= nil then deadline = started + budget end
    for _ = 1, 64 do
        local entry = Text.nextEntry()
        if entry == nil then break end
        Text.advance(entry, deadline)
        if deadline ~= nil then
            local now = Text.clock()
            if now == nil or now >= deadline then break end
        end
    end
    return Text.pending()
end

function Text.enforce(class, keep)
    local cap = Text.caps[class] or 4
    while true do
        local count, oldest = 0, nil
        for _, entry in pairs(Text.entries) do
            if entry.class == class and entry.state == "ready" then
                count = count + 1
                if entry ~= keep and (oldest == nil or entry.used < oldest.used) then oldest = entry end
            end
        end
        if count <= cap or oldest == nil then return end
        Text.entries[oldest.path] = nil
        Text.metrics.evictions = Text.metrics.evictions + 1
    end
end

function Text.sweep(nowMs)
    local now = tonumber(nowMs) or Text.nowMs()
    local stale = {}
    for path, entry in pairs(Text.entries) do
        if entry.state == "ready" and now - entry.lastUseMs >= (Text.idleMs[entry.class] or 600000) then
            stale[#stale + 1] = path
        elseif entry.state == "failed" and now - (entry.failedMs or 0) >= Text.retryMs * 2 then
            stale[#stale + 1] = path
        end
    end
    for index = 1, #stale do Text.entries[stale[index]] = nil end
    Text.metrics.idleDrops = Text.metrics.idleDrops + #stale
    return #stale
end

function Text.sweepTick()
    Text.sweep(nil)
end

function Text.drop(path)
    if Text.entries[path] == nil then return false end
    Text.entries[path] = nil
    return true
end

function Text.reset()
    Text.entries, Text.seq, Text.useSeq = {}, 0, 0
    Text.metrics = { reads = 0, readLines = 0, bytesRead = 0, decodeSlices = 0, decodeMs = 0, evictions = 0,
        idleDrops = 0, failures = 0, rejects = 0, lastWhy = "-" }
end

function Text.stats()
    local out = { entries = 0, ready = 0, loading = 0, failed = 0, bytes = 0, byClass = {}, caps = Text.caps }
    for _, entry in pairs(Text.entries) do
        out.entries = out.entries + 1
        local row = out.byClass[entry.class]
        if row == nil then
            row = { ready = 0, loading = 0, failed = 0 }
            out.byClass[entry.class] = row
        end
        if entry.state == "ready" then
            out.ready, row.ready = out.ready + 1, row.ready + 1
            out.bytes = out.bytes + (entry.bytes or 0)
        elseif entry.state == "failed" then
            out.failed, row.failed = out.failed + 1, row.failed + 1
        else
            out.loading, row.loading = out.loading + 1, row.loading + 1
        end
    end
    for key, value in pairs(Text.metrics) do out[key] = value end
    return out
end

function Text.qaLine()
    local stats = Text.stats()
    local capTotal = 0
    for _, cap in pairs(Text.caps) do capTotal = capTotal + cap end
    return "[ALIFE-QA] VisitorText shards=" .. tostring(stats.ready) .. "/" .. tostring(capTotal)
        .. " loading=" .. tostring(stats.loading) .. " failed=" .. tostring(stats.failed)
        .. " bytes=" .. tostring(stats.bytes) .. " reads=" .. tostring(stats.reads)
        .. " decodeSlices=" .. tostring(stats.decodeSlices) .. " decodeMs=" .. tostring(math.floor(stats.decodeMs))
        .. " evictions=" .. tostring(stats.evictions) .. " idleDrops=" .. tostring(stats.idleDrops)
        .. " rejects=" .. tostring(stats.rejects) .. " why=" .. tostring(stats.lastWhy)
end

if type(Events) == "table" and Events.EveryTenMinutes ~= nil and type(Events.EveryTenMinutes.Add) == "function" then
    Events.EveryTenMinutes.Add(Text.sweepTick)
end

return Text
