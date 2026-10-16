ProjectALife = ProjectALife or {}
if ProjectALife.ExecutorHits then return ProjectALife.ExecutorHits end

local Hits = {
    graceMs = 4000,
    latencyMs = 250,
    ageCapMs = 3000,
    slackCap = 4,
    minSpeed = 1.5,
    maxSpeed = 7,
    limit = 256,
    recent = {},
    speeds = {},
    size = 0,
    speedCount = 0,
    metrics = { acceptedOrdered = 0, graceAccepted = 0, graceRefused = 0, slackAccepted = 0 },
}
ProjectALife.ExecutorHits = Hits

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Hits.reset()
    Hits.recent, Hits.speeds, Hits.size, Hits.speedCount = {}, {}, 0, 0
    Hits.metrics = { acceptedOrdered = 0, graceAccepted = 0, graceRefused = 0, slackAccepted = 0 }
end

function Hits.prune(now)
    local kept, count = {}, 0
    for uid, row in pairs(Hits.recent) do
        if now >= row.atMs and now - row.atMs <= Hits.graceMs then
            kept[uid] = row
            count = count + 1
        end
    end
    Hits.recent, Hits.size = kept, count
    if count >= Hits.limit then Hits.recent, Hits.size = {}, 0 end
end

function Hits.noteBound(uid, binding, now)
    if type(uid) ~= "string" or type(binding) ~= "table" or not finite(now) then return false end
    if Hits.recent[uid] == nil then
        if Hits.size >= Hits.limit then Hits.prune(now) end
        Hits.size = Hits.size + 1
    end
    Hits.recent[uid] = { binding = binding, generation = binding.generation, atMs = now }
    return true
end

function Hits.noteMove(uid, x, y, now)
    if type(uid) ~= "string" or not finite(x) or not finite(y) or not finite(now) then return nil end
    local row = Hits.speeds[uid]
    if row == nil then
        if Hits.speedCount >= Hits.limit * 2 then Hits.speeds, Hits.speedCount = {}, 0 end
        Hits.speedCount = Hits.speedCount + 1
        Hits.speeds[uid] = { x = x, y = y, atMs = now, speed = Hits.minSpeed }
        return Hits.minSpeed
    end
    local dt = (now - row.atMs) / 1000
    if dt >= 0.1 and dt <= 3 then
        local dx, dy = x - row.x, y - row.y
        local measured = math.sqrt(dx * dx + dy * dy) / dt
        row.speed = math.max(Hits.minSpeed, math.min(Hits.maxSpeed, math.max(measured, row.speed * 0.5)))
        row.x, row.y, row.atMs = x, y, now
    elseif dt > 3 or dt < 0 then
        row.x, row.y, row.atMs, row.speed = x, y, now, Hits.minSpeed
    end
    return row.speed
end

function Hits.forget(uid)
    if Hits.recent[uid] ~= nil then
        Hits.recent[uid] = nil
        Hits.size = math.max(0, Hits.size - 1)
    end
    Hits.speeds[uid] = nil
end

function Hits.grace(uid, generation, now)
    local row = Hits.recent[uid]
    if row == nil or row.generation ~= generation or not finite(now) or now < row.atMs
            or now - row.atMs > Hits.graceMs then
        Hits.metrics.graceRefused = Hits.metrics.graceRefused + 1
        return nil
    end
    return row.binding
end

function Hits.slack(uid, lastReportMs, now)
    if not finite(now) then return 0 end
    local age = finite(lastReportMs) and now - lastReportMs or Hits.ageCapMs
    age = math.max(0, math.min(Hits.ageCapMs, age))
    local row = Hits.speeds[uid]
    local speed = row ~= nil and row.speed or Hits.minSpeed
    return math.min(Hits.slackCap, speed * (age + Hits.latencyMs) / 1000)
end

function Hits.qaLine()
    local m = Hits.metrics
    return " ordered=" .. m.acceptedOrdered .. " hitGrace=" .. m.graceAccepted .. "/" .. m.graceRefused
        .. " hitSlack=" .. m.slackAccepted
end

return Hits
