ProjectALife = ProjectALife or {}
require "ProjectALife/World/ALifeSeasons"

local Facts = {
    ttlMs = 1800,
    radius = 7,
    vehicleRadius = 14,
    scanBudget = 4,
    budgetWindowMs = 1000,
    cacheLimit = 96,
    adapters = {},
    cache = {},
    cacheCount = 0,
    spent = 0,
    spentAtMs = 0,
    metrics = { reads = 0, hits = 0, scans = 0, throttled = 0, noShell = 0 },
}
ProjectALife.WorldFacts = Facts

Facts.flagNames = {
    window = { "WindowN", "WindowW", "windowN", "windowW" },
    door = { "doorN", "doorW" },
    fence = { "HoppableN", "HoppableW", "TallHoppableN", "TallHoppableW" },
    fire = { "burning" },
    water = { "water" },
}

function Facts.nowMs()
    if type(Facts.adapters.nowMs) == "function" then return Facts.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Facts.flagLists()
    if Facts.flagCache ~= nil then return Facts.flagCache end
    if type(IsoFlagType) ~= "table" and type(IsoFlagType) ~= "userdata" then return nil end
    local lists = {}
    for tag, names in pairs(Facts.flagNames) do
        local list = {}
        for _, name in ipairs(names) do
            local flag = IsoFlagType[name]
            if flag ~= nil then list[#list + 1] = flag end
        end
        lists[tag] = list
    end
    Facts.flagCache = lists
    return lists
end

function Facts.shellFor(uid)
    if type(Facts.adapters.shell) == "function" then return Facts.adapters.shell(uid) end
    if uid == nil then return nil end
    local watchdog = ProjectALife.Watchdog
    local bound = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    if bound ~= nil then return bound.shell end
    return nil
end

function Facts.weatherTags(tags, now)
    local seasons = ProjectALife.Seasons
    if seasons == nil then return end
    local w = seasons.weather(now)
    if w ~= nil then
        if w.rain > 0.05 then tags.rain = true end
        if w.snowing or w.ground > 0.15 then tags.snow = true end
        if w.fog > 0.2 then tags.fog = true end
        if w.wind > 12 then tags.wind = true end
        if seasons.skyOf(w) == "storm" or w.rain > 0.5 then tags.storm = true end
        if w.air <= 10 then tags.cold = true end
        if w.air >= 26 then tags.hot = true end
    end
    tags[seasons.current()] = true
end

function Facts.vehicleTags(tags, cell, x, y)
    if type(cell.getVehicles) ~= "function" then return end
    local list = cell:getVehicles()
    if list == nil or type(list.toArray) ~= "function" then return end
    local limit = Facts.vehicleRadius * Facts.vehicleRadius
    local near = 0
    for _, vehicle in pairs(list:toArray()) do
        local dx, dy = vehicle:getX() - x, vehicle:getY() - y
        if dx * dx + dy * dy <= limit then near = near + 1 end
    end
    if near >= 1 then tags.vehicle = true end
    if near >= 2 then tags.cars = true end
end

function Facts.squareTags(tags, square, lists, onGrid)
    local props = square:getProperties()
    if props ~= nil and lists ~= nil then
        for tag, list in pairs(lists) do
            if tags[tag] ~= true then
                for index = 1, #list do
                    if props:has(list[index]) then tags[tag] = true; break end
                end
            end
        end
    end
    if tags.building ~= true and square:getBuilding() ~= nil then tags.building = true end
    if tags.trees ~= true and type(square.HasTree) == "function" and square:HasTree() == true then tags.trees = true end
    if tags.stairs ~= true and type(square.HasStairs) == "function" and square:HasStairs() == true then tags.stairs = true end
    if tags.generator ~= true and type(square.getGenerator) == "function" and square:getGenerator() ~= nil then tags.generator = true end
    if tags.road ~= true and onGrid then
        local floor = square:getFloor()
        local sprite = floor ~= nil and floor:getSprite() or nil
        local name = sprite ~= nil and sprite:getName() or nil
        if type(name) == "string" and string.find(name, "blends_street", 1, true) == 1 then tags.road = true end
    end
end

function Facts.scan(shell, now)
    local tags = {}
    Facts.weatherTags(tags, now)
    local square = shell:getCurrentSquare()
    if square == nil then return tags end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local outside = square:isOutside() == true
    if outside then
        if z >= 1 then tags.rooftop = true end
    else
        tags.inside = true
        tags.building = true
    end
    local cell = getCell()
    if cell == nil then return tags end
    Facts.vehicleTags(tags, cell, x, y)
    local lists = Facts.flagLists()
    local radius = Facts.radius
    for dx = -radius, radius do
        for dy = -radius, radius do
            local near = cell:getGridSquare(x + dx, y + dy, z)
            if near ~= nil then
                Facts.squareTags(tags, near, lists, dx % 2 == 0 and dy % 2 == 0)
            end
        end
    end
    return tags
end

function Facts.read(uid)
    Facts.metrics.reads = Facts.metrics.reads + 1
    if uid == nil then return {} end
    local now = Facts.nowMs()
    local entry = Facts.cache[uid]
    if entry ~= nil and now - entry.atMs < Facts.ttlMs then
        Facts.metrics.hits = Facts.metrics.hits + 1
        return entry.tags
    end
    local shell = Facts.shellFor(uid)
    if shell == nil then
        Facts.metrics.noShell = Facts.metrics.noShell + 1
        return entry ~= nil and entry.tags or {}
    end
    if now - Facts.spentAtMs >= Facts.budgetWindowMs then Facts.spentAtMs, Facts.spent = now, 0 end
    if Facts.spent >= Facts.scanBudget then
        Facts.metrics.throttled = Facts.metrics.throttled + 1
        return entry ~= nil and entry.tags or {}
    end
    Facts.spent = Facts.spent + 1
    Facts.metrics.scans = Facts.metrics.scans + 1
    local scan = type(Facts.adapters.scan) == "function" and Facts.adapters.scan or Facts.scan
    local ok, tags = pcall(scan, shell, now)
    if not ok or type(tags) ~= "table" then tags = {} end
    if entry == nil then
        if Facts.cacheCount >= Facts.cacheLimit then Facts.cache, Facts.cacheCount = {}, 0 end
        Facts.cacheCount = Facts.cacheCount + 1
    end
    Facts.cache[uid] = { atMs = now, tags = tags }
    return tags
end

function Facts.reset()
    Facts.cache, Facts.cacheCount, Facts.spent, Facts.spentAtMs = {}, 0, 0, 0
    Facts.metrics = { reads = 0, hits = 0, scans = 0, throttled = 0, noShell = 0 }
end

return Facts
