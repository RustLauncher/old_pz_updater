require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local R = {
    key = "regionLedger",
    settings = { cell = 120, maxCells = 128, scale = 0.25, ceiling = 4, floorKills = 0.25 },
    adapters = {},
    metrics = { deaths = 0, spawns = 0, cooling = 0, regrowing = 0, passed = 0 },
}
ProjectALife.RegionLedger = R

function R.cooldownDays()
    return Gate.number("Population_RespawnCooldownDays", 3, 0, 60)
end

function R.regrowDays()
    return Gate.number("Population_RegrowthDays", 2, 0, 30)
end

function R.enabled()
    return R.cooldownDays() > 0 and Gate.authority()
end

function R.registry()
    return R.adapters.actors or ProjectALife.ActorRegistry
end

function R.finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function R.cellOf(x, y)
    x, y = R.finite(x), R.finite(y)
    if x == nil or y == nil then return nil end
    local size = R.settings.cell
    return tostring(math.floor(x / size)) .. ":" .. tostring(math.floor(y / size))
end

function R.clean(saved)
    local data = { v = 1, cells = {} }
    if type(saved) ~= "table" or type(saved.cells) ~= "table" then return data end
    local count = 0
    for key, row in pairs(saved.cells) do
        if count >= R.settings.maxCells then break end
        if type(key) == "string" and #key <= 32 and type(row) == "table" and R.finite(row.k) and R.finite(row.t) then
            data.cells[key] = { k = math.max(0, R.finite(row.k)), t = R.finite(row.t),
                u = R.finite(row.u) or R.finite(row.t), s = R.finite(row.s) }
            count = count + 1
        end
    end
    return data
end

function R.load()
    local actors = R.registry()
    local epoch = actors ~= nil and actors.worldState or nil
    if R.data ~= nil and R.store == actors and R.epoch == epoch then return R.data end
    R.store, R.epoch = actors, epoch
    local saved = actors ~= nil and type(actors.getWorldValue) == "function" and actors.getWorldValue(R.key) or nil
    R.data = R.clean(saved)
    return R.data
end

function R.save()
    local actors = R.registry()
    if R.data == nil or actors == nil or type(actors.setWorldValue) ~= "function" then return false end
    return actors.setWorldValue(R.key, R.data) == true
end

function R.hours()
    local pressure = ProjectALife.WorldPressure
    if pressure ~= nil and type(pressure.hours) == "function" then return pressure.hours(0) end
    return Gate.worldHours()
end

function R.decayed(row, hours)
    local days = math.max(0.25, R.regrowDays())
    local elapsed = math.max(0, (tonumber(hours) or row.t) - row.t) / 24
    return math.max(0, row.k - elapsed / days)
end

function R.cooldownHours(kills)
    local s = R.settings
    local factor = math.min(s.ceiling, 1 + math.max(0, kills - 1) * s.scale)
    return R.cooldownDays() * 24 * factor
end

function R.prune(data, hours)
    local count, oldest, oldestKey = 0, nil, nil
    for key, row in pairs(data.cells) do
        if R.decayed(row, hours) < R.settings.floorKills and hours >= row.u then
            data.cells[key] = nil
        else
            count = count + 1
            if oldest == nil or row.t < oldest then oldest, oldestKey = row.t, key end
        end
    end
    if count > R.settings.maxCells and oldestKey ~= nil then data.cells[oldestKey] = nil end
end

function R.noteDeaths(x, y, count, hours)
    if not R.enabled() then return false end
    local key = R.cellOf(x, y)
    count = math.floor(tonumber(count) or 0)
    if key == nil or count < 1 then return false end
    hours = R.finite(hours) or R.hours()
    local data = R.load()
    local row = data.cells[key]
    local kills = count
    if row ~= nil then kills = R.decayed(row, hours) + count end
    local until_ = hours + R.cooldownHours(kills)
    if row ~= nil and row.u > until_ then until_ = row.u end
    data.cells[key] = { k = kills, t = hours, u = until_, s = row ~= nil and row.s or nil }
    R.prune(data, hours)
    R.metrics.deaths = R.metrics.deaths + count
    return R.save()
end

function R.blocked(x, y, hours)
    if not R.enabled() then return false end
    local key = R.cellOf(x, y)
    if key == nil then return false end
    local data = R.load()
    local row = data.cells[key]
    if row == nil then return false end
    hours = R.finite(hours) or R.hours()
    if hours < row.u then
        R.metrics.cooling = R.metrics.cooling + 1
        return true, "region_cooldown", row.u
    end
    local gap = R.regrowDays() * 24
    if gap > 0 and R.decayed(row, hours) >= R.settings.floorKills and row.s ~= nil and hours - row.s < gap then
        R.metrics.regrowing = R.metrics.regrowing + 1
        return true, "region_regrowing", row.s + gap
    end
    R.metrics.passed = R.metrics.passed + 1
    return false
end

function R.noteSpawn(x, y, hours)
    if not R.enabled() then return false end
    local key = R.cellOf(x, y)
    if key == nil then return false end
    local data = R.load()
    local row = data.cells[key]
    if row == nil then return false end
    hours = R.finite(hours) or R.hours()
    row.s = hours
    R.metrics.spawns = R.metrics.spawns + 1
    return R.save()
end

function R.summary(hours)
    hours = R.finite(hours) or R.hours()
    local data = R.load()
    local cells, cooling, regrowing = 0, 0, 0
    for _, row in pairs(data.cells) do
        cells = cells + 1
        if hours < row.u then cooling = cooling + 1
        elseif R.decayed(row, hours) >= R.settings.floorKills then regrowing = regrowing + 1 end
    end
    return { cells = cells, cooling = cooling, regrowing = regrowing }
end

function R.reset()
    R.data, R.store, R.epoch = nil, nil, nil
    R.metrics = { deaths = 0, spawns = 0, cooling = 0, regrowing = 0, passed = 0 }
end

function R.qaLine()
    local m = R.metrics
    local ok, summary = pcall(R.summary)
    if not ok then summary = { cells = 0, cooling = 0, regrowing = 0 } end
    return "[ALIFE-QA] regionLedger cooldownDays=" .. tostring(R.cooldownDays()) .. " regrowDays=" .. tostring(R.regrowDays())
        .. " cells=" .. tostring(summary.cells) .. " cooling=" .. tostring(summary.cooling)
        .. " regrowing=" .. tostring(summary.regrowing) .. " deaths=" .. tostring(m.deaths)
        .. " spawns=" .. tostring(m.spawns) .. " refusedCooldown=" .. tostring(m.cooling)
        .. " refusedRegrowth=" .. tostring(m.regrowing)
end

return R
