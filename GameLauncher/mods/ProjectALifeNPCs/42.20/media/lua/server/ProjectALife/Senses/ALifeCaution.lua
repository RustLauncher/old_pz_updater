require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Senses/ALifePerception"
require "ProjectALife/Senses/ALifeSneakProfile"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/World/ALifeHeliSearch"
require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Combat/ALifeLineOfFire"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate
local Perception = ProjectALife.Perception

local Caution = {
    id = "caution",
    settings = {
        goalTiles = 7, laneTiles = 2.5, groupLimit = 3, waitMs = 3500, waitLimit = 4,
        detourTiles = 7, detourLimit = 2, memoryMs = 60000, scanMs = 500, watchMs = 700,
        visibleChecks = 6, hearTiles = 6, siteTiles = 9, siteScanTiles = 30, shortLeg = 5,
        backoffTiles = 9, backoffStep = 8, sneakBlockMs = 8000, sneakSlotMs = 60000,
        sneakNearPercent = 70, sneakLegMs = 25000, hostileTiles = 26, hostileChecks = 4,
        idleSeenTiles = 20, idleHeardTiles = 8, idleChecks = 4, idleHitMs = 6000, idleNoiseMs = 5000,
        idleCacheMs = 400, fishNoticeTiles = 12, playerViewDegrees = 100,
        lightDetourTiles = 8, lightDetourLimit = 2, lightWaitLimit = 4, lightWaitMs = 2500,
        lightNearTiles = 14, heatRows = 128, heatMarks = 32, heatTiles = 24, heatAgeMs = 10000,
    },
    idleMemo = setmetatable({}, { __mode = "k" }),
    intents = { patrol = true, roam = true, scavenge = true, collect_supplies = true, travel = true, regroup = true },
    sneakIntents = { patrol = true, roam = true, scavenge = true, collect_supplies = true, travel = true },
    marks = {},
    markCount = 0,
    metrics = { waits = 0, detours = 0, skipped = 0, backoffs = 0, sneaks = 0, sneakStops = 0, sites = 0 },
}
ProjectALife.Caution = Caution

function Caution.active()
    return Gate.on(Caution.id, "Caution_Enabled", true)
end

Caution.modeId = "zombieAvoid"

function Caution.zombieMode(actor)
    local registry = ProjectALife.ModuleRegistry
    if registry == nil or type(actor) ~= "table" or registry.modules[Caution.modeId] == nil
            or not registry.isEnabled(Caution.modeId) then return "default" end
    local authored = registry.override(actor, Caution.modeId)
    if authored == "off" then return "fight" end
    if authored == "on" then return "avoid" end
    return "default"
end

function Caution.avoidTiles()
    return Gate.number("Caution_AvoidTiles", 12, 4, 30)
end

function Caution.isActor(body)
    local data = Perception.dataOf(body)
    return data ~= nil and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

function Caution.bodies(now)
    return Perception.snapshotFor(now).bodies
end

function Caution.positionOf(body)
    if body == nil or type(body.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return body:getX(), body:getY(), body:getZ() end)
    if not ok then return nil end
    return x, y, z
end

function Caution.markFor(uid, now)
    local mark = Caution.marks[uid]
    if mark ~= nil and now - (mark.atMs or 0) > Caution.settings.memoryMs then mark = nil end
    if mark == nil then
        if Caution.markCount > 256 then
            Caution.marks, Caution.markCount = {}, 0
        end
        mark = { waits = 0, detours = 0, atMs = now }
        if Caution.marks[uid] == nil then Caution.markCount = Caution.markCount + 1 end
        Caution.marks[uid] = mark
    end
    return mark
end

