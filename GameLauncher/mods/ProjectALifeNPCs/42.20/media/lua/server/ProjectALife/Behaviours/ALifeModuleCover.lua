require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Senses/ALifeSight"
require "ProjectALife/Behaviours/ALifeFireManeuver"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Cover = {
    id = "cover",
    settings = {

        radius = 7,
        radiusIndoors = 4,

        ringStep = 1.5,

        maximumRays = 16,

        intervalMs = 1200,

        engagedIntervalMs = 8000,

        hurtFraction = 0.45,

        runBeyond = 3,

        holdMs = 5000,
        hurtHoldMs = 7000,
    },
    nextAtMs = {},
    metrics = { searches = 0, rays = 0, found = 0 },
}
ProjectALife.ModuleCover = Cover

local BEARINGS = {
    { 1, 0 }, { 0.7071, 0.7071 }, { 0, 1 }, { -0.7071, 0.7071 },
    { -1, 0 }, { -0.7071, -0.7071 }, { 0, -1 }, { 0.7071, -0.7071 },
}

function Cover.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Cover.settings[key] ~= nil and tonumber(value) ~= nil then
            Cover.settings[key] = tonumber(value)
        end
    end
    return true
end

Cover.vehicleCacheMs = 500

local function coverNow()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Cover.reset()
    Cover.vehicleCache, Cover.vehicleCacheUntilMs = nil, 0
    Cover.nextAtMs = {}
    Cover.metrics = { searches = 0, rays = 0, found = 0 }
end

local function standable(square)
    if square == nil then return false end
    local ok, free = pcall(function()
        if square:isSolid() == true or square:isSolidTrans() == true then return false end
        return square:isFree(false) == true
    end)
    return ok and free == true
end

local function hidden(cell, tx, ty, tz, cx, cy, cz)
    local sight = ProjectALife.Sight
    return sight ~= nil and sight.hides(sight.between(tx, ty, tz, cx, cy, cz)) == true
end

local function fenceOnly(square, cell, tx, ty, z)
    local only = false
    pcall(function()
        local dx, dy = tx - square:getX(), ty - square:getY()
        local stepX = dx > 0 and 1 or (dx < 0 and -1 or 0)
        local stepY = dy > 0 and 1 or (dy < 0 and -1 or 0)
        local toward = cell:getGridSquare(square:getX() + stepX, square:getY() + stepY, z)
        if toward == nil then return end
        local fence = square:isHoppableTo(toward) == true
        local wall = square:isWallTo(toward) == true
        only = fence and not wall
    end)
    return only
end

