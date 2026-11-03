CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Agregados de janela que nao sao soma simples: maximo, p95 e percentual.
CD._perfTick = { n = 0, sum = 0, max = 0, hist = {} }
CD._perfTickPrevMs = nil
CD._perfStreamDogs = {}
CD._perfCStream = { i = 0, e = 0, s = 0, gapN = 0, gapSum = 0, gapSq = 0, gapMax = 0,
                    ageMax = 0, timeout = 0, overflow = 0, ids = {} }

local function resetCStream()
    local cs = CD._perfCStream
    cs.i, cs.e, cs.s, cs.gapN, cs.gapSum, cs.gapSq, cs.gapMax = 0, 0, 0, 0, 0, 0, 0
    cs.ageMax, cs.timeout, cs.overflow, cs.ids = 0, 0, 0, {}
end

---@return string side "server", "client" or "sp"
function CD.perfSide()
    if CD._perfSideStr then return CD._perfSideStr end
    local s = "sp"
    if isServer() then s = "server"
    elseif isClient() then s = "client" end
    CD._perfSideStr = s
    return s
end

---Timestamp that names this session's CSV, fixed until perfCsvArm starts a new one.
---@return string id YYYYmmdd-HHMMSS
function CD.perfSessionId()
    if CD._perfSessionId then return CD._perfSessionId end
    CD._perfSessionId = os.date("%Y%m%d-%H%M%S")
    return CD._perfSessionId
end

-- .txt e nao .csv: o getFileWriter filtra por ALLOWED_FILE_EXTENSIONS e devolve nil, sem erro e sem log.
---@return string name
function CD.perfCsvName()
    return "CompanionDogs_perf_" .. CD.perfSide() .. "_" .. CD.perfSessionId() .. ".txt"
end

local function csvCell(s)
    s = tostring(s or "")
    if string.find(s, '[,"\r\n]') then
        return '"' .. string.gsub(s, '"', '""') .. '"'
    end
    return s
end

