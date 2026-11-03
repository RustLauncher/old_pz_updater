require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Senses/ALifeSight"

ProjectALife = ProjectALife or {}

local Control = {
    settings = {
        lineCacheMs = 400,
        staleLineMs = 1500,
        raysPerTick = 40,
        squadShooters = 8,
        squadWindowMs = 1000,
        laneRetryMs = 1200,
        laneHoldMs = 3500,
        laneRays = 8,
        giveUpMs = 5000,
        laneSides = { 2, -2, 3.5, -3.5, 5, -5, 7, -7 },
        laneForward = { 0, 1.5 },
    },
    metrics = { shots = 0, blockedByVehicle = 0, heldFire = 0, repositioned = 0, shotsPerSecPeak = 0,
        lineChecks = 0, lineHits = 0, lineStale = 0, laneSearches = 0, laneFails = 0, giveUps = 0 },
    cache = setmetatable({}, { __mode = "k" }),
    lanes = setmetatable({}, { __mode = "k" }),
    squads = {},
    tick = { stamp = -1, rays = 0 },
    second = { startMs = -1e12, count = 0 },
}
ProjectALife.FireControl = Control

function Control.reset()
    local metrics = Control.metrics
    for name in pairs(metrics) do metrics[name] = 0 end
    Control.cache = setmetatable({}, { __mode = "k" })
    Control.lanes = setmetatable({}, { __mode = "k" })
    Control.squads = {}
    Control.tick.stamp, Control.tick.rays = -1, 0
    Control.second.startMs, Control.second.count = -1e12, 0
end

function Control.nowMs()
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.nowMs) == "function" then return combat.nowMs() end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function Control.rayLeft(now)
    local tick = Control.tick
    local stamp = math.floor(now / 100)
    if tick.stamp ~= stamp then tick.stamp, tick.rays = stamp, 0 end
    return tick.rays < Control.settings.raysPerTick
end

function Control.rangedLine(shell, target)
    local combat = ProjectALife.Combat
    local sx, sy, sz = combat.xyzOf(shell)
    local tx, ty, tz = combat.xyzOf(target)
    if sx == nil or tx == nil then return combat.plainRangedLine(shell, target) end
    local now = Control.nowMs()
    local settings, metrics = Control.settings, Control.metrics
    local qsx, qsy = math.floor(sx * 2), math.floor(sy * 2)
    local qtx, qty = math.floor(tx * 2), math.floor(ty * 2)
    local level = math.floor(sz) * 16 + math.floor(tz)
    local row = Control.cache[shell]
    if row ~= nil and row.target == target then
        local same = row.sx == qsx and row.sy == qsy and row.tx == qtx and row.ty == qty and row.level == level
        if same and now >= row.atMs and now - row.atMs < settings.lineCacheMs then
            metrics.lineHits = metrics.lineHits + 1
            return row.clear, row.reason
        end
        if not Control.rayLeft(now) and now >= row.atMs and now - row.atMs < settings.staleLineMs then
            metrics.lineStale = metrics.lineStale + 1
            return row.clear, row.reason
        end
    end
    Control.tick.rays = Control.tick.rays + 1
    metrics.lineChecks = metrics.lineChecks + 1
    local clear, reason = combat.plainRangedLine(shell, target)
    if clear and combat.vehicleBlocks(sx, sy, sz, tx, ty, tz) then
        clear, reason = false, "vehicle"
        metrics.blockedByVehicle = metrics.blockedByVehicle + 1
    end
    if row == nil then
        row = {}
        Control.cache[shell] = row
    end
    row.target, row.sx, row.sy, row.tx, row.ty, row.level = target, qsx, qsy, qtx, qty, level
    row.atMs, row.clear, row.reason = now, clear, reason
    return clear, reason
end

function Control.squadKey(actor)
    if type(actor) ~= "table" then return nil end
    local memory = actor.memory
    if type(memory) == "table" and memory.groupId ~= nil then return tostring(memory.groupId) end
    return nil
end