function Cover.find(shell, target, options)
    options = options or {}
    if options.mode == "forward" or options.mode == "retreat" then
        return ProjectALife.FireManeuver.find(shell,target,options)
    end
    local cell
    local ok, sx, sy, sz, tx, ty, tz = pcall(function()
        cell = getCell()
        return math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()),
            math.floor(target:getX()), math.floor(target:getY()), math.floor(target:getZ())
    end)
    if not ok or cell == nil or LosUtil == nil then return nil end

    local here = shell.getSquare ~= nil and shell:getSquare() or nil
    local indoors = here ~= nil and here.getRoom ~= nil and here:getRoom() ~= nil
    local radius = indoors and Cover.settings.radiusIndoors or Cover.settings.radius
    local range = tonumber(options.range) or 0
    local awayFromThreat = options.away == true
    local rays, best, bestScore = 0, nil, nil
    Cover.metrics.searches = Cover.metrics.searches + 1

    pcall(function()

        if indoors or sz ~= 0 then return end

        local vehicleList = Cover.vehicleCache
        if vehicleList == nil or coverNow() >= (Cover.vehicleCacheUntilMs or 0) then
            local vehicles = cell:getVehicles()
            if vehicles == nil or vehicles.toArray == nil then return end
            vehicleList = vehicles:toArray()
            Cover.vehicleCache = vehicleList
            Cover.vehicleCacheUntilMs = coverNow() + Cover.vehicleCacheMs
        end
        if vehicleList == nil then return end
        for _, vehicle in pairs(vehicleList) do
            local vx, vy = vehicle:getX(), vehicle:getY()
            local toVehicle = (vx - sx) ^ 2 + (vy - sy) ^ 2
            if toVehicle <= (radius + 4) ^ 2 then
                local dx, dy = vx - tx, vy - ty
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0.001 then
                    dx, dy = dx / length, dy / length
                    local cx = math.floor(vx + dx * 2)
                    local cy = math.floor(vy + dy * 2)
                    local square = cell:getGridSquare(cx, cy, sz)
                    if standable(square) then
                        local toSelf = math.sqrt((cx - sx) ^ 2 + (cy - sy) ^ 2)

                        local score = toSelf - 2.5
                        if awayFromThreat then
                            score = score - math.sqrt((cx - tx) ^ 2 + (cy - ty) ^ 2) * 0.6
                        end
                        if bestScore == nil or score < bestScore then
                            best = { x = cx + 0.5, y = cy + 0.5, z = sz,
                                toThreat = math.sqrt((cx - tx) ^ 2 + (cy - ty) ^ 2),
                                toSelf = toSelf, vehicle = true }
                            bestScore = score
                        end
                    end
                end
            end
        end
    end)
    local ring = Cover.settings.ringStep
    while ring <= radius and rays < Cover.settings.maximumRays do
        for index = 1, #BEARINGS do
            local bearing = BEARINGS[index]
            local cx = math.floor(sx + 0.5 + bearing[1] * ring)
            local cy = math.floor(sy + 0.5 + bearing[2] * ring)
            if not (cx == sx and cy == sy) then
                local square
                pcall(function() square = cell:getGridSquare(cx, cy, sz) end)
                if standable(square) and rays < Cover.settings.maximumRays then
                    rays = rays + 1
                    if hidden(cell, tx, ty, tz, cx, cy, sz)
                            and not fenceOnly(square, cell, tx, ty, sz) then
                        local dxs, dys = cx - sx, cy - sy
                        local dxt, dyt = cx - tx, cy - ty
                        local toSelf = math.sqrt(dxs * dxs + dys * dys)
                        local toThreat = math.sqrt(dxt * dxt + dyt * dyt)

                        local score = toSelf
                        if awayFromThreat then
                            score = score - toThreat * 0.6
                        elseif range > 0 then
                            if toThreat > range then score = score + (toThreat - range) * 2 end
                            if toThreat < 2 then score = score + 4 end
                        end
                        if bestScore == nil or score < bestScore then
                            best = { x = cx + 0.5, y = cy + 0.5, z = sz,
                                     toThreat = toThreat, toSelf = toSelf }
                            bestScore = score
                        end
                    end
                end
            end
        end

        if best ~= nil and not awayFromThreat then break end
        ring = ring + Cover.settings.ringStep
    end
    Cover.metrics.rays = Cover.metrics.rays + rays
    if best ~= nil then Cover.metrics.found = Cover.metrics.found + 1 end
    return best
end

local function evaluate(actor, shell, context)
    if context == nil or context.ranged ~= true or context.target == nil then return nil end
    local now = tonumber(context.now) or 0
    if now < (tonumber(context.coverUntilMs) or 0) then return nil end
    local uid = actor.uid
    if now < (Cover.nextAtMs[uid] or 0) then return nil end

    local forward,waiting = ProjectALife.FireManeuver.offer(actor,shell,context)
    if forward ~= nil then return forward end
    if waiting == "pending" then return {reason="cover_pin_wait"} end
    local reason, away, hold
    if context.reloading == true then

        if now < (Cover.nextAtMs[uid .. ":reload"] or 0) then return nil end
        Cover.nextAtMs[uid .. ":reload"] = now + Cover.settings.engagedIntervalMs
        reason, hold = "cover_reload", Cover.settings.holdMs
    elseif context.hurt == true then
        reason, away, hold = "cover_hurt", true, Cover.settings.hurtHoldMs
    elseif context.threatIsGunman == true and (tonumber(context.distance) or 0) > 4 then

        if now < (Cover.nextAtMs[uid .. ":engaged"] or 0) then return nil end
        Cover.nextAtMs[uid .. ":engaged"] = now + Cover.settings.engagedIntervalMs
        reason, hold = "cover_fire", Cover.settings.holdMs
    else
        return nil
    end
    Cover.nextAtMs[uid] = now + Cover.settings.intervalMs

    local point = Cover.find(shell, context.target, {
        away = away, range = tonumber(context.range) or 0,
    })
    if point == nil then return nil end
    point.reason = reason
    point.holdMs = hold
    point.pace = point.toSelf > Cover.settings.runBeyond and "run" or "walk"
    return point
end

Registry.register({
    id = "cover",
    kind = "craft",
    dispatch = "positioning",
    label = "Use cover",
    summary = "Shooters get out of the line of fire to reload, break contact when hurt, and fight from behind walls.",
    defaultEnabled = true,
    evaluate = evaluate,
})

return Cover