function Caution.assess(shell, goal, now)
    local sx, sy, sz = Caution.positionOf(shell)
    local result = { atGoal = 0, onRoute = 0, nearest = math.huge, side = 0, ax = nil, ay = nil, along = 0 }
    if sx == nil then return result end
    local settings = Caution.settings
    local gx, gy, gz = tonumber(goal.x), tonumber(goal.y), tonumber(goal.z) or sz
    local dx, dy = gx - sx, gy - sy
    local length = math.sqrt(dx * dx + dy * dy)
    local reach = Caution.avoidTiles()
    local rows = Caution.bodies(now)
    local hear2 = settings.hearTiles * settings.hearTiles
    local scan2 = settings.siteScanTiles * settings.siteScanTiles
    local goal2 = settings.goalTiles * settings.goalTiles
    local checks = 0
    for index = 1, #rows do
        local row = rows[index]
        local rx, ry, rz = row.x, row.y, row.z
        local shellFlat = (rx - sx) ^ 2 + (ry - sy) ^ 2
        if shellFlat < result.nearest and math.abs(rz - sz) < 1.5 then result.nearest = shellFlat end
        if math.abs(rz - gz) < 1.5 and (rx - gx) ^ 2 + (ry - gy) ^ 2 <= goal2 and shellFlat <= scan2 then
            result.atGoal = result.atGoal + 1
        end
        if length > 1 and math.abs(rz - sz) < 1.5 then
            local along = ((rx - sx) * dx + (ry - sy) * dy) / length
            if along > 0 and along <= math.min(length + 1, reach) then
                local lateral = ((rx - sx) * -dy + (ry - sy) * dx) / length
                if math.abs(lateral) <= settings.laneTiles then
                    local known = shellFlat <= hear2
                    if not known and checks < settings.visibleChecks then
                        checks = checks + 1
                        known = Perception.visible(shell, row.body) == true
                    end
                    if known then
                        result.onRoute = result.onRoute + 1
                        if result.ax == nil or along < result.along then
                            result.ax, result.ay, result.along = rx, ry, along
                            result.side = lateral >= 0 and 1 or -1
                        end
                    end
                end
            end
        end
    end
    result.nearest = math.sqrt(result.nearest)
    return result
end

function Caution.clean(assessed)
    return assessed.atGoal == 0 and assessed.onRoute == 0
end

function Caution.rotated(shell, goal, degrees)
    local sx, sy = Caution.positionOf(shell)
    if sx == nil then return nil end
    local dx, dy = goal.x - sx, goal.y - sy
    local angle = math.rad(degrees)
    local cs, sn = math.cos(angle), math.sin(angle)
    return { x = sx + dx * cs - dy * sn, y = sy + dx * sn + dy * cs, z = goal.z }
end

function Caution.alternative(shell, goal, now)
    local angles = { 50, -50, 100, -100, 150, -150 }
    for index = 1, #angles do
        local alt = Caution.rotated(shell, goal, angles[index])
        if alt ~= nil and Caution.clean(Caution.assess(shell, alt, now)) then return alt end
    end
    return nil
end

function Caution.sidestep(shell, goal, assessed, now)
    local sx, sy = Caution.positionOf(shell)
    if sx == nil or assessed.ax == nil then return nil end
    local dx, dy = goal.x - sx, goal.y - sy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return nil end
    local ux, uy = dx / length, dy / length
    local nx, ny = -uy, ux
    local along = math.min(length, assessed.along + 2)
    for _, sign in ipairs({ -assessed.side, assessed.side }) do
        local waypoint = {
            x = sx + ux * along + nx * sign * Caution.settings.detourTiles,
            y = sy + uy * along + ny * sign * Caution.settings.detourTiles,
            z = goal.z,
        }
        if Caution.clean(Caution.assess(shell, waypoint, now)) then return waypoint end
    end
    return nil
end

function Caution.backoff(shell, assessed, now)
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil or assessed.ax == nil then return nil end
    local dx, dy = sx - assessed.ax, sy - assessed.ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    local step = Caution.settings.backoffStep
    local point = { x = sx + dx / length * step, y = sy + dy / length * step, z = sz }
    if Caution.clean(Caution.assess(shell, point, now)) then return point end
    return nil
end

function Caution.takeHeatRay(now)
    local window = Caution.heatRayWindow
    if window == nil or now < window.atMs or now - window.atMs >= 1000 then
        window = { atMs = now, count = 0 }
        Caution.heatRayWindow = window
    end
    local maximum = math.floor(Gate.number("Caution_DangerRaysPerSecond", 32, 0, 120))
    Caution.metrics.heatRaysSecond = window.count
    if window.count >= maximum then
        Caution.metrics.heatRayCapped = (Caution.metrics.heatRayCapped or 0) + 1
        return false
    end
    window.count = window.count + 1
    Caution.metrics.heatRaysSecond = window.count
    Caution.metrics.heatRays = (Caution.metrics.heatRays or 0) + 1
    return true
end

function Caution.heatRay(sx, sy, sz, point, now)
    local sight = ProjectALife.Sight
    if sight == nil or type(sight.between) ~= "function" then return nil end
    if not Caution.takeHeatRay(now) then return nil, "budget" end
    return sight.between(sx, sy, sz, point.x, point.y, point.z)
end

