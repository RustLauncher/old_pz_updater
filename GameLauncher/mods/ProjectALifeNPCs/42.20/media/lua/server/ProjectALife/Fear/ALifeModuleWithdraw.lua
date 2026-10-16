ProjectALife = ProjectALife or {}

require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Senses/ALifeSight"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Fear/ALifeSurvival"

local Registry = ProjectALife.ModuleRegistry
local Endurance = ProjectALife.Endurance
local Survival = ProjectALife.Survival

local Withdraw = {
    id = "withdraw",
    settings = {

        breakDistance = 18,

        breakStep = 2,

        breakSpread = 1,

        returnDistance = 9,

        holdMs = 4500,

        hurtFraction = 0.30,

        crowdTiles = 4,
        crowdCount = 5,

        pressureHits = 3,
        pressureWindowMs = 6000,

        cooldownMs = 25000,

        legGraceMs = 2500,

        abandonDistance = 3.5,

        maximumRooms = 6,
    },

    plans = {},
    nextAtMs = {},
    metrics = { started = 0, legs = 0, completed = 0, abandoned = 0 },
}
ProjectALife.ModuleWithdraw = Withdraw

local BEARINGS = {
    { 1, 0 }, { 0.7071, 0.7071 }, { 0, 1 }, { -0.7071, 0.7071 },
    { -1, 0 }, { -0.7071, -0.7071 }, { 0, -1 }, { 0.7071, -0.7071 },
}

function Withdraw.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Withdraw.settings[key] ~= nil and tonumber(value) ~= nil then
            Withdraw.settings[key] = tonumber(value)
        end
    end
    return true
end

function Withdraw.reset()
    Withdraw.plans = {}
    Withdraw.nextAtMs = {}
    Withdraw.crowdCache = nil
    Withdraw.metrics = { started = 0, legs = 0, completed = 0, abandoned = 0 }
end

function Withdraw.forgetActor(actorUid)
    Withdraw.plans[actorUid] = nil
    Withdraw.nextAtMs[actorUid] = nil
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
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

local function awayBearing(sx, sy, tx, ty)
    local dx, dy = sx - tx, sy - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return 1 + roll(8) end
    dx, dy = dx / length, dy / length
    local best, bestDot = 1, -2
    for index = 1, #BEARINGS do
        local dot = dx * BEARINGS[index][1] + dy * BEARINGS[index][2]
        if dot > bestDot then best, bestDot = index, dot end
    end
    return best
end

local function wrapBearing(index)

    local wrapped = (index - 1) % 8
    if wrapped < 0 then wrapped = wrapped + 8 end
    return wrapped + 1
end

local function rayOut(cell, sx, sy, z, bearing, distance, step)
    local best
    local reach = step
    while reach <= distance do
        local cx = math.floor(sx + 0.5 + BEARINGS[bearing][1] * reach)
        local cy = math.floor(sy + 0.5 + BEARINGS[bearing][2] * reach)
        local square
        pcall(function() square = cell:getGridSquare(cx, cy, z) end)
        if not standable(square) then break end
        best = { x = cx, y = cy, z = z }
        reach = reach + step
    end
    return best
end
Withdraw.rayOut = rayOut
Withdraw.bearings = BEARINGS

local function roomInside(shell, cell, tx, ty, tz, z)
    local point
    pcall(function()
        local square = shell:getCurrentSquare()
        if square == nil then return end
        local building = square:getBuilding()
        if building == nil then return end
        local definition = building:getDef()
        if definition == nil or definition.getRooms == nil then return end
        local rooms = definition:getRooms()
        if rooms == nil then return end
        local count = math.min(rooms:size(), Withdraw.settings.maximumRooms)
        for index = 0, count - 1 do
            local room = rooms:get(index)
            if room ~= nil then
                local tile
                pcall(function() tile = cell:getFreeTile(room) end)
                if tile ~= nil then
                    local tileX, tileY, tileZ = tile:getX(), tile:getY(), tile:getZ()
                    if math.floor(tileZ) == z
                            and hidden(cell, tx, ty, tz, tileX, tileY, tileZ) then
                        point = { x = tileX + 0.5, y = tileY + 0.5, z = tileZ }
                        return
                    end
                end
            end
        end
    end)
    return point
end

