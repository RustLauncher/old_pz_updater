ProjectALife = ProjectALife or {}

local Retarget = {
    settings = {
        burstGapMs = 1500,
        refreshMs = 4000,
        eventsPerSecond = 8,
        zombieCooldownMs = 5000,
        keepSeenMs = 4000,
        drawCap = 40,
    },
    metrics = { events = 0, coalesced = 0, cooldownSkips = 0, keptTarget = 0, attracted = 0, capped = 0,
        noiseEmitted = 0, markFresh = 0 },
    shooters = setmetatable({}, { __mode = "k" }),
    window = { startMs = -1e12, count = 0 },
}
ProjectALife.ZombieRetarget = Retarget

function Retarget.nowMs()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function Retarget.reset()
    local metrics = Retarget.metrics
    for name in pairs(metrics) do metrics[name] = 0 end
    Retarget.shooters = setmetatable({}, { __mode = "k" })
    Retarget.window.startMs, Retarget.window.count = -1e12, 0
end

function Retarget.rowFor(shooter)
    local row = Retarget.shooters[shooter]
    if row == nil then
        row = { shotMs = -1e12, emitMs = -1e12, emitted = false, markMs = -1e12, markFreshMs = -1e12 }
        Retarget.shooters[shooter] = row
    end
    return row
end

function Retarget.takeWindow(now)
    local window = Retarget.window
    if now - window.startMs >= 1000 or now < window.startMs then
        window.startMs, window.count = now, 0
    end
    if window.count >= Retarget.settings.eventsPerSecond then return false end
    window.count = window.count + 1
    return true
end

function Retarget.noiseVerdict(shooter, now)
    if shooter == nil then return "emit" end
    now = tonumber(now) or Retarget.nowMs()
    local settings, metrics = Retarget.settings, Retarget.metrics
    local row = Retarget.rowFor(shooter)
    if now - row.shotMs > settings.burstGapMs or now < row.shotMs then row.emitted = false end
    row.shotMs = now
    local due = not row.emitted or now - row.emitMs >= settings.refreshMs or now < row.emitMs
    if not due then
        metrics.coalesced = metrics.coalesced + 1
        return "coalesced"
    end
    if not Retarget.takeWindow(now) then
        metrics.capped = metrics.capped + 1
        return "capped"
    end
    row.emitted, row.emitMs = true, now
    metrics.events = metrics.events + 1
    metrics.noiseEmitted = metrics.noiseEmitted + 1
    return "emit"
end

function Retarget.markVerdict(shooter, now)
    if shooter == nil then return true end
    now = tonumber(now) or Retarget.nowMs()
    local settings, metrics = Retarget.settings, Retarget.metrics
    local row = Retarget.rowFor(shooter)
    local last, fresh = row.markMs, row.markFreshMs
    row.markMs = now
    if now >= last and now - last <= settings.burstGapMs and now >= fresh and now - fresh < settings.refreshMs then
        metrics.coalesced = metrics.coalesced + 1
        return false
    end
    row.markFreshMs = now
    metrics.events = metrics.events + 1
    metrics.markFresh = metrics.markFresh + 1
    return true
end

function Retarget.drawVerdict(memory, strong, now)
    if memory == nil or memory.prey == nil then return "draw" end
    if strong == true then return "kept" end
    local drawAt = tonumber(memory.drawAtMs)
    if drawAt ~= nil and now >= drawAt and now - drawAt < Retarget.settings.zombieCooldownMs then
        return "cooldown"
    end
    return "draw"
end

function Retarget.noteSkip(memory, verdict, stamp)
    if memory == nil or memory.skipStamp == stamp then return end
    memory.skipStamp = stamp
    local metrics = Retarget.metrics
    if verdict == "kept" then
        metrics.keptTarget = metrics.keptTarget + 1
    else
        metrics.cooldownSkips = metrics.cooldownSkips + 1
    end
end

function Retarget.capOpen(mark)
    if mark == nil then return true end
    return (tonumber(mark.drawCount) or 0) < Retarget.settings.drawCap
end

function Retarget.noteCapped(memory, mark)
    local stamp = mark ~= nil and mark.untilMs or nil
    if memory ~= nil then
        if memory.capStamp == stamp then return end
        memory.capStamp = stamp
    end
    Retarget.metrics.capped = Retarget.metrics.capped + 1
end

function Retarget.claim(mark, memory, now)
    if mark ~= nil then mark.drawCount = (tonumber(mark.drawCount) or 0) + 1 end
    if memory ~= nil then memory.drawAtMs = now end
    Retarget.metrics.attracted = Retarget.metrics.attracted + 1
end

function Retarget.qaLine()
    local m = Retarget.metrics
    return "[ALIFE-QA] ZombieRetarget: events=" .. tostring(m.events) .. " coalesced=" .. tostring(m.coalesced)
        .. " cooldownSkips=" .. tostring(m.cooldownSkips) .. " keptTarget=" .. tostring(m.keptTarget)
        .. " attracted=" .. tostring(m.attracted) .. " capped=" .. tostring(m.capped)
        .. " noiseEmitted=" .. tostring(m.noiseEmitted) .. " markFresh=" .. tostring(m.markFresh)
end

return Retarget