---Buffers one CSV row; ignored while the CSV sink is off.
---@param t number timestamp in milliseconds
---@param kind string zone, count, ctx, bucket, spike or trace
---@param key string
---@param ms number|nil milliseconds, 0 when nil
---@param calls number|nil call count, or the value of count and ctx rows; 0 when nil
function CD.perfRow(t, kind, key, ms, calls)
    if not CD.PERF_CSV then return end
    local b = CD._perfCsvBuf
    b[#b + 1] = tostring(t) .. "," .. CD.perfSide() .. "," .. kind .. "," .. csvCell(key) ..
                "," .. string.format("%.1f", ms or 0) .. "," .. string.format("%.0f", calls or 0)
end

local function csvHeaderLines()
    return {
        "# CompanionDogs perf log",
        "# build=" .. tostring(CD.BUILD) .. " side=" .. CD.perfSide() ..
            " session=" .. CD.perfSessionId() .. " level=" .. tostring(CD._perfLv),
        "# clock_granularity_ms=" .. tostring(CD._perfCalMs or "?") ..
            " probe_cost_us=" .. tostring(CD._perfCalUs or "?") ..
            " clock_steps=" .. tostring(CD._perfCalSteps or "?"),
        "# spike_threshold_ms=" .. tostring(CD._perfSpikeMs or "?"),
        "# tick_interval=" .. tostring(CD.COMPANION_TICK_INTERVAL) ..
            " follow_interval=" .. tostring(CD.FOLLOW_TICK_INTERVAL) ..
            " dog_reg_ticks=" .. tostring(CD.DOG_REG_TICKS) ..
            " sniff_budget=" .. tostring(CD.TRICK_SNIFF_SCAN_BUDGET) ..
            " sniff_quota=" .. tostring(CD.TRICK_SNIFF_TICK_QUOTA),
        "# ms de zona sao EXCLUSIVOS e sao SOMA de janela; leia sempre com calls ao lado.",
        "t,side,kind,key,ms,calls",
    }
end

-- O LuaFileWriter nao expoe flush() e nao ha evento de encerramento: abre, escreve o lote e fecha.
local function csvPut(lines, append)
    local name = CD.perfCsvName()
    local w = getFileWriter(name, true, append)
    if not w then return false, "getFileWriter devolveu nil para '" .. name .. "'" end
    for i = 1, #lines do w:writeln(lines[i]) end
    w:close()
    return true
end

---Appends the buffered rows to the CSV; when the write fails the rows are dropped and the sink disarms.
function CD.perfCsvFlush()
    local b = CD._perfCsvBuf
    if #b == 0 then return end
    if not CD.PERF_CSV then
        CD._perfCsvBuf = {}
        return
    end
    local ok, err = csvPut(b, true)
    if ok then
        CD._perfCsvBuf = {}
        CD._perfCsvRows = CD._perfCsvRows + #b
        return
    end
    CD._perfCsvBuf = {}
    CD.PERF_CSV = false
    CD._perfCsvArmedMs = nil
    CD.log("[CD-PERF] *** escrita do CSV falhou, sink desarmado: " .. tostring(err) .. " ***")
end

local function ctxTable(fn, key)
    local tbl = fn()
    if type(tbl) == "table" then
        local v = tbl[key]
        if type(v) == "number" then return v end
    end
    return nil
end

---Buffers the context rows of a bucket: memory, frame and network figures, zombie and dog counts.
---@param t number timestamp in milliseconds
function CD.perfContext(t)
    local function row(key, v)
        if v ~= nil then
            CD.perfRow(t, "ctx", key, 0, v)
        end
    end
    row("lua_kb", collectgarbage("count"))
    if CD.perfSide() ~= "server" then
        row("fps_avg", getAverageFPS())
        row("fps_cap", getPerformance():getFramerate())
        row("cpu_ms", getCPUTime())
        row("gpu_ms", getGPUTime())
        row("cpu_wait_ms", getCPUWait())
        row("gpu_wait_ms", getGPUWait())
    end
    row("heap_used_mb", ctxTable(getPerformanceLocal, "memory-used"))
    row("animals_objects", ctxTable(getGameLocal, "animals-objects"))
    row("animals_instances", ctxTable(getGameLocal, "animals-instances"))
    row("zombies_loaded", ctxTable(getGameLocal, "zombies-loaded"))
    row("zombies_simulated", ctxTable(getGameLocal, "zombies-simulated"))
    row("players", ctxTable(getGameLocal, "players"))
    row("net_tx_packets", ctxTable(getNetworkLocal, "sent-packets"))
    row("net_rx_packets", ctxTable(getNetworkLocal, "received-packets"))
    if CD._perfDogN > 0 then
        row("dogs_min", CD._perfDogMin)
        row("dogs_max", CD._perfDogMax)
        row("dogs_avg", CD._perfDogSum / CD._perfDogN)
    end
    row("reg_builds", CD._regBuilds or 0)
    local ph = 0
    for _, v in pairs(CD._perfPhase) do if v > 0 then ph = ph + 1 end end
    row("clock_phases_seen", ph)
end

CD._perfBucketSince = nil
CD._perfBucketTicks = 0

local function dumpTick(now, total, kind)
    local n, tk, tv = CD._tn, CD._tk, CD._tv
    CD.perfRow(now, kind, "_total", total, 1)
    local seen, order = {}, {}
    for i = 1, n do
        local k = tk[i]
        if seen[k] == nil then
            seen[k] = 0
            order[#order + 1] = k
        end
        seen[k] = seen[k] + tv[i]
    end
    table.sort(order, function(a, b) return seen[a] > seen[b] end)
    local parts = {}
    for i = 1, #order do
        local k = order[i]
        CD.perfRow(now, kind, k, seen[k], 1)
        if i <= 8 and seen[k] > 0 then
            parts[#parts + 1] = string.format("%s %.0f", k, seen[k])
        end
    end
    if kind == "spike" then
        CD.log(string.format("[CD-PERF-SPIKE] %.0f ms in one tick | %s", total, table.concat(parts, " | ")))
    end
end

local function closeBucket(now, elapsed)
    local blk, calls, cnt = CD._perfBlk, CD._perfCalls, CD._perfCnt
    if CD.PERF_CSV then
        CD.perfRow(now, "bucket", "_secs", elapsed, CD._perfBucketTicks)
        for k, v in pairs(blk) do
            CD.perfRow(now, "zone", k, v, calls[k] or 0)
        end
        for k, v in pairs(cnt) do
            CD.perfRow(now, "count", k, 0, v)
        end
        CD.perfContext(now)
    end
    local w1, w2, w3 = CD._perfWinBlk, CD._perfWinCalls, CD._perfWinCnt
    for k, v in pairs(blk) do w1[k] = (w1[k] or 0) + v end
    for k, v in pairs(calls) do w2[k] = (w2[k] or 0) + v end
    for k, v in pairs(cnt) do w3[k] = (w3[k] or 0) + v end
    CD._perfBlk, CD._perfCalls, CD._perfCnt = {}, {}, {}
    CD._perfBucketTicks = 0
    CD._perfDogMin, CD._perfDogMax, CD._perfDogSum, CD._perfDogN = nil, nil, 0, 0
    CD.perfCsvFlush()
end

---End of tick for the meter: tick interval, spike and trace dumps, CSV caps and bucket rollover.
function CD.perfTickEnd()
    if CD._perfLv < 1 then
        if CD._pDepth ~= 0 then
            CD._pDepth, CD._pCur = 0, "other"
        end
        return
    end
    local now = getTimestampMs()
    CD._perfBucketTicks = CD._perfBucketTicks + 1
    CD._perfTicksTotal = (CD._perfTicksTotal or 0) + 1

    -- Intervalo ENTRE chamadas do nosso OnTick: e o tick da engine, nao o nosso tempo dentro dele.
    local prevTick = CD._perfTickPrevMs
    CD._perfTickPrevMs = now
    if prevTick then
        local gap = now - prevTick
        if gap > 0 then
            local t = CD._perfTick
            t.n = t.n + 1
            t.sum = t.sum + gap
            if gap > t.max then
                t.max = gap
            end
            local k = gap
            if k > 1000 then
                k = 1000
            end
            t.hist[k] = (t.hist[k] or 0) + 1
        end
    end

    local total, n, tv = 0, CD._tn, CD._tv
    for i = 1, n do total = total + tv[i] end
    local spike = total >= (CD._perfSpikeMs or 25)
    if spike or CD._perfTraceLeft > 0 then
        dumpTick(now, total, spike and "spike" or "trace")
    end
    CD._tn = 0
    CD._pDepth, CD._pCur = 0, "other"

    if CD._perfTraceLeft > 0 then
        CD._perfTraceLeft = CD._perfTraceLeft - 1
        if CD._perfTraceLeft == 0 then
            CD.log("[CD-PERF] trace done, disarmed.")
            CD.perfCsvFlush()
        end
    end

    local reg = CD.dogReg
    if reg and reg.dogs then
        local d = #reg.dogs
        if CD._perfDogMin == nil or d < CD._perfDogMin then
            CD._perfDogMin = d
        end
        if CD._perfDogMax == nil or d > CD._perfDogMax then
            CD._perfDogMax = d
        end
        CD._perfDogSum = CD._perfDogSum + d
        CD._perfDogN = CD._perfDogN + 1
    end

    local kb = collectgarbage("count")
    if type(kb) == "number" then
        local prev = CD._perfAllocPrev
        if prev and kb > prev then
            CD.perfCount("alloc.kb", kb - prev)
        end
        CD._perfAllocPrev = kb
    end

    if CD.PERF_CSV and CD._perfCsvArmedMs then
        local maxMs = CD.PERF_CSV_MAX_MIN * 60000
        if (now - CD._perfCsvArmedMs) > maxMs or CD._perfCsvRows > CD.PERF_CSV_MAX_ROWS then
            CD.PERF_CSV = false
            CD._perfCsvArmedMs = nil
            CD.log("[CD-PERF] CSV auto-disarmed (time or row cap). File: " .. CD.perfCsvName())
        end
    end

    if not CD._perfBucketSince then
        CD._perfBucketSince = now
        return
    end
    local elapsed = now - CD._perfBucketSince
    if elapsed < CD.PERF_BUCKET_MS then return end
    closeBucket(now, elapsed)
    CD._perfBucketSince = now
end

local function bandPerSec(n, secs)
    local g = CD._perfCalMs or 1
    if g <= 0 then
        g = 1
    end
    return (g * math.sqrt(math.max(n, 1))) / secs
end

local function fallGuardLine(secs, prefix)
    local n = CD._perfWinCalls["cli.fallguard"]
    if not n then return end
    local w = CD._perfWinCnt
    local f = {
        msPerSec = (CD._perfWinBlk["cli.fallguard"] or 0) / secs,
        band = bandPerSec(n, secs),
        n = n,
        sweeps = n / secs,
        dogs = (w["fallguard.check"] or 0) / n,
        misses = (w["fallguard.miss"] or 0) / secs,
        writes = w["fallguard.write"] or 0,
        secs = secs,
    }
    CD._perfLast.fallGuard = f
    CD.log(string.format(
        "%s fall guard: %.2f+-%.2f ms/s (n=%d) | %.1f sweeps/s x %.0f dogs | %.2f memo misses/s | %d flag writes in %.0fs",
        prefix, f.msPerSec, f.band, n, f.sweeps, f.dogs, f.misses, f.writes, secs))
end

local function perfDetailLine(secs)
    local ord = {}
    for k, v in pairs(CD._perfWinBlk) do ord[#ord + 1] = { k = k, v = v } end
    if #ord > 0 then
        table.sort(ord, function(a, b) return a.v > b.v end)
        local parts = {}
        for i = 1, math.min(#ord, 10) do
            local k = ord[i].k
            parts[#parts + 1] = string.format("%s %.2f+-%.2f (n=%d)", k, ord[i].v / secs,
                bandPerSec(CD._perfWinCalls[k] or 0, secs), CD._perfWinCalls[k] or 0)
        end
        CD.log("[CD-PERF] by zone (ms/s, exclusive): " .. table.concat(parts, " | "))
    end
    local cnt = {}
    for k, v in pairs(CD._perfWinCnt) do
        local ps = v / secs
        cnt[#cnt + 1] = string.format(ps < 10 and "%s %.2f/s" or "%s %.0f/s", k, ps)
    end
    if #cnt > 0 then
        table.sort(cnt)
        CD.log("[CD-PERF] counters: " .. table.concat(cnt, " | "))
    end
    local gau = {}
    CD._perfLast.gauges = {}
    for k, g in pairs(CD._perfWinGauge) do
        gau[#gau + 1] = string.format("%s avg %.1f max %.0f (n=%d)", k, g.sum / g.n, g.max, g.n)
        CD._perfLast.gauges[#CD._perfLast.gauges + 1] = { key = k, avg = g.sum / g.n, max = g.max, n = g.n }
    end
    if #gau > 0 then
        table.sort(gau)
        table.sort(CD._perfLast.gauges, function(a, b) return a.key < b.key end)
        CD.log("[CD-PERF] gauges (window average, NOT a rate): " .. table.concat(gau, " | "))
    end
    CD._perfLast.blocks = {}
    for i = 1, math.min(#ord, 10) do
        CD._perfLast.blocks[i] = { key = ord[i].k, msPerSec = ord[i].v / secs,
                                   callsPerSec = (CD._perfWinCalls[ord[i].k] or 0) / secs }
    end
    CD._perfLast.counters = {}
    local ck = {}
    for k, v in pairs(CD._perfWinCnt) do ck[#ck + 1] = { key = k, perSec = v / secs } end
    table.sort(ck, function(a, b) return a.perSec > b.perSec end)
    for i = 1, math.min(#ck, 20) do CD._perfLast.counters[i] = ck[i] end
    table.sort(CD._perfLast.counters, function(a, b) return a.key < b.key end)
    CD._perfLast.clockMs = CD._perfCalMs
    CD._perfLast.level = CD._perfLv
    CD._perfLast.csv = CD.PERF_CSV == true
    CD._perfWinBlk, CD._perfWinCalls, CD._perfWinCnt = {}, {}, {}
    CD._perfWinGauge = {}
end

local function tickPeriodLine(prefix)
    local t = CD._perfTick
    if t.n > 0 then
        local keys = {}
        for k in pairs(t.hist) do keys[#keys + 1] = k end
        table.sort(keys)
        local need, acc, p95 = t.n * 0.95, 0, t.max
        for i = 1, #keys do
            acc = acc + t.hist[keys[i]]
            if acc >= need then
                p95 = keys[i]
                break
            end
        end
        CD.log(string.format("%s: mean %.1f ms | p95 %.0f ms | max %.0f ms | n=%d",
            prefix, t.sum / t.n, p95, t.max, t.n))
        CD._perfLast.tickMeanMs, CD._perfLast.tickP95Ms, CD._perfLast.tickMaxMs = t.sum / t.n, p95, t.max
    end
    t.n, t.sum, t.max, t.hist = 0, 0, 0, {}
end

local function streamLineServer(secs)
    local w = CD._perfWinCnt
    local frames = w["stream.dogs"] or 0
    local stops = w["followstop"] or 0
    local dogs = 0
    for _ in pairs(CD._perfStreamDogs) do dogs = dogs + 1 end
    CD._perfStreamDogs = {}
    if frames == 0 and stops == 0 then return end
    local hz = (dogs > 0) and (frames / secs / dogs) or 0
    CD.log(string.format(
        "[CD-PERF] stream: %.1f Hz per dog (avg over %d dogs) | %.1f dog-frames/s | idle %.1f/s | stops %.2f/s: radius %.2f, left follow %.2f, no viewer %.2f, landing %.2f",
        hz, dogs, frames / secs, (w["stream.idle"] or 0) / secs, stops / secs,
        (w["followstop.radius"] or 0) / secs, (w["followstop.leftfollow"] or 0) / secs,
        (w["followstop.noviewer"] or 0) / secs, (w["followstop.landing"] or 0) / secs))
    CD._perfLast.streamHz, CD._perfLast.streamDogs = hz, dogs
end

local function streamLineClient()
    local cs = CD._perfCStream
    local frames = cs.i + cs.e + cs.s
    if frames > 0 or cs.timeout > 0 then
        local dogs = 0
        for _ in pairs(cs.ids) do dogs = dogs + 1 end
        local mean = (cs.gapN > 0) and (cs.gapSum / cs.gapN) or 0
        local var = (cs.gapN > 0) and (cs.gapSq / cs.gapN - mean * mean) or 0
        if var < 0 then
            var = 0
        end
        local pf = (frames > 0) and (100 / frames) or 0
        CD.log(string.format(
            "[CD-PERF-CLIENT] stream: %d frames over %d dogs (interp %.0f%% | extrap %.0f%% | snap %.0f%%) | packet gap mean %.0f ms, max %.0f, jitter %.0f | age max %.0f ms | timeouts %d | overflows %d",
            frames, dogs, cs.i * pf, cs.e * pf, cs.s * pf, mean, cs.gapMax, math.sqrt(var),
            cs.ageMax, cs.timeout, cs.overflow))
    end
    resetCStream()
end

---Adds one companion tick to the load sample and logs the report every PERF_DEBUG_SECS.
---@param t0 number|nil timestamp in milliseconds at the start of the tick; nil while measuring is off
function CD.perfSample(t0)
    if not t0 then return end
    local now = getTimestampMs()
    CD._perfMs = (CD._perfMs or 0) + (now - t0)
    CD._perfN = (CD._perfN or 0) + 1
    if not CD._perfSince then
        CD._perfSince = now
        return
    end
    local elapsed = now - CD._perfSince
    if elapsed < CD.PERF_DEBUG_SECS * 1000 then return end
    local secs = elapsed / 1000
    local builds = (CD._regBuilds or 0) - (CD._perfBuilds or 0)
    CD._perfBuilds = CD._regBuilds or 0
    CD._perfLast.msPerSec  = CD._perfMs / secs
    CD._perfLast.msPerTick = CD._perfMs / CD._perfN
    CD._perfLast.ticksPerSec = CD._perfN / secs
    CD._perfLast.ticks   = CD._perfN
    CD._perfLast.secs    = secs
    CD._perfLast.dogs    = #CD.dogReg.dogs
    CD._perfLast.comps   = #CD.dogReg.companions
    CD._perfLast.scans   = builds / secs
    CD._perfLast.stampMs = now
    CD.log(string.format(
        "[CD-PERF] companionTick: %.2f ms/s load | %.3f ms/tick | %.1f ticks/s | %d ticks in %.0fs | dogs: %d | sweeps: %.1f/s | registry: %s",
        CD._perfMs / secs, CD._perfMs / CD._perfN, CD._perfN / secs, CD._perfN, secs,
        #CD.dogReg.dogs, builds / secs, (CD.DOG_REG == false) and "OFF" or "ON"))
    tickPeriodLine("[CD-PERF] engine tick")
    streamLineServer(secs)
    fallGuardLine(secs, "[CD-PERF]")
    perfDetailLine(secs)
    CD._perfMs, CD._perfN, CD._perfSince = 0, 0, now
end

---Client side report every PERF_DEBUG_SECS: registry sweeps and stream stats, plus frame and zone detail on a multiplayer client.
function CD.perfSampleClient()
    if CD._perfLv < 1 then return end
    local own = isClient()
    local now = getTimestampMs()
    if not CD._perfCliSince then
        CD._perfCliSince, CD._perfCliBuilds = now, CD._regBuilds or 0
        return
    end
    local elapsed = now - CD._perfCliSince
    if elapsed < CD.PERF_DEBUG_SECS * 1000 then return end
    local secs = elapsed / 1000
    local builds = (CD._regBuilds or 0) - (CD._perfCliBuilds or 0)
    local reg = CD.dogReg
    CD.log(string.format(
        "[CD-PERF-CLIENT] cell:getAnimals() sweeps: %.1f/s (%d in %.0fs) | registry: %d dogs (%d companions, %d strays)",
        builds / secs, builds, secs, #reg.dogs, #reg.companions, #reg.strays))
    if own then
        local tk = (CD._perfTicksTotal or 0) - (CD._perfCliTicks or 0)
        CD._perfCliTicks = CD._perfTicksTotal or 0
        CD._perfLast.ticks = tk
        CD._perfLast.ticksPerSec = tk / secs
        CD._perfLast.msPerSec = nil
        CD._perfLast.msPerTick = nil
        CD._perfLast.secs = secs
        CD._perfLast.dogs = #reg.dogs
        CD._perfLast.comps = #reg.companions
        CD._perfLast.scans = builds / secs
        CD._perfLast.stampMs = now
        tickPeriodLine("[CD-PERF-CLIENT] frame period")
    end
    streamLineClient()
    if own then
        fallGuardLine(secs, "[CD-PERF-CLIENT]")
        perfDetailLine(secs)
    end
    CD._perfCliSince, CD._perfCliBuilds = now, CD._regBuilds or 0
end

---Writes the zone breakdown of each of the next n ticks to the CSV, which must be armed.
---@param n number|nil ticks, clamped to 0..20000; 0 disarms
function CD.perfTraceArm(n)
    n = tonumber(n) or 0
    if n < 1 then n = 0 elseif n > 20000 then n = 20000 end
    CD._perfTraceLeft = n
    if n > 0 then
        CD.log("[CD-PERF] trace armed for " .. n .. " ticks.")
        if not CD.PERF_CSV then
            CD.log("[CD-PERF] *** trace needs the CSV sink: turn 'CSV log' on, or nothing is written. ***")
        end
    end
end

---Runs once: measures the clock granularity and the probe cost, and floors the spike threshold at three clock steps.
function CD.perfCalibrate()
    if CD._perfCalMs then return end
    local hist, rounds, acc = {}, 0, 0
    local guardStart = getTimestampMs()
    while rounds < 40 and (getTimestampMs() - guardStart) < 250 do
        local a = getTimestampMs()
        local b, spins = a, 0
        while b == a and spins < 500000 do
            b = getTimestampMs()
            spins = spins + 1
        end
        if b > a then
            local step = b - a
            hist[step] = (hist[step] or 0) + 1
            acc = acc + step
            rounds = rounds + 1
        end
    end
    local modal, modalN = 1, 0
    for step, n in pairs(hist) do
        if n > modalN then
            modal, modalN = step, n
        end
    end
    CD._perfCalMs = (rounds > 0) and modal or -1
    local parts = {}
    for step, n in pairs(hist) do parts[#parts + 1] = tostring(step) .. "x" .. tostring(n) end
    table.sort(parts)
    CD._perfCalSteps = table.concat(parts, ";")

    local scratch, N = {}, 20000
    local t0 = getTimestampMs()
    for _ = 1, N do
        local a = getTimestampMs()
        scratch.k = (scratch.k or 0) + (getTimestampMs() - a)
    end
    CD._perfCalUs = ((getTimestampMs() - t0) * 1000) / N

    local want = tonumber(CD.PERF_SPIKE_MS) or 25
    local floor3 = 3 * (CD._perfCalMs > 0 and CD._perfCalMs or 1)
    CD._perfSpikeMs = (want > floor3) and want or floor3
    CD.log(string.format(
        "[CD-PERF] calibration: clock granularity %.1f ms (steps %s) | probe cost %.2f us | spike threshold %.0f ms",
        CD._perfCalMs, CD._perfCalSteps, CD._perfCalUs, CD._perfSpikeMs))
    if CD._perfCalMs > 2 then
        CD.log("[CD-PERF] *** COARSE CLOCK: this VM cannot see sub-" .. tostring(CD._perfCalMs) ..
              "ms. Read the COUNTERS as primary evidence; ms per zone only in aggregate. ***")
    end
end

---Zeroes every meter accumulator and drops buffered CSV rows; calibration and CSV arming stay.
function CD.perfReset()
    CD._perfBlk, CD._perfCalls, CD._perfCnt = {}, {}, {}
    CD._perfWinBlk, CD._perfWinCalls, CD._perfWinCnt = {}, {}, {}
    CD._perfWinGauge = {}
    CD._tn, CD._pDepth, CD._pCur, CD._pLast = 0, 0, "other", 0
    CD._perfMs, CD._perfN, CD._perfSince = 0, 0, nil
    CD._perfCliSince, CD._perfCliBuilds = nil, nil
    CD._perfBucketSince, CD._perfBucketTicks = nil, 0
    CD._perfDogMin, CD._perfDogMax, CD._perfDogSum, CD._perfDogN = nil, nil, 0, 0
    CD._perfAllocPrev = nil
    CD._perfCsvBuf = {}
    CD._perfPhase = {}
    CD._perfTick = { n = 0, sum = 0, max = 0, hist = {} }
    CD._perfTickPrevMs = nil
    CD._perfStreamDogs = {}
    resetCStream()
end

---Arming starts a new CSV with its header; disarming flushes the buffer first.
---@param on boolean
function CD.perfCsvArm(on)
    if on then
        CD.perfCalibrate()
        CD._perfSessionId = nil
        CD._perfCsvRows = 0
        CD._perfCsvBuf = {}
        CD._perfCsvArmedMs = getTimestampMs()
        CD.PERF_CSV = true
        local ok, err = csvPut(csvHeaderLines(), false)
        if ok then
            CD.log("[CD-PERF] CSV armed: " .. CD.perfCsvName())
        else
            CD.PERF_CSV = false
            CD._perfCsvArmedMs = nil
            CD.log("[CD-PERF] *** CSV NAO ABRIU: " .. tostring(err) .. " ***")
        end
    else
        CD.perfCsvFlush()
        CD.PERF_CSV = false
        CD._perfCsvArmedMs = nil
        CD.log("[CD-PERF] CSV disarmed.")
    end
end
