require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local H = {
    refreshMs = 2000, players = {}, atMs = -1e9, known = {}, knownCount = 0, knownCap = 512,
    metrics = { frozen = 0, slept = 0, woke = 0, refreshes = 0 },
}
ProjectALife.Hibernation = H

H.minTiles, H.maxTiles, H.defaultTiles = 60, 400, 150

function H.tiles()
    local raw = tonumber(Gate.option("Population_HibernateTiles", H.defaultTiles))
    if raw ~= nil and raw <= 0 then return 0 end
    return Gate.number("Population_HibernateTiles", H.defaultTiles, H.minTiles, H.maxTiles)
end

function H.seedPerTown()
    return Gate.number("Population_SeedPerTown", 3, 1, 4)
end

function H.seedClearTiles()
    return Gate.number("Population_SeedClearTiles", 150, 0, 400)
end

function H.stale(now)
    now = tonumber(now) or Gate.nowMs()
    return now < H.atMs or now - H.atMs >= H.refreshMs
end

function H.refresh(list, now)
    H.players = type(list) == "table" and list or {}
    H.atMs = tonumber(now) or Gate.nowMs()
    H.metrics.refreshes = H.metrics.refreshes + 1
    return #H.players
end

function H.nearest(q, players)
    local qx, qy = tonumber(q.x), tonumber(q.y)
    if qx == nil or qy == nil then return 0 end
    local best = math.huge
    for _, p in ipairs(players) do
        local dx, dy = qx - (tonumber(p.x) or 0), qy - (tonumber(p.y) or 0)
        local d2 = dx * dx + dy * dy
        if d2 < best then best = d2 end
    end
    return math.sqrt(best)
end

function H.sleeping(q, players)
    local tiles = H.tiles()
    if tiles <= 0 or type(q) ~= "table" or q.state ~= "offline" or q.revenge ~= nil then return false end
    return H.nearest(q, players or H.players) > tiles
end

function H.note(q, asleep)
    local id = q.id
    if id == nil then return end
    if asleep then
        if not H.known[id] then
            if H.knownCount >= H.knownCap then H.known, H.knownCount = {}, 0 end
            H.known[id] = true
            H.knownCount = H.knownCount + 1
            H.metrics.slept = H.metrics.slept + 1
        end
    elseif H.known[id] then
        H.known[id] = nil
        H.knownCount = math.max(0, H.knownCount - 1)
        H.metrics.woke = H.metrics.woke + 1
    end
end

function H.asleep(q)
    local asleep = H.sleeping(q)
    H.note(q, asleep)
    return asleep
end

function H.freeze(q, hours, elapsed)
    elapsed = math.max(0, tonumber(elapsed) or 0)
    if elapsed > 0 then
        if q.legStartedHours ~= nil then q.legStartedHours = q.legStartedHours + elapsed end
        if q.decisionDueHours ~= nil then q.decisionDueHours = q.decisionDueHours + elapsed end
        local task = q.task
        if type(task) == "table" then
            if task.untilHours ~= nil then task.untilHours = task.untilHours + elapsed end
            if task.assignedHours ~= nil then task.assignedHours = task.assignedHours + elapsed end
        end
    end
    q.lastSimulatedHours = hours
    H.metrics.frozen = H.metrics.frozen + 1
end

function H.reset()
    H.players, H.atMs, H.known, H.knownCount = {}, -1e9, {}, 0
    H.metrics = { frozen = 0, slept = 0, woke = 0, refreshes = 0 }
end

function H.qaLine()
    local m = H.metrics
    return "[ALIFE-QA] hibernation tiles=" .. tostring(H.tiles()) .. " asleep=" .. tostring(H.knownCount)
        .. " slept=" .. tostring(m.slept) .. " woke=" .. tostring(m.woke) .. " frozenUpdates=" .. tostring(m.frozen)
end

return H