function Caution.contactAddressed(actor, row)
    local group = type(actor) == "table" and type(actor.memory) == "table" and actor.memory.groupId or nil
    return group ~= nil and row.group == group
        and (type(row.consumed) ~= "table" or row.consumed[actor.uid] ~= true)
end

function Caution.noiseDanger(row, actor, sx, sy, sz, now)
    if type(row) ~= "table" or tonumber(row.x) == nil or tonumber(row.y) == nil then return false end
    local radius = tonumber(row.radiusSquared) or 0
    local atMs = tonumber(row.atMs) or -1
    return (row.kind == "gunfire" or row.kind == "contact" or row.kind == "noise" and radius >= 900)
        and (row.kind ~= "contact" or Caution.contactAddressed(actor, row))
        and now >= atMs and now - atMs <= Caution.settings.heatAgeMs
        and now < (tonumber(row.untilMs) or -1)
        and math.abs((tonumber(row.z) or 0) - sz) < 0.5
        and (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= radius
end

function Caution.noiseHeard(actor, shell, row, sx, sy, sz, now)
    if not Caution.noiseDanger(row, actor, sx, sy, sz, now) then return false end
    if row.kind == "contact" then return true end
    if row.source == shell or not Gate.flag("Hearing_Enabled", true) then return false end
    local investigation = ProjectALife.Investigation
    if investigation ~= nil and type(investigation.hearingOn) == "function" and not investigation.hearingOn() then return false end
    if investigation == nil or type(investigation.audible) ~= "function" then return true end
    if not Caution.takeHeatRay(now) then return false, "budget" end
    local ok, radius = pcall(investigation.audible, shell, row)
    radius = ok and tonumber(radius) or nil
    if radius == nil then return false end
    return (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= radius * radius
end

function Caution.listeningNoise(actor, shell, now)
    if not Caution.active() or not Gate.flag("Caution_DangerRouting", true) then return false end
    local sx, sy, sz = Caution.positionOf(shell)
    local investigation = ProjectALife.Investigation
    local rows = investigation ~= nil and investigation.marks or nil
    if sx == nil or type(rows) ~= "table" then return false end
    for index = #rows, math.max(1, #rows - Caution.settings.heatMarks + 1), -1 do
        if Caution.noiseHeard(actor, shell, rows[index], sx, sy, sz, now) then return true end
    end
    return false
end

function Caution.squareHazard(square)
    if square == nil then return nil end
    if IsoFlagType ~= nil and IsoFlagType.burning ~= nil and type(square.has) == "function"
            and square:has(IsoFlagType.burning) == true then return "fire" end
    if type(square.hasLitCampfire) == "function" and square:hasLitCampfire() == true then return "campfire" end
    local campfires = ProjectALife.Campfires
    if campfires ~= nil and type(campfires.litSquare) == "function" and campfires.litSquare(square) then return "campfire" end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.landingWater) == "function"
            and traversal.landingWater(square) then return "water" end
    return nil
end

function Caution.legHazard(shell, target)
    if not Caution.active() or not Gate.flag("Caution_HazardCheck", true) then return nil end
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil or type(target) ~= "table" or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local z = math.floor(tonumber(target.z) or sz)
    local hazard = Caution.squareHazard(cell:getGridSquare(math.floor(target.x), math.floor(target.y), z))
    if hazard == nil and math.floor(sz) == z then
        local _, found = ProjectALife.LineOfFire.cells(sx, sy, target.x, target.y, 64, function(x, y, nx, ny)
            return Caution.squareHazard(cell:getGridSquare(nx, ny, z))
        end)
        hazard = found
    end
    if hazard ~= nil then Caution.metrics.legHazards = (Caution.metrics.legHazards or 0) + 1 end
    return hazard
end

function Caution.heatOnSegment(points, sx, sy, goal)
    local dx, dy = goal.x - sx, goal.y - sy
    local length2 = dx * dx + dy * dy
    local heat, nearest, along = 0, nil, math.huge
    if length2 < 0.01 then return heat end
    for index = 1, #points do
        local point = points[index]
        local t = ((point.x - sx) * dx + (point.y - sy) * dy) / length2
        if t > 0 and t <= 1 and (point.x - sx - t * dx) ^ 2 + (point.y - sy - t * dy) ^ 2 <= point.radius ^ 2 then
            heat = heat + point.weight
            if t < along then nearest, along = point, t end
        end
    end
    return heat, nearest, along
end

function Caution.heatPoints(actor, shell, goal, now)
    local sx, sy, sz = Caution.positionOf(shell)
    local points, capped = {}, false
    local rows = Caution.bodies(now)
    local count = math.min(#rows, Caution.settings.heatRows)
    local cursor = Caution.heatCursor or 0
    for offset = 1, count do
        local row = rows[(cursor + offset - 1) % #rows + 1]
        local body = row.body
        local x, y, z = row.x, row.y, row.z
        if x ~= nil and not Caution.isActor(body) and math.abs(z - sz) < 0.5
                and (x - sx) ^ 2 + (y - sy) ^ 2 <= Caution.settings.heatTiles ^ 2 then
            local point = { x = x, y = y, z = z, radius = 4, weight = 1 }
            if Caution.heatOnSegment({ point }, sx, sy, goal) > 0 then
                local known = (x - sx) ^ 2 + (y - sy) ^ 2 <= Caution.settings.hearTiles ^ 2
                if not known then
                    local answer, reason = Caution.heatRay(sx, sy, sz, point, now)
                    known = answer == "clear"
                    capped = capped or reason == "budget"
                end
                if known then points[#points + 1] = point end
            end
        end
    end
    Caution.heatCursor = #rows > 0 and (cursor + count) % #rows or 0
    Caution.metrics.heatSamples = (Caution.metrics.heatSamples or 0) + count
    local investigation = ProjectALife.Investigation
    rows = investigation ~= nil and investigation.marks or nil
    if type(rows) == "table" then
        for index = #rows, math.max(1, #rows - Caution.settings.heatMarks + 1), -1 do
            local row = rows[index]
            if Caution.noiseDanger(row, actor, sx, sy, sz, now) then
                local heard, reason = Caution.noiseHeard(actor, shell, row, sx, sy, sz, now)
                capped = capped or reason == "budget"
                if heard then
                    points[#points + 1] = { x = row.x, y = row.y, z = sz, radius = 6, weight = 3 }
                end
            end
        end
    end
    return points, capped
end

function Caution.heatWaypoint(shell, goal, points, hot, along, now)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local sx, sy, sz = Caution.positionOf(shell)
    local dx, dy = goal.x - sx, goal.y - sy
    local length = math.sqrt(dx * dx + dy * dy)
    local reach = math.min(14, length - 1, along * length + 3)
    local side = math.min(14, math.max(Caution.settings.detourTiles, hot.radius * 2))
    for _, sign in ipairs({ 1, -1 }) do
        local point = { x = sx + dx / length * reach - dy / length * side * sign,
            y = sy + dy / length * reach + dx / length * side * sign, z = sz }
        local square = cell:getGridSquare(math.floor(point.x), math.floor(point.y), math.floor(sz))
        if square ~= nil and type(square.isFree) == "function" and type(square.TreatAsSolidFloor) == "function" then
            if not (Caution.heatOnSegment(points, sx, sy, point) >= 3
                    or square:isFree(false) ~= true or square:TreatAsSolidFloor() ~= true
                    or Caution.legHazard(shell, point) ~= nil) then
                if Caution.heatRay(sx, sy, sz, point, now) == "clear" then return point end
            end
        end
    end
    return nil
end

function Caution.heatVerdict(actor, shell, goal, now, mark)
    if not Gate.flag("Caution_DangerRouting", true) then return nil end
    local sx, sy = Caution.positionOf(shell)
    local points, capped = Caution.heatPoints(actor, shell, goal, now)
    local heat, hot, along = Caution.heatOnSegment(points, sx, sy, goal)
    if heat < 3 and not capped then return nil end
    local point = heat >= 3 and mark.detours < Caution.settings.detourLimit
        and Caution.heatWaypoint(shell, goal, points, hot, along, now) or nil
    mark.atMs = now
    if point ~= nil then
        mark.detours = mark.detours + 1
        Caution.metrics.detours = Caution.metrics.detours + 1
        Caution.metrics.heatDetours = (Caution.metrics.heatDetours or 0) + 1
        return "detour", point
    end
    if capped then Caution.metrics.heatBudgetHolds = (Caution.metrics.heatBudgetHolds or 0) + 1 end
    if mark.waits < Caution.settings.waitLimit then
        mark.waits = mark.waits + 1
        Caution.metrics.waits = Caution.metrics.waits + 1
        return "wait", nil, Caution.settings.waitMs
    end
    mark.waits, mark.detours = 0, 0
    Caution.metrics.skipped = Caution.metrics.skipped + 1
    return "skip"
end

function Caution.decide(actor, shell, goal, now, mark, midRoute)
    local settings = Caution.settings
    local sx, sy = Caution.positionOf(shell)
    if sx == nil or (goal.x - sx) ^ 2 + (goal.y - sy) ^ 2 < settings.shortLeg * settings.shortLeg then
        return "go"
    end
    local mode = Caution.zombieMode(actor)
    if mode == "fight" then return "go" end
    local heat, waypoint, hold = Caution.heatVerdict(actor, shell, goal, now, mark)
    if heat ~= nil then return heat, waypoint, hold end
    local assessed = Caution.assess(shell, goal, now)
    if Caution.clean(assessed) then
        mark.waits = 0
        return "go"
    end
    mark.atMs = now
    local limit = mode == "avoid" and 1 or settings.groupLimit
    local crowd = assessed.atGoal >= limit or assessed.onRoute >= limit
    if crowd then
        if midRoute and assessed.onRoute >= settings.groupLimit and assessed.nearest <= settings.backoffTiles
                and mark.detours < settings.detourLimit then
            local away = Caution.backoff(shell, assessed, now)
            if away ~= nil then
                mark.detours = mark.detours + 1
                Caution.metrics.backoffs = Caution.metrics.backoffs + 1
                return "detour", away
            end
        end
        local alt = mark.detours < settings.detourLimit and Caution.alternative(shell, goal, now) or nil
        if alt ~= nil then
            mark.detours = mark.detours + 1
            Caution.metrics.detours = Caution.metrics.detours + 1
            return "detour", alt
        end
        if mark.waits < settings.waitLimit then
            mark.waits = mark.waits + 1
            Caution.metrics.waits = Caution.metrics.waits + 1
            return "wait", nil, settings.waitMs
        end
        mark.waits, mark.detours = 0, 0
        mark.skips = (mark.skips or 0) + 1
        if mark.skips >= 3 then
            mark.skips = 0
            return "go"
        end
        Caution.metrics.skipped = Caution.metrics.skipped + 1
        return "skip"
    end
    if assessed.onRoute > 0 and mark.detours < settings.detourLimit then
        local waypoint = Caution.sidestep(shell, goal, assessed, now)
        if waypoint ~= nil then
            mark.detours = mark.detours + 1
            Caution.metrics.detours = Caution.metrics.detours + 1
            return "detour", waypoint
        end
    end
    if assessed.atGoal > 0 and mark.waits < settings.waitLimit then
        mark.waits = mark.waits + 1
        Caution.metrics.waits = Caution.metrics.waits + 1
        return "wait", nil, settings.waitMs
    end
    return "go"
end

function Caution.review(actor, shell, goal, intent, options)
    if Caution.intents[intent] ~= true or type(options) ~= "table" or options.cautionSkip == true then
        return "go"
    end
    if options.pace == "run" or options.pace == "sprint" then return "go" end
    if type(goal) ~= "table" or tonumber(goal.x) == nil or tonumber(goal.y) == nil then return "go" end
    if type(actor) ~= "table" or actor.uid == nil or not Caution.active() then return "go" end
    local now = Gate.nowMs()
    local mark = Caution.markFor(actor.uid, now)
    local ok, verdict, newGoal, hold = pcall(Caution.decide, actor, shell, goal, now, mark, false)
    if not ok then return "go" end
    return verdict, newGoal, hold
end

function Caution.watch(actor, shell, state, now)
    if type(state) ~= "table" or state.cautionSkip == true or Caution.intents[state.intent] ~= true then return nil end
    if state.action ~= nil and (state.action.pace == "run" or state.action.pace == "sprint") then return nil end
    if type(actor) ~= "table" or actor.uid == nil or not Caution.active() then return nil end
    local mark = Caution.markFor(actor.uid, now)
    if now < (mark.watchAt or 0) then return nil end
    mark.watchAt = now + Caution.settings.watchMs
    local lit, litGoal, litHold = Caution.beamVerdict(actor, shell, mark, now)
    if lit ~= nil then return lit, litGoal, litHold end
    local goal = type(state.action) == "table" and state.action.target or nil
    if type(goal) ~= "table" or tonumber(goal.x) == nil or tonumber(goal.y) == nil then return nil end
    local ok, verdict, newGoal, hold = pcall(Caution.decide, actor, shell, goal, now, mark, true)
    if not ok or verdict == "go" then return nil end
    if verdict == "skip" then return "wait", nil, Caution.settings.waitMs end
    return verdict, newGoal, hold
end

function Caution.siteClear(shell, square, now)
    if not Caution.active() or square == nil then return true end
    local ok, x, y = pcall(function() return square:getX(), square:getY() end)
    if not ok then return true end
    now = now or Gate.nowMs()
    local sx, sy = Caution.positionOf(shell)
    local settings = Caution.settings
    local rows = Caution.bodies(now)
    local near, site2, scan2 = 0, settings.siteTiles * settings.siteTiles, settings.siteScanTiles * settings.siteScanTiles
    for index = 1, #rows do
        local row = rows[index]
        if (row.x - x) ^ 2 + (row.y - y) ^ 2 <= site2 and (sx == nil or (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= scan2) then
            near = near + 1
            if near >= 2 then
                Caution.metrics.sites = Caution.metrics.sites + 1
                return false
            end
        end
    end
    return true
end

function Caution.beamOver(actor, shell, margin)
    local heli = ProjectALife.HeliSearch
    if heli == nil or type(heli.litAt) ~= "function" then return nil end
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil then return nil end
    local flight, distance = heli.litAt(sx, sy, sz, actor, margin)
    if flight == nil then return nil end
    local outside = false
    pcall(function()
        local square = shell:getSquare()
        outside = square ~= nil and square:isOutside() == true
    end)
    if not outside then return nil end
    return flight, distance, sx, sy, sz
end

function Caution.beamVerdict(actor, shell, mark, now)
    local settings = Caution.settings
    local heli = ProjectALife.HeliSearch
    local flight, distance, sx, sy, sz = Caution.beamOver(actor, shell, 0)
    if flight ~= nil then
        if (mark.lights or 0) >= settings.lightDetourLimit then return nil end
        local dx, dy = sx - flight.x, sy - flight.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.5 then dx, dy, length = 1, 0, 1 end
        local out = math.max(settings.lightDetourTiles, heli.beamRadius(flight) - distance + 5)
        mark.lights = (mark.lights or 0) + 1
        mark.atMs = now
        heli.metrics.reactions = heli.metrics.reactions + 1
        return "detour", { x = sx + dx / length * out, y = sy + dy / length * out, z = sz }
    end
    local near = Caution.beamOver(actor, shell, settings.lightNearTiles)
    if near ~= nil and (mark.lightWaits or 0) < settings.lightWaitLimit then
        mark.lightWaits = (mark.lightWaits or 0) + 1
        mark.atMs = now
        heli.metrics.reactions = heli.metrics.reactions + 1
        return "wait", nil, settings.lightWaitMs
    end
    return nil
end

function Caution.hash(text)
    local seed = 0
    text = tostring(text or "")
    for index = 1, #text do seed = (seed * 31 + string.byte(text, index)) % 2147483647 end
    return seed
end

function Caution.zombiesNear(shell, now, tiles)
    local sx, sy = Caution.positionOf(shell)
    if sx == nil then return false end
    local rows = Caution.bodies(now)
    local limit = tiles * tiles
    for index = 1, #rows do
        if (rows[index].x - sx) ^ 2 + (rows[index].y - sy) ^ 2 <= limit then return true end
    end
    return false
end

function Caution.playerWatching(actor, shell)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.players) ~= "function" then return false end
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil then return false end
    local list = policy.players()
    for index = 1, #list do
        local player = list[index]
        local px, py, pz = Caution.positionOf(player)
        if px ~= nil and policy.ask(player, "isDead") ~= true and math.abs(pz - sz) < 3 then
            local distance = math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2)
            if distance <= Perception.sightTiles
                    and Perception.inView(shell, player, Perception.fieldOfViewFor(shell))
                    and Perception.playerInSightRange(actor, player, distance) then
                return true
            end
        end
    end
    return false
end

function Caution.hostileWatching(actor, shell, now)
    local snapshot = Perception.zombieSnapshot
    local relations = ProjectALife.Relations
    local policy = ProjectALife.DoorPolicy
    if type(snapshot) ~= "table" or type(snapshot.actors) ~= "table" or relations == nil
            or now - (tonumber(snapshot.atMs) or -1e12) > 2000
            or type(relations.hostile) ~= "function" or policy == nil then
        return false
    end
    local sx, sy = Caution.positionOf(shell)
    if sx == nil then return false end
    local settings = Caution.settings
    local limit, checks = settings.hostileTiles * settings.hostileTiles, 0
    for index = 1, #snapshot.actors do
        local row = snapshot.actors[index]
        if row.body ~= shell and (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= limit and checks < settings.hostileChecks then
            local other = policy.actorOf(row.body)
            if other ~= nil and other.uid ~= actor.uid then
                checks = checks + 1
                if relations.hostile(actor, other) == true and Perception.visible(shell, row.body) == true then
                    return true
                end
            end
        end
    end
    return false
end

function Caution.dataOf(shell)
    return Perception.dataOf(shell)
end

function Caution.sneakRoll(actor, shell, intent, options, now)
    local profile = ProjectALife.SneakProfile
    if type(actor) ~= "table" or actor.uid == nil or type(options) ~= "table" then return false end
    local data = Caution.dataOf(shell)
    if data == nil then return false end
    if profile == nil or not profile.enabled() or Caution.sneakIntents[intent] ~= true
            or options.pace == "run" or options.pace == "sprint" then
        data.ProjectALifeSneakWant = nil
        return false
    end
    if now < (tonumber(data.ProjectALifeSneakBlockUntilMs) or 0) then
        data.ProjectALifeSneakWant = nil
        return false
    end
    local settings = Caution.settings
    local percent = profile.frequency()
    if percent > 0 and Caution.listeningNoise(actor, shell, now) then percent = 100 end
    if percent > 0 and percent < settings.sneakNearPercent and Caution.zombiesNear(shell, now, Caution.avoidTiles()) then
        percent = settings.sneakNearPercent
    end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local slot = math.floor(now / settings.sneakSlotMs)
    local roll = Caution.hash(tostring(memory.groupId or actor.uid) .. ":" .. tostring(slot)) % 100
    local want = percent > 0 and roll < percent
    if want and (Caution.playerWatching(actor, shell) or Caution.hostileWatching(actor, shell, now)) then
        want = false
    end
    if want then
        if data.ProjectALifeSneakWant ~= true then Caution.metrics.sneaks = Caution.metrics.sneaks + 1 end
        data.ProjectALifeSneakWant = true
        data.ProjectALifeSneakUntilMs = now + (tonumber(options.timeoutMs) or settings.sneakLegMs) + 3000
        options.pace = "walk"
    else
        data.ProjectALifeSneakWant = nil
    end
    return want
end

function Caution.noticed(actor, shell, threat, kind, now)
    local data = Caution.dataOf(shell)
    if data == nil or data.ProjectALifeSneakWant ~= true then return false end
    local seen = threat ~= nil and kind ~= "zombie"
    if not seen then seen = Caution.playerWatching(actor, shell) end
    if not seen then return false end
    data.ProjectALifeSneakWant = nil
    data.ProjectALifeSneakBlockUntilMs = now + Caution.settings.sneakBlockMs
    Caution.metrics.sneakStops = Caution.metrics.sneakStops + 1
    return true
end

function Caution.hostilePlayerSeen(actor, shell)
    local relations = ProjectALife.Relations
    local policy = ProjectALife.DoorPolicy
    if actor == nil or relations == nil or type(relations.playerStance) ~= "function"
            or policy == nil or type(policy.players) ~= "function" then return nil end
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil then return nil end
    local list = policy.players()
    for index = 1, #list do
        local player = list[index]
        local px, py, pz = Caution.positionOf(player)
        if px ~= nil and policy.ask(player, "isDead") ~= true and math.abs(pz - sz) < 3 then
            local distance = math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2)
            if distance <= Perception.sightTiles
                    and Perception.inView(shell, player, Perception.fieldOfViewFor(shell))
                    and Perception.playerInSightRange(actor, player, distance)
                    and relations.playerStance(actor, player) == "hostile" then
                return px, py
            end
        end
    end
    return nil
end

function Caution.playerApproach(actor, shell, tiles)
    local policy = ProjectALife.DoorPolicy
    if actor == nil or policy == nil or type(policy.players) ~= "function" then return nil end
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil then return nil end
    local party = ProjectALife.Party
    local list = policy.players()
    for index = 1, #list do
        local player = list[index]
        local px, py, pz = Caution.positionOf(player)
        if px ~= nil and policy.ask(player, "isDead") ~= true and math.abs(pz - sz) < 3 then
            local distance = math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2)
            if distance <= tiles and Perception.playerInSightRange(actor, player, distance)
                    and (Perception.inView(shell, player, Perception.fieldOfViewFor(shell))
                        or Perception.inView(player, shell, Caution.settings.playerViewDegrees))
                    and not (party ~= nil and type(party.friendly) == "function" and party.friendly(actor, player)) then
                return px, py
            end
        end
    end
    return nil
end

function Caution.scanIdleDanger(actor, shell, now)
    local sx, sy, sz = Caution.positionOf(shell)
    if sx == nil then return nil end
    local settings = Caution.settings
    local data = Perception.dataOf(shell)
    if data ~= nil then
        local hitAt = tonumber(data.ProjectALifeLastHitAtMs)
        if hitAt ~= nil and now >= hitAt and now - hitAt < settings.idleHitMs then return "hit" end
    end
    local burning = false
    pcall(function() burning = type(shell.isOnFire) == "function" and shell:isOnFire() == true end)
    if burning then return "fire" end
    local rows = Caution.bodies(now)
    local heard2, seen2 = settings.idleHeardTiles ^ 2, settings.idleSeenTiles ^ 2
    local checks = 0
    for index = 1, #rows do
        local row = rows[index]
        if math.abs(row.z - sz) < 1.5 then
            local d2 = (row.x - sx) ^ 2 + (row.y - sy) ^ 2
            if d2 <= heard2 then return Caution.sawZombie(actor, now), row.x, row.y end
            if d2 <= seen2 and checks < settings.idleChecks and row.body ~= nil then
                checks = checks + 1
                if Perception.visible(shell, row.body) == true then return Caution.sawZombie(actor, now), row.x, row.y end
            end
        end
    end
    local flight = Caution.beamOver(actor, shell, 0)
    if flight ~= nil then
        ProjectALife.HeliSearch.metrics.reactions = ProjectALife.HeliSearch.metrics.reactions + 1
        return "light", flight.x, flight.y
    end
    local investigation = ProjectALife.Investigation
    local marks = investigation ~= nil and investigation.marks or nil
    if type(marks) == "table" then
        for index = 1, #marks do
            local mark = marks[index]
            local at = tonumber(mark.atMs)
            if at ~= nil and now >= at and now - at < settings.idleNoiseMs
                    and (mark.x - sx) ^ 2 + (mark.y - sy) ^ 2 <= (tonumber(mark.radiusSquared) or 0) then
                return "noise", mark.x, mark.y
            end
        end
    end
    if actor ~= nil then
        local px, py = Caution.hostilePlayerSeen(actor, shell)
        if px ~= nil then return "hostile", px, py end
        if Caution.hostileWatching(actor, shell, now) then return "hostile" end
        if type(actor.memory) == "table" and actor.memory.activityId == "fish" then
            local fx, fy = Caution.playerApproach(actor, shell, settings.fishNoticeTiles)
            if fx ~= nil then return "player", fx, fy end
        end
        local first = ProjectALife.FirstDays
        if first ~= nil and type(first.idleHold) == "function" then
            local ok, held = pcall(first.idleHold, actor, shell, now)
            if ok and held ~= nil then return held end
        end
    end
    return nil
end

function Caution.sawZombie(actor, now)
    local first = ProjectALife.FirstDays
    if actor ~= nil and first ~= nil and type(first.noteSeen) == "function" then pcall(first.noteSeen, actor, now) end
    return "zombie"
end

function Caution.idleDanger(actor, shell, now)
    if shell == nil or not Caution.active() then return nil end
    now = now or Gate.nowMs()
    local memo = Caution.idleMemo[shell]
    if memo ~= nil and now >= memo.atMs and now - memo.atMs < Caution.settings.idleCacheMs then
        return memo.reason, memo.x, memo.y
    end
    local reason, x, y = Caution.scanIdleDanger(actor, shell, now)
    Caution.idleMemo[shell] = { atMs = now, reason = reason, x = x, y = y }
    return reason, x, y
end

function Caution.idleGateFor(shell)
    local data = Perception.dataOf(shell)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    local registry = ProjectALife.ActorRegistry
    local actor = uid ~= nil and registry ~= nil and type(registry.peek) == "function" and registry.peek(uid) or nil
    return (Caution.idleDanger(actor, shell, Gate.nowMs()))
end

if ProjectALife.Animations ~= nil then ProjectALife.Animations.idleGate = Caution.idleGateFor end

if ProjectALife.ModuleRegistry ~= nil and type(ProjectALife.ModuleRegistry.register) == "function" then
    ProjectALife.ModuleRegistry.register({
        id = "zombieAvoid",
        kind = "craft",
        label = "Zombie avoidance",
        summary = "On: steers clear of zombies and leaves them alone unless they attack. Off: ignores zombie caution and fights them on sight.",
        defaultEnabled = true,
        evaluate = function() return nil end,
    })
end

return Caution
