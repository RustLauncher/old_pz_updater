require "ProjectALife/Shells/ALifeAIFence"

ProjectALife = ProjectALife or {}

local Guard = ProjectALife.AIFence
local Kit = {
    lights = setmetatable({}, { __mode = "k" }),
    placedAt = setmetatable({}, { __mode = "k" }),
    due = setmetatable({}, { __mode = "k" }),
    settings = {
        everyTicks = 12,
        perSecond = 2,
        maximumLights = 12,
        range = 60,

        nearest = 1.5,
        farthest = 6,
        throw = { walk = 2.5, run = 4, sprint = 5 },
        radius = 9,
        life = 45,
        color = { 1.0, 0.92, 0.70 },
    },

    metrics = { placed = 0, removed = 0, relights = 0, throttled = 0, perSecond = 0, peakPerSecond = 0 },
    window = { atMs = nil, count = 0 },
    tick = 0,
}
ProjectALife.NightKit = Kit

local function isNight()
    local hour
    pcall(function() hour = getGameTime():getHour() end)
    if hour == nil then return false end

    return hour >= 19 or hour < 7
end

function Kit.nowMs()
    local now = 0
    pcall(function() now = getTimestampMs() end)
    return tonumber(now) or 0
end

function Kit.queueLight(cell, light)
    local positions = type(cell.getLamppostPositions) == "function" and cell:getLamppostPositions() or nil
    if positions ~= nil then
        positions:add(light)
        return
    end
    cell:addLamppost(light)
    Kit.metrics.relights = Kit.metrics.relights + 1
end

function Kit.releaseLight(light)
    pcall(function()
        local cell = type(getCell) == "function" and getCell() or nil
        if cell == nil or type(cell.removeLamppost) ~= "function" then return end
        local positions = type(cell.getLamppostPositions) == "function" and cell:getLamppostPositions() or nil
        if positions ~= nil and type(positions.contains) == "function" and not positions:contains(light) then return end
        cell:removeLamppost(light)
        Kit.metrics.relights = Kit.metrics.relights + 1
    end)
end

local function removeLight(shell)
    local light = Kit.lights[shell]
    if light == nil then return end
    Kit.releaseLight(light)
    Kit.lights[shell] = nil
    Kit.placedAt[shell] = nil
    Kit.due[shell] = nil
    Kit.metrics.removed = Kit.metrics.removed + 1
end

local function removeAll()
    for shell in pairs(Kit.lights) do removeLight(shell) end
end

local function carriesLight(shell)
    local carries = false
    pcall(function()
        local data = shell:getModData()
        carries = type(data) == "table" and data.ProjectALifeFlashlight == true
            and not shell:isDead()
    end)
    return carries
end

function Kit.beamPoint(shell)
    local s = Kit.settings
    local x, y = shell:getX(), shell:getY()
    local data = shell:getModData()
    local aimX = type(data) == "table" and tonumber(data.ProjectALifeAimAtX) or nil
    local aimY = type(data) == "table" and tonumber(data.ProjectALifeAimAtY) or nil
    local dx, dy, reach
    if aimX ~= nil and aimY ~= nil then
        dx, dy = aimX - x, aimY - y
        reach = math.max(s.nearest, math.min(s.farthest, math.sqrt(dx * dx + dy * dy)))
    else
        local forward = shell:getForwardDirection()
        dx, dy = forward:getX(), forward:getY()
        local pace = type(data) == "table" and data.ProjectALifePace or nil
        reach = s.throw[pace] or s.throw.walk
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then dx, dy, length = 1, 0, 1 end
    return x + dx / length * reach, y + dy / length * reach
end

function Kit.countPlaced(now)
    local window, metrics = Kit.window, Kit.metrics
    if window.atMs == nil or now < window.atMs or now - window.atMs >= 1000 then
        if window.atMs ~= nil and now >= window.atMs and now - window.atMs < 2000 then
            metrics.perSecond = window.count
        else
            metrics.perSecond = 0
        end
        window.atMs, window.count = now, 0
    end
    window.count = window.count + 1
    if window.count > metrics.peakPerSecond then metrics.peakPerSecond = window.count end
end

function Kit.throttled(shell, now)
    local last = Kit.placedAt[shell]
    local rate = tonumber(Kit.settings.perSecond) or 0
    if last == nil or rate <= 0 or now < last then return false end
    return now - last < 1000 / rate
end

local function placeLight(shell, now)
    if Kit.lights[shell] ~= nil and Kit.throttled(shell, now) then
        if not Kit.due[shell] then Kit.metrics.throttled = Kit.metrics.throttled + 1 end
        Kit.due[shell] = true
        return
    end
    Kit.due[shell] = nil
    removeLight(shell)
    pcall(function()
        local beamX, beamY = Kit.beamPoint(shell)
        local x, y = math.floor(beamX), math.floor(beamY)
        local z = math.floor(shell:getZ())
        local c = Kit.settings.color
        local light = IsoLightSource.new(x, y, z, c[1], c[2], c[3],
            Kit.settings.radius, Kit.settings.life)
        Kit.queueLight(getCell(), light)
        Kit.lights[shell] = light
        Kit.placedAt[shell] = now
        Kit.metrics.placed = Kit.metrics.placed + 1
        Kit.countPlaced(now)
    end)
end

local function nearestCarriers(player)
    local list = {}
    if Guard == nil or type(Guard.owned) ~= "table" then return list end
    local px, py = player:getX(), player:getY()
    local rangeSq = Kit.settings.range * Kit.settings.range
    for shell in pairs(Guard.owned) do
        if carriesLight(shell) then
            local ok, dx, dy = pcall(function() return shell:getX() - px, shell:getY() - py end)
            if ok then
                local d = dx * dx + dy * dy
                if d <= rangeSq then list[#list + 1] = { shell = shell, d = d } end
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

function Kit.placeDue(now)
    for shell in pairs(Kit.due) do
        if Kit.lights[shell] == nil then
            Kit.due[shell] = nil
        elseif not Kit.throttled(shell, now) then
            placeLight(shell, now)
        end
    end
end

local function onTick()
    Kit.tick = Kit.tick + 1
    if Kit.tick % Kit.settings.everyTicks ~= 0 then
        for _ in pairs(Kit.due) do
            Kit.placeDue(Kit.nowMs())
            break
        end
        return
    end
    if not isNight() then
        removeAll()
        return
    end
    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if player == nil then return end
    local carriers = nearestCarriers(player)
    local keep = {}
    local now = Kit.nowMs()
    for index = 1, math.min(#carriers, Kit.settings.maximumLights) do
        local shell = carriers[index].shell
        keep[shell] = true
        placeLight(shell, now)
    end
    for shell in pairs(Kit.lights) do
        if not keep[shell] then removeLight(shell) end
    end
end
Kit.onTick, Kit.removeAll = onTick, removeAll

function Kit.listForQA()
    local window = ALifeDebugSpawnerWindow
    local names = type(window) == "table" and window.clientQANames or nil
    if type(names) ~= "table" then return false end
    for _, name in ipairs(names) do
        if name == "NightKit" then return true end
    end
    names[#names + 1] = "NightKit"
    return true
end

if type(Events) == "table" then
    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
    if Events.OnGameStart ~= nil then
        Events.OnGameStart.Add(removeAll)
        Events.OnGameStart.Add(function() pcall(Kit.listForQA) end)
    end
end

return Kit