function Control.admit(actor, shell, now)
    local key = Control.squadKey(actor)
    if key == nil then return true end
    local settings = Control.settings
    local squad = Control.squads[key]
    if squad == nil then
        squad = { startMs = now, set = {}, count = 0 }
        Control.squads[key] = squad
    end
    if now - squad.startMs >= settings.squadWindowMs or now < squad.startMs then
        squad.startMs, squad.set, squad.count = now, {}, 0
    end
    if squad.set[shell] then return true end
    if squad.count >= settings.squadShooters then
        Control.metrics.heldFire = Control.metrics.heldFire + 1
        return false
    end
    squad.set[shell] = true
    squad.count = squad.count + 1
    return true
end

function Control.noteShot(now)
    local metrics, second = Control.metrics, Control.second
    metrics.shots = metrics.shots + 1
    if now - second.startMs >= 1000 or now < second.startMs then
        second.startMs, second.count = now, 0
    end
    second.count = second.count + 1
    if second.count > metrics.shotsPerSecPeak then metrics.shotsPerSecPeak = second.count end
end

function Control.walkable(shell, origin, point)
    local maneuver = ProjectALife.FireManeuver
    if maneuver == nil or type(maneuver.route) ~= "function" then return true end
    local ok, routed = pcall(maneuver.route, shell, origin, point)
    return ok and routed == true
end

function Control.laneSearch(shell, target, now)
    local combat = ProjectALife.Combat
    local sx, sy, sz = combat.xyzOf(shell)
    local tx, ty, tz = combat.xyzOf(target)
    if sx == nil or tx == nil then return nil end
    local dx, dy = tx - sx, ty - sy
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 2 then return nil end
    dx, dy = dx / distance, dy / distance
    local px, py = -dy, dx
    local settings = Control.settings
    local origin = { x = sx, y = sy, z = sz }
    local rays = 0
    for _, forward in ipairs(settings.laneForward) do
        for _, side in ipairs(settings.laneSides) do
            local point = { x = math.floor(sx + px * side + dx * forward) + 0.5,
                y = math.floor(sy + py * side + dy * forward) + 0.5, z = sz }
            if not combat.vehicleBlocks(point.x, point.y, sz, tx, ty, tz) then
                if rays >= settings.laneRays then return nil end
                rays = rays + 1
                local sight = ProjectALife.Sight.between(point.x, point.y, sz, tx, ty, tz)
                if sight == "clear" and Control.walkable(shell, origin, point) then return point end
            end
        end
    end
    return nil
end

function Control.lane(shell, target, now)
    local row = Control.lanes[shell]
    if row == nil then
        row = { nextMs = -1e12, untilMs = -1e12 }
        Control.lanes[shell] = row
    end
    if row.point ~= nil and row.target == target and now < row.untilMs then return row.point end
    if now < row.nextMs then return nil end
    row.nextMs = now + Control.settings.laneRetryMs
    row.point, row.target = nil, nil
    Control.metrics.laneSearches = Control.metrics.laneSearches + 1
    local point = Control.laneSearch(shell, target, now)
    if point == nil then
        Control.metrics.laneFails = Control.metrics.laneFails + 1
        return nil
    end
    row.point, row.target, row.untilMs = point, target, now + Control.settings.laneHoldMs
    Control.metrics.repositioned = Control.metrics.repositioned + 1
    return point
end

function Control.noteGiveUp()
    Control.metrics.giveUps = Control.metrics.giveUps + 1
end

function Control.qaLine()
    local m = Control.metrics
    return "[ALIFE-QA] FireControl: shots=" .. tostring(m.shots) .. " blockedByVehicle=" .. tostring(m.blockedByVehicle)
        .. " heldFire=" .. tostring(m.heldFire) .. " repositioned=" .. tostring(m.repositioned)
        .. " shotsPerSecPeak=" .. tostring(m.shotsPerSecPeak)
        .. " lineChecks=" .. tostring(m.lineChecks) .. " lineHits=" .. tostring(m.lineHits)
        .. " lineStale=" .. tostring(m.lineStale) .. " laneSearches=" .. tostring(m.laneSearches)
        .. " laneFails=" .. tostring(m.laneFails) .. " giveUps=" .. tostring(m.giveUps)
end

return Control