local function underPressure(actor, shell, now)
    local pressed = false
    pcall(function()
        local perception = ProjectALife.Perception
        if perception == nil or type(perception.attackers) ~= "table" then return end

        local record = perception.attackers[actor.uid]
        local live = type(record) == "table"
            and now < (tonumber(record.untilMs) or 0)
        if not live then return end
        local data = shell ~= nil and shell:getModData() or nil
        local hitAt = type(data) == "table"
            and tonumber(data.ProjectALifeLastHitAtMs) or nil
        pressed = hitAt ~= nil
            and now - hitAt <= Withdraw.settings.pressureWindowMs
    end)
    return pressed
end

function Withdraw.ours(body)
    if body.hasModData ~= nil then
        local ok, present = pcall(body.hasModData, body)
        if ok and present == false then return false end
    end
    local ok, data = pcall(body.getModData, body)
    return ok and type(data) == "table"
        and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

function Withdraw.crowdSquare(cell, x, y, z)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or os.time() * 1000
    local cache = Withdraw.crowdCache
    if cache == nil or cache.cell ~= cell or now >= cache.untilMs or now < cache.atMs then
        cache = { cell = cell, atMs = now, untilMs = now + 200, squares = {} }
        Withdraw.crowdCache = cache
    end
    local key = (x * 131072 + y) * 64 + z + 32
    local bodies = cache.squares[key]
    if bodies ~= nil then return bodies end
    bodies = {}
    local square = cell:getGridSquare(x, y, z)
    local movers = square ~= nil and square:getMovingObjects() or nil
    for index = 0, (movers and movers:size() or 0) - 1 do
        local other = movers:get(index)
        if other ~= nil and instanceof(other, "IsoZombie") then bodies[#bodies + 1] = other end
    end
    cache.squares[key] = bodies
    return bodies
end

function Withdraw.countCrowd(shell, tiles, limit)
    local count = 0
    local seen = {}
        local cell = type(getCell) == "function" and getCell() or nil
        if cell == nil then return 0 end
        local sx, sy, sz = math.floor(shell:getX()), math.floor(shell:getY()),
            math.floor(shell:getZ())
        for dx = -tiles, tiles do
            for dy = -tiles, tiles do
                for _, other in ipairs(Withdraw.crowdSquare(cell, sx + dx, sy + dy, sz)) do
                    if other ~= nil and other ~= shell and not seen[other]
                            and other:isDead() ~= true
                            and not Withdraw.ours(other)
                            and math.abs(math.floor(other:getX()) - sx) <= tiles
                            and math.abs(math.floor(other:getY()) - sy) <= tiles
                            and math.floor(other:getZ()) == sz then
                        seen[other] = true
                        count = count + 1
                        if count >= limit then return count end
                    end
                end
            end
        end
    return count
end

local function crowdedBy(shell, tiles, limit)
    local ok, count = pcall(Withdraw.countCrowd, shell, tiles, limit)
    return ok and count or 0
end

function Withdraw.crowdBearings(shell, tiles)
    local bodies = {}
    local seen = {}
    pcall(function()
        local cell = getCell()
        local x, y = shell:getX(), shell:getY()
        local sx, sy, sz = math.floor(x), math.floor(y), math.floor(shell:getZ())
        for dx = -tiles, tiles do
            for dy = -tiles, tiles do
                for _, other in ipairs(Withdraw.crowdSquare(cell, sx + dx, sy + dy, sz)) do
                    if other ~= nil and other ~= shell and not seen[other]
                            and other:isDead() ~= true
                            and not Withdraw.ours(other)
                            and math.abs(math.floor(other:getX()) - sx) <= tiles
                            and math.abs(math.floor(other:getY()) - sy) <= tiles
                            and math.floor(other:getZ()) == sz then
                        seen[other] = true
                        local ox, oy = other:getX() - x, other:getY() - y
                        local squared = math.max(0.25, ox * ox + oy * oy)
                        local length = math.sqrt(squared)
                        bodies[#bodies + 1] = { ox / length, oy / length, 1 / squared }
                    end
                end
            end
        end
    end)
    local order = {}
    for index = 1, #BEARINGS do
        local ahead, net = 0, 0
        for _, body in ipairs(bodies) do
            local pull = (BEARINGS[index][1] * body[1] + BEARINGS[index][2] * body[2]) * body[3]
            net = net + pull
            if pull > 0 then ahead = ahead + pull end
        end

        order[index] = { index = index, ahead = math.floor(ahead * 1000 + 0.5),
            net = math.floor(net * 1000 + 0.5) }
    end
    table.sort(order, function(a, b)
        if a.ahead ~= b.ahead then return a.ahead < b.ahead end
        if a.net ~= b.net then return a.net < b.net end
        return a.index < b.index
    end)
    local result = {}
    for index = 1, #order do result[index] = order[index].index end
    return result
end

function Withdraw.crowdLimit(actor)
    local base = Withdraw.settings.crowdCount
    local crew = ProjectALife.MeleeCrew
    if crew ~= nil and type(crew.crowdLimit) == "function" then return crew.crowdLimit(actor, base) end
    return base
end

function Withdraw.tired(actor, shell, context, now)
    local tired = Endurance.value(actor, shell, now) <= Endurance.settings.retreatThreshold
    local resistance = ProjectALife.Resistance
    if tired and resistance ~= nil and type(context) == "table" and context.target ~= nil then
        return resistance.tired(actor, shell, context.target, resistance.kindOf(context.target), now, true)
    end
    return tired
end

local function trigger(actor, shell, context, now)

    local limit = Withdraw.crowdLimit(actor)
    local crowd = crowdedBy(shell, Withdraw.settings.crowdTiles, limit)
    if crowd >= limit then
        local crew = ProjectALife.MeleeCrew
        if crew ~= nil and limit < Withdraw.settings.crowdCount then crew.noteCaution() end
        return "withdraw_outnumbered"
    end
    if Withdraw.tired(actor, shell, context, now) then
        return "withdraw_exhausted"
    end
    if context.hurt == true then
        local fraction = 1
        pcall(function()
            local maximum = ProjectALife.ShellSimulation.maximumFor(shell)
            if maximum > 0 then fraction = ProjectALife.ShellSimulation.trueHealth(shell) / maximum end
        end)
        if fraction <= Withdraw.settings.hurtFraction then return "withdraw_hurt" end
    end

    if context.reloading == true and context.threatIsGunman == true then
        local cover = ProjectALife.ModuleCover
        local near = cover ~= nil
            and cover.find(shell, context.target, { range = context.range }) or nil
        if near == nil then return "withdraw_reload" end
    end
    if context.threatIsGunman == true and underPressure(actor, shell, now) then
        return "withdraw_pressure"
    end
    return nil
end

local function nextLeg(actor, shell, context, plan, now)
    local cell
    local ok, sx, sy, z, tx, ty, tz = pcall(function()
        cell = getCell()
        local target = context.target
        return math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()),
            math.floor(target:getX()), math.floor(target:getY()), math.floor(target:getZ())
    end)
    if not ok or cell == nil or LosUtil == nil then return nil end

    if plan.stage == "break" then
        local bearing, point
        if plan.reason == "withdraw_outnumbered" then

            local reach = 0
            for _, index in ipairs(Withdraw.crowdBearings(shell, Withdraw.settings.crowdTiles)) do
                local found = rayOut(cell, sx, sy, z, index, Withdraw.settings.breakDistance,
                    Withdraw.settings.breakStep)
                local length = found ~= nil and (found.x - sx) ^ 2 + (found.y - sy) ^ 2 or 0
                if length > reach then bearing, point, reach = index, found, length end
                if reach >= (Withdraw.settings.breakDistance / 2) ^ 2 then break end
            end
        else

            local base = awayBearing(sx, sy, tx, ty)
            local spread = Withdraw.settings.breakSpread
            bearing = wrapBearing(base + roll(spread * 2 + 1) - spread)
            point = rayOut(cell, sx, sy, z, bearing, Withdraw.settings.breakDistance,
                Withdraw.settings.breakStep)
        end
        if plan.reason ~= "withdraw_outnumbered" and context.threatIsGunman == true then
            point = ProjectALife.FireManeuver.find(shell,context.target,
                {mode="retreat",distance=Withdraw.settings.breakDistance}) or point
            if point ~= nil and point.toSelf ~= nil then point.x,point.y=point.x-0.5,point.y-0.5 end
        end
        if point == nil then return nil end
        plan.bearing = bearing

        plan.stage = not plan.disengage and context.ranged == true and "hole" or "done"
        return { x = point.x + 0.5, y = point.y + 0.5, z = point.z,
                 pace = plan.disengage and not Endurance.canSprint(actor, shell, now) and "walk" or "run",
                 disengage = plan.disengage, reason = plan.reason .. "_break" }
    end

    if plan.stage == "hole" then
        plan.stage = "return"

        local point = roomInside(shell, cell, tx, ty, tz, z)
        if point == nil then
            local cover = ProjectALife.ModuleCover
            if cover ~= nil then
                local found = cover.find(shell, context.target, { away = true })
                if found ~= nil then point = found end
            end
        end
        if point == nil then return nil end

        return { x = point.x, y = point.y, z = point.z, pace = "walk",
                 reason = plan.reason .. "_hole", holdMs = Withdraw.settings.holdMs }
    end

    if plan.stage == "return" then
        plan.stage = "done"

        local swing = roll(2) == 0 and 3 or -3
        local bearing = wrapBearing((plan.bearing or 1) + swing)
        local distance = Withdraw.settings.returnDistance
        local cx = math.floor(tx + 0.5 + BEARINGS[bearing][1] * distance)
        local cy = math.floor(ty + 0.5 + BEARINGS[bearing][2] * distance)
        local square
        pcall(function() square = cell:getGridSquare(cx, cy, z) end)
        if not standable(square) then return nil end
        return { x = cx + 0.5, y = cy + 0.5, z = z, pace = "run",
                 reason = plan.reason .. "_return" }
    end

    return nil
end

local function evaluate(actor, shell, context)

    if context == nil or context.target == nil then return nil end
    if type(actor) ~= "table" or actor.uid == nil then return nil end
    local now = tonumber(context.now) or 0
    local exhausted = Withdraw.tired(actor, shell, context, now)
    local limit = Withdraw.crowdLimit(actor)
    if context.ranged ~= true
            and crowdedBy(shell, Withdraw.settings.crowdTiles, limit) < limit and not exhausted then
        return nil
    end
    local uid = actor.uid
    local plan = Withdraw.plans[uid]
    local starting = plan == nil
    if plan ~= nil and exhausted then
        Withdraw.plans[uid] = nil
        Survival.beginDisengage(actor, shell, context.target, now, Withdraw.settings.cooldownMs)
        return nil
    end

    local distance = tonumber(context.distance) or 0

    if plan ~= nil and plan.reason ~= "withdraw_outnumbered"
            and distance <= Withdraw.settings.abandonDistance then
        Withdraw.plans[uid] = nil
        Withdraw.metrics.abandoned = Withdraw.metrics.abandoned + 1
        return nil
    end

    if plan ~= nil and now > (plan.untilMs or 0) then
        Withdraw.plans[uid] = nil
        Withdraw.metrics.abandoned = Withdraw.metrics.abandoned + 1
        return nil
    end

    if plan == nil then
        if now < (Withdraw.nextAtMs[uid] or 0) then return nil end
        local reason = trigger(actor, shell, context, now)
        if reason == nil then return nil end
        plan = { stage = "break", reason = reason, startedAtMs = now,
            disengage = exhausted or context.disengage == true }
    elseif type(context.acceptOffer) == "function" then
        plan = { stage = plan.stage, reason = plan.reason, startedAtMs = plan.startedAtMs,
            untilMs = plan.untilMs, bearing = plan.bearing, disengage = plan.disengage }
    end

    local offer = nextLeg(actor, shell, context, plan, now)
    if offer == nil or plan.stage == "done" and offer == nil then
        Withdraw.plans[uid] = nil
        return offer
    end
    if type(context.acceptOffer) == "function"
            and context.acceptOffer(actor, shell, offer, context) ~= true then
        return nil
    end
    Withdraw.plans[uid] = plan
    if offer.disengage == true then
        Survival.beginDisengage(actor, shell, context.target, now, Withdraw.settings.cooldownMs)
    end
    if starting then
        Withdraw.nextAtMs[uid] = now + Withdraw.settings.cooldownMs
        Withdraw.metrics.started = Withdraw.metrics.started + 1
    end

    local legMs = Withdraw.settings.legGraceMs
    pcall(function()
        local dx, dy = offer.x - shell:getX(), offer.y - shell:getY()
        local reach = math.sqrt(dx * dx + dy * dy)

        local rate = offer.pace == "run" and 3.5 or 1.6
        legMs = math.floor(reach / rate * 1000) + Withdraw.settings.legGraceMs
    end)
    offer.legMs = legMs
    offer.holdMs = (tonumber(offer.holdMs) or 0) + legMs
    plan.untilMs = now + legMs + (tonumber(offer.holdMs) or 0)
    Withdraw.metrics.legs = Withdraw.metrics.legs + 1
    if plan.stage == "done" then
        Withdraw.plans[uid] = nil
        Withdraw.metrics.completed = Withdraw.metrics.completed + 1
    end
    return offer
end

Withdraw.evaluate = evaluate

Registry.register({
    id = "withdraw",
    kind = "reaction",
    dispatch = "positioning",
    label = "Withdraw and re-engage",
    summary = "A losing shooter breaks contact, holes up out of sight, then comes back in from another side.",

    defaultEnabled = true,
    evaluate = evaluate,
})

return Withdraw
