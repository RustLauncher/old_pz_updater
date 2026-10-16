require "ProjectALife/Behaviours/ALifeInjuryRules"
require "ProjectALife/Combat/ALifeInjury"

ProjectALife = ProjectALife or {}

local Rules = ProjectALife.InjuryRules
local Injury = ProjectALife.Injury

local Rescue = {
    active = {},
    carriers = {},
    cooldown = {},
    nextExpireMs = 0,
    metrics = { considered = 0, noTeam = 0, playerNear = 0, danger = 0, started = 0, dragSteps = 0, healed = 0,
        aborted = 0, reasons = {}, allied = 0, lines = 0, healedInPlace = 0, dragged = 0, dragOff = 0,
        moduleOff = 0, noSight = 0 },
}
ProjectALife.InjuryRescue = Rescue

function Rescue.count(name)
    Rescue.metrics[name] = (Rescue.metrics[name] or 0) + 1
end

function Rescue.sameTeam(first, second)
    local a = type(first) == "table" and type(first.memory) == "table" and first.memory or nil
    local b = type(second) == "table" and type(second.memory) == "table" and second.memory or nil
    if a == nil or b == nil then return false end
    if a.groupId ~= nil and a.groupId == b.groupId then return true end
    if a.outpostId ~= nil and a.outpostId == b.outpostId then return true end
    return false
end

function Rescue.allowed(record)
    local modules = ProjectALife.ModuleRegistry
    if modules == nil or type(modules.allows) ~= "function" then return true end
    local ok, allowed = pcall(modules.allows, record, "healing")
    if ok and allowed == false then
        Rescue.metrics.moduleOff = Rescue.metrics.moduleOff + 1
        return false
    end
    return true
end

function Rescue.allied(bodyRecord, record)
    if bodyRecord.factionId == nil or bodyRecord.factionId ~= record.factionId then return false end
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.status) ~= "function" then return false end
    local ok, status = pcall(relations.status, record, bodyRecord)
    return ok and status == "friendly"
end

function Rescue.hostile(bodyRecord, record)
    local relations = ProjectALife.Relations
    if bodyRecord == nil or record == nil or relations == nil or type(relations.hostile) ~= "function" then return true end
    local ok, hostile = pcall(relations.hostile, record, bodyRecord)
    return not ok or hostile == true
end

function Rescue.sees(shell, body)
    if shell == nil or type(shell.CanSee) ~= "function" then return false end
    local ok, seen = pcall(shell.CanSee, shell, body)
    return ok and seen == true
end

function Rescue.engaged(uid)
    local decisions = ProjectALife.DecisionLoop
    local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[uid] or nil
    return type(state) == "table" and (state.kind == "combat" or state.kind == "retreat")
end

function Rescue.candidates(body, bodyRecord, now)
    local rows = {}
    local watchdog, registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    if watchdog == nil or registry == nil or type(watchdog.bindings) ~= "table" then return rows end
    local bx, by, bz = Injury.xyz(body)
    local limit = Rules.settings().rescueTiles
    local bodyUid = type(bodyRecord) == "table" and bodyRecord.uid or nil
    for uid, binding in pairs(watchdog.bindings) do
        if uid ~= bodyUid and type(binding) == "table" and binding.shell ~= nil then
            local record = registry.peek(uid)
            local team = record ~= nil and record.lifecycle == "active" and Rescue.sameTeam(bodyRecord, record)
            local shell = binding.shell
            local x, y, z = Injury.xyz(shell)
            local near = x ~= nil and bx ~= nil and (x - bx) ^ 2 + (y - by) ^ 2 <= (limit + 5) ^ 2
            local helper = false
            if near and record ~= nil and record.lifecycle == "active" and Rescue.allowed(record)
                    and not Rescue.hostile(bodyRecord, record) then
                if team then
                    helper = true
                elseif Rescue.allied(bodyRecord, record) then
                    if Rescue.sees(shell, body) then
                        helper = true
                        Rescue.metrics.allied = Rescue.metrics.allied + 1
                    else
                        Rescue.metrics.noSight = Rescue.metrics.noSight + 1
                    end
                end
            end
            if helper then
                local data = Injury.dataOf(shell) or {}
                rows[#rows + 1] = {
                    uid = uid, shell = shell, record = record, x = x, y = y, z = z,
                    alive = Injury.alive(shell),
                    injured = data.ProjectALifeInjured ~= nil,
                    busy = Rescue.engaged(uid) or Rescue.carriers[uid] ~= nil
                        or data.ProjectALifeHealDoneAtMs ~= nil or data.ProjectALifeBleedOutAtMs ~= nil
                        or now < (tonumber(data.ProjectALifeDownedUntilMs) or 0),
                    cooldown = now < (Rescue.cooldown[uid] or 0),
                    team = true,
                    allied = not team,
                }
            end
        end
    end
    return rows
end

function Rescue.zombieRows(now)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.bodies) ~= "function" then return {} end
    local ok, rows = pcall(caution.bodies, now)
    if ok and type(rows) == "table" then return rows end
    return {}
end

function Rescue.zombiesAt(x, y, z, tiles, now)
    local rows = Rescue.zombieRows(now)
    local limit = tiles * tiles
    local best, bestFlat
    for index = 1, #rows do
        local row = rows[index]
        local flat = (row.x - x) ^ 2 + (row.y - y) ^ 2
        if math.abs((row.z or z) - z) < 1.5 and flat <= limit and (bestFlat == nil or flat < bestFlat) then
            best, bestFlat = row, flat
        end
    end
    if best == nil then return false end
    return true, best.x, best.y, math.sqrt(bestFlat)
end

function Rescue.hostileActorNear(record, x, y, z, tiles)
    local watchdog, registry, relations = ProjectALife.Watchdog, ProjectALife.ActorRegistry, ProjectALife.Relations
    if watchdog == nil or registry == nil or relations == nil or type(relations.hostile) ~= "function"
            or type(watchdog.bindings) ~= "table" then return false end
    local limit = tiles * tiles
    local bestX, bestY, bestFlat
    for uid, binding in pairs(watchdog.bindings) do
        if uid ~= record.uid and type(binding) == "table" and binding.shell ~= nil then
            local ox, oy, oz = Injury.xyz(binding.shell)
            local flat = ox ~= nil and (ox - x) ^ 2 + (oy - y) ^ 2 or nil
            if flat ~= nil and math.abs(oz - z) < 1.5 and flat <= limit
                    and (bestFlat == nil or flat < bestFlat) and Injury.alive(binding.shell) then
                local other = registry.peek(uid)
                if other ~= nil and other.lifecycle == "active" then
                    local ok, hostile = pcall(relations.hostile, record, other)
                    if ok and hostile == true then bestX, bestY, bestFlat = ox, oy, flat end
                end
            end
        end
    end
    if bestFlat == nil then return false end
    return true, bestX, bestY, math.sqrt(bestFlat)
end

function Rescue.hostilePlayerNear(record, x, y, z, tiles)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return false end
    local limit = tiles * tiles
    local bestX, bestY, bestFlat
    for _, row in ipairs(Injury.playerRows()) do
        local flat = (row.x - x) ^ 2 + (row.y - y) ^ 2
        if math.abs((row.z or z) - z) < 1.5 and flat <= limit and (bestFlat == nil or flat < bestFlat) then
            local ok, stance = pcall(relations.playerStance, record, row.body)
            if ok and stance == "hostile" then bestX, bestY, bestFlat = row.x, row.y, flat end
        end
    end
    if bestFlat == nil then return false end
    return true, bestX, bestY, math.sqrt(bestFlat)
end

function Rescue.threatNear(record, x, y, z, now, tiles)
    local found, tx, ty, distance = Rescue.zombiesAt(x, y, z, tiles, now)
    local kind = found and "zombies" or nil
    local actor, ax, ay, ad = Rescue.hostileActorNear(record, x, y, z, tiles)
    if actor and (kind == nil or ad < distance) then kind, tx, ty, distance = "hostiles", ax, ay, ad end
    local player, px, py, pd = Rescue.hostilePlayerNear(record, x, y, z, tiles)
    if player and (kind == nil or pd < distance) then kind, tx, ty, distance = "player", px, py, pd end
    if kind == nil then return nil end
    return kind, tx, ty, distance
end

function Rescue.danger(record, x, y, z, now, tiles)
    return (Rescue.threatNear(record, x, y, z, now, tonumber(tiles) or Rules.settings().hostileTiles))
end

function Rescue.helpLine(job, carrier, cdata, body, now, settings)
    if now < (tonumber(job.lineAtMs) or 0) then return false end
    job.lineAtMs = now + settings.helpLineGapMs
    local said = Injury.say(carrier, cdata, "WOUNDED_HELP", body)
    if said ~= nil then Rescue.metrics.lines = Rescue.metrics.lines + 1 end
    return said ~= nil
end

function Rescue.release(uid, now, hold)
    local shell = uid ~= nil and Injury.shellOf(uid) or nil
    Rescue.carriers[uid] = nil
    if shell == nil then return false end
    local data = Injury.dataOf(shell)
    if data == nil then return false end
    data.ProjectALifeInjuryHoldUntilMs = nil
    data.ProjectALifeInjuryRole = nil
    data.ProjectALifeDragUntilMs = nil
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.clearLeaderOrder) == "function" then
        pcall(decisions.clearLeaderOrder, uid, data.ProjectALifeGeneration)
    end
    if decisions ~= nil and type(decisions.states) == "table" then
        decisions.states[uid] = { kind = "idle", intent = "rescue_done", cooldownUntilMs = now + 900 }
    end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.clear) == "function" then pcall(animations.clear, shell) end
    pcall(function() shell:setMoving(false) end)
    Rescue.cooldown[uid] = now + (hold or Rules.settings().cooldownMs)
    return true
end

function Rescue.finish(bodyUid, job, reason, now, success)
    Rescue.active[bodyUid] = nil
    Rescue.release(job.rescuer, now, success and 15000 or nil)
    if job.forced == true then
        local perception = ProjectALife.Perception
        if perception ~= nil and type(perception.forgetIgnored) == "function" then
            pcall(perception.forgetIgnored, job.rescuer)
        end
    end
    Rescue.cooldown[bodyUid] = now + (success and 0 or Rules.settings().cooldownMs)
    if success then
        Rescue.metrics.healed = Rescue.metrics.healed + 1
        Injury.metrics.rescueDone = Injury.metrics.rescueDone + 1
    else
        Rescue.metrics.aborted = Rescue.metrics.aborted + 1
        Rescue.metrics.reasons[reason] = (Rescue.metrics.reasons[reason] or 0) + 1
        Injury.metrics.rescueAborted = Injury.metrics.rescueAborted + 1
    end
    Injury.log("rescue " .. (success and "done" or "abort") .. " body=" .. tostring(bodyUid)
        .. " rescuer=" .. tostring(job.rescuer) .. " phase=" .. tostring(job.phase) .. " reason=" .. tostring(reason)
        .. (job.forced == true and " forced=1" or ""))
end

function Rescue.abort(body, data, job, reason, now)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    if data ~= nil and (data.ProjectALifeInjured == "dragged" or data.ProjectALifeInjured == "healing") then
        data.ProjectALifeInjured = "down"
        data.ProjectALifeInjuryClip = nil
        Injury.clearAnchor(data)
        Injury.persist(data)
    end
    if uid ~= nil then Rescue.finish(uid, job, reason, now, false) end
end

function Rescue.dropFor(bodyUid, reason)
    local job = Rescue.active[bodyUid]
    if job == nil then return false end
    Rescue.finish(bodyUid, job, reason or "dropped", Injury.now(), false)
    return true
end

function Rescue.dropUid(uid, reason)
    local bodies = {}
    for bodyUid, job in pairs(Rescue.active) do
        if bodyUid == uid or job.rescuer == uid then bodies[#bodies + 1] = bodyUid end
    end
    local dropped, now = 0, Injury.now()
    for _, bodyUid in ipairs(bodies) do
        local job = Rescue.active[bodyUid]
        local body = Injury.shellOf(bodyUid)
        local bdata = body ~= nil and Injury.dataOf(body) or nil
        if job ~= nil and bdata ~= nil then
            Rescue.abort(body, bdata, job, reason, now)
            dropped = dropped + 1
        elseif job ~= nil then
            Rescue.finish(bodyUid, job, reason, now, false)
            dropped = dropped + 1
        end
    end
    Rescue.carriers[uid] = nil
    return dropped
end

function Rescue.expire(now)
    if now < Rescue.nextExpireMs then return end
    Rescue.nextExpireMs = now + 2000
    for bodyUid, job in pairs(Rescue.active) do
        if now > job.deadlineMs + 6000 then Rescue.finish(bodyUid, job, "stale", now, false) end
    end
    for uid, bodyUid in pairs(Rescue.carriers) do
        if Rescue.active[bodyUid] == nil then Rescue.release(uid, now, 5000) end
    end
end

function Rescue.consider(body, data, now, settings)
    if settings.rescue ~= true then return false end
    local uid = data.ProjectALifeUID
    if type(uid) ~= "string" or now < (Rescue.cooldown[uid] or 0) then return false end
    if now < (tonumber(data.ProjectALifeRescueCheckMs) or 0) then return false end
    data.ProjectALifeRescueCheckMs = now + 1500
    Rescue.metrics.considered = Rescue.metrics.considered + 1
    if settings.rescueInView ~= true and Injury.playerNear(body, settings.playerRange) then
        Rescue.metrics.playerNear = Rescue.metrics.playerNear + 1
        return false
    end
    if now < (tonumber(data.ProjectALifeInjuryTalkUntilMs) or 0) then
        Rescue.metrics.playerNear = Rescue.metrics.playerNear + 1
        return false
    end
    local record = Injury.recordOf(data)
    if record == nil then return false end
    local bx, by, bz = Injury.xyz(body)
    if bx == nil then return false end
    local rows = Rescue.candidates(body, record, now)
    local best = Rules.pickRescuer({ x = bx, y = by, z = bz }, rows, settings)
    if best == nil then
        Rescue.metrics.noTeam = Rescue.metrics.noTeam + 1
        return false
    end
    if Rescue.danger(record, bx, by, bz, now, settings.meleeTiles) ~= nil
            or Rescue.danger(best.record, best.x, best.y, best.z, now, settings.meleeTiles) ~= nil then
        Rescue.metrics.danger = Rescue.metrics.danger + 1
        return false
    end
    if settings.rescueDrag ~= true and Rescue.danger(record, bx, by, bz, now, settings.hostileTiles) ~= nil then
        Rescue.metrics.dragOff = Rescue.metrics.dragOff + 1
        return false
    end
    return Rescue.begin(body, data, best, now, settings)
end

function Rescue.begin(body, data, row, now, settings, forced)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.setOrder) ~= "function" then return false end
    local rdata = Injury.dataOf(row.shell)
    if rdata == nil then return false end
    local bx, by, bz = Injury.xyz(body)
    local ok, accepted = pcall(decisions.setOrder, row.uid, row.record.generation, {
        kind = "hold", source = "leader", quiet = true,
        anchor = { x = bx, y = by, z = math.floor(bz) }, untilMs = now + settings.approachMs,
    })
    if not ok or accepted ~= true then
        Rescue.cooldown[row.uid] = now + 10000
        return false
    end
    local bodyUid = data.ProjectALifeUID
    Rescue.active[bodyUid] = { rescuer = row.uid, phase = "approach", startedMs = now, phaseMs = now,
        deadlineMs = now + settings.approachMs, travelled = 0, forced = forced == true }
    Rescue.carriers[row.uid] = bodyUid
    Rescue.metrics.started = Rescue.metrics.started + 1
    Injury.metrics.rescueStarted = Injury.metrics.rescueStarted + 1
    local rx, ry = Injury.xyz(row.shell)
    Injury.log("rescue start body=" .. tostring(bodyUid) .. " rescuer=" .. tostring(row.uid)
        .. " gap=" .. string.format("%.1f", rx ~= nil and Rules.distance(rx, ry, bx, by) or -1)
        .. (forced == true and " forced=1" or ""))
    Rescue.helpLine(Rescue.active[bodyUid], row.shell, rdata, body, now, settings)
    return true
end

function Rescue.calm(row, now, settings)
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.states) == "table" then
        decisions.states[row.uid] = { kind = "idle", intent = "rescue_forced", cooldownUntilMs = now + 800 }
    end
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.disengage) == "function" then pcall(combat.disengage, row.shell) end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.ignore) == "function" then
        local span = settings.approachMs + settings.dragMs + settings.healMs
        for _, player in ipairs(Injury.playerRows()) do pcall(perception.ignore, row.uid, player.body, span) end
    end
end

function Rescue.force(body, data, now)
    local settings = Rules.settings()
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if type(uid) ~= "string" then return false, "no_uid" end
    if Rescue.active[uid] ~= nil then return false, "already_running" end
    if data.ProjectALifeInjured ~= "down" then return false, "not_down" end
    local record = Injury.recordOf(data)
    if record == nil then return false, "no_record" end
    local bx, by, bz = Injury.xyz(body)
    if bx == nil then return false, "no_position" end
    local rows = Rescue.candidates(body, record, now)
    for _, row in ipairs(rows) do
        row.cooldown = false
        if row.alive == true and row.injured ~= true and Rescue.carriers[row.uid] == nil then row.busy = false end
    end
    local best, why = Rules.pickRescuer({ x = bx, y = by, z = bz }, rows, settings)
    if best == nil then return false, "no_rescuer_" .. tostring(why) end
    if Rescue.danger(record, bx, by, bz, now, settings.meleeTiles) ~= nil
            or Rescue.danger(best.record, best.x, best.y, best.z, now, settings.meleeTiles) ~= nil then
        return false, "danger"
    end
    Rescue.cooldown[uid], Rescue.cooldown[best.uid] = nil, nil
    Rescue.calm(best, now, settings)
    if not Rescue.begin(body, data, best, now, settings, true) then return false, "order_refused" end
    return true, "started"
end

function Rescue.square(shell)
    local ok, square = pcall(shell.getCurrentSquare, shell)
    if ok then return square end
    return nil
end

function Rescue.stepClear(shell, nx, ny)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.stepClear) ~= "function" then return false end
    local square = Rescue.square(shell)
    local sx, sy = Injury.xyz(shell)
    if square == nil or sx == nil then return false end
    local ok, clear = pcall(fence.stepClear, shell, square, sx, sy, nx, ny)
    return ok and clear == true
end

function Rescue.pathClear(carrier, ux, uy, tiles)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.stepClear) ~= "function" or type(getCell) ~= "function" then return false end
    local cell = getCell()
    local x, y, z = Injury.xyz(carrier)
    if x == nil or cell == nil then return false end
    local square = Rescue.square(carrier)
    if square == nil then return false end
    local travelled, step = 0, 0.5
    local cx, cy = x, y
    while travelled < tiles do
        local nx, ny = cx + ux * step, cy + uy * step
        local ok, clear = pcall(fence.stepClear, carrier, square, cx, cy, nx, ny)
        if not ok or clear ~= true then return false, travelled end
        if math.floor(nx) ~= math.floor(cx) or math.floor(ny) ~= math.floor(cy) then
            local landing = cell:getGridSquare(math.floor(nx), math.floor(ny), math.floor(z))
            if landing == nil then return false, travelled end
            square = landing
        end
        cx, cy = nx, ny
        travelled = travelled + step
    end
    return true, travelled
end

function Rescue.nearestPlayer(x, y)
    return Rules.nearestPlayer(Injury.playerRows(), x, y)
end

function Rescue.stillAway(dx, dy, body, now)
    local x, y, z = Injury.xyz(body)
    local record = Injury.recordOf(Injury.dataOf(body))
    if record == nil or x == nil then return false end
    local kind, tx, ty = Rescue.threatNear(record, x, y, z, now, 30)
    return kind == nil or Rules.awayFrom(dx, dy, x, y, tx, ty, 0)
end

function Rescue.chooseDirection(carrier, body, now, settings)
    local bx, by, bz = Injury.xyz(body)
    local threats = {}
    local record = Injury.recordOf(Injury.dataOf(body))
    if record == nil then return nil end
    local kind, tx, ty = Rescue.threatNear(record, bx, by, bz, now, 30)
    local nearest
    if kind ~= nil then
        nearest = { x = tx, y = ty }
    else
        nearest = Rescue.nearestPlayer(bx, by)
    end
    if nearest ~= nil then threats[1] = nearest end
    local ux, uy = Rules.dragDirection(bx, by, threats)
    local tiles = settings.dragMin + Injury.roll(settings.dragMax - settings.dragMin + 1)
    local best, bestTravelled = nil, -1
    for _, turn in ipairs({ 0, 35, -35, 70, -70, 110, -110, 150, -150, 180 }) do
        local dx, dy = Rules.rotate(ux, uy, turn)
        if nearest == nil or Rules.awayFrom(dx, dy, bx, by, nearest.x, nearest.y, 0) then
            local clear, travelled = Rescue.pathClear(carrier, dx, dy, tiles)
            if clear then return dx, dy, tiles end
            if (travelled or 0) > bestTravelled then best, bestTravelled = { dx, dy }, travelled or 0 end
        end
    end
    if best ~= nil and bestTravelled >= 3 then return best[1], best[2], math.floor(bestTravelled) end
    return nil
end

function Rescue.face(shell, x, y, now)
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.faceAimPoint) == "function" then pcall(fence.faceAimPoint, shell, x, y, now) end
end

function Rescue.hold(shell, data, now, role, withDragLease)
    local lease = Rules.settings().leaseMs
    data.ProjectALifeInjuryHoldUntilMs = now + lease
    data.ProjectALifeInjuryRole = role
    if withDragLease == true then data.ProjectALifeDragUntilMs = now + lease else data.ProjectALifeDragUntilMs = nil end
    data.ProjectALifeBleedOutAtMs = nil
end

function Rescue.beginDrag(body, bdata, job, carrier, cdata, now, settings)
    local ux, uy, tiles = Rescue.chooseDirection(carrier, body, now, settings)
    if ux == nil then return false, "no_route" end
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.clearLeaderOrder) == "function" then
        pcall(decisions.clearLeaderOrder, job.rescuer, cdata.ProjectALifeGeneration)
    end
    pcall(function() ProjectALife.Movement.stop(carrier) end)
    pcall(function() carrier:setMoving(false) end)
    Rescue.hold(carrier, cdata, now, "carrier", true)
    if decisions ~= nil and type(decisions.states) == "table" then
        decisions.states[job.rescuer] = { kind = "idle", intent = "rescue_drag", cooldownUntilMs = now + 1500 }
    end
    local cx, cy = Injury.xyz(carrier)
    local px, py = Rules.bodyBehind(cx, cy, ux, uy, 1.0)
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.moveBody) == "function" and Rescue.stepClear(body, px, py) then
        pcall(fence.moveBody, body, px, py)
    else
        px, py = Injury.xyz(body)
    end
    bdata.ProjectALifeInjured = "dragged"
    bdata.ProjectALifeInjuryClip = nil
    Injury.clearAnchor(bdata)
    Injury.stamp(body, bdata, now)
    if px ~= nil then Rescue.face(carrier, px, py, now) end
    local animations = ProjectALife.Animations
    if animations ~= nil then
        pcall(animations.apply, body, "drag_body")
        pcall(animations.apply, carrier, "drag_carry")
    end
    job.phase, job.phaseMs, job.deadlineMs = "drag", now, now + settings.dragMs
    job.ux, job.uy, job.tiles, job.travelled = ux, uy, tiles, 0
    local near = Rescue.nearestPlayer(cx, cy)
    local toward = -2
    if near ~= nil then
        local tx, ty = Rules.unit(near.x - cx, near.y - cy)
        toward = ux * tx + uy * ty
    end
    Injury.log("rescue drag body=" .. tostring(bdata.ProjectALifeUID) .. " tiles=" .. tostring(tiles)
        .. " dir=" .. string.format("%.2f,%.2f", ux, uy) .. " towardPlayer=" .. string.format("%.2f", toward)
        .. (job.forced == true and " forced=1" or ""))
    return true
end

function Rescue.dragStep(body, bdata, job, carrier, cdata, now, settings)
    local cx, cy = Injury.xyz(carrier)
    if cx == nil then return nil, "no_carrier" end
    Rescue.hold(carrier, cdata, now, "carrier", true)
    Injury.stamp(body, bdata, now)
    local step = settings.dragStep
    local nx, ny = cx + job.ux * step, cy + job.uy * step
    local bx, by = Rules.bodyBehind(nx, ny, job.ux, job.uy, 1.0)
    if not Rescue.stepClear(carrier, nx, ny) or not Rescue.stepClear(body, bx, by)
            or not Rescue.stillAway(job.ux, job.uy, body, now) then
        local moved = false
        for _, turn in ipairs({ 35, -35 }) do
            local dx, dy = Rules.rotate(job.ux, job.uy, turn)
            local tx, ty = cx + dx * step, cy + dy * step
            local px, py = Rules.bodyBehind(tx, ty, dx, dy, 1.0)
            if Rescue.stepClear(carrier, tx, ty) and Rescue.stepClear(body, px, py)
                    and Rescue.stillAway(dx, dy, body, now) then
                job.ux, job.uy, nx, ny, moved = dx, dy, tx, ty, true
                bx, by = px, py
                break
            end
        end
        if not moved then
            if job.travelled >= 2 then return "done" end
            return nil, "blocked"
        end
    end
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.moveBody) ~= "function" then return nil, "no_fence" end
    local oldX, oldY = Injury.xyz(body)
    local moved = pcall(fence.moveBody, body, bx, by)
    local actualX, actualY = Injury.xyz(body)
    if not moved or actualX == nil or math.abs(actualX - bx) > 0.05 or math.abs(actualY - by) > 0.05 then
        return nil, "body_move_failed"
    end
    moved = pcall(fence.moveBody, carrier, nx, ny)
    local actualCX, actualCY = Injury.xyz(carrier)
    if not moved or actualCX == nil or math.abs(actualCX - nx) > 0.05 or math.abs(actualCY - ny) > 0.05 then
        return nil, "carrier_move_failed"
    end
    Rescue.face(carrier, bx, by, now)
    Rescue.face(body, nx, ny, now)
    job.travelled = job.travelled + math.sqrt((actualX - oldX) ^ 2 + (actualY - oldY) ^ 2)
    Rescue.metrics.dragSteps = Rescue.metrics.dragSteps + 1
    if job.travelled >= job.tiles then return "done" end
    return "moving"
end

function Rescue.beginHeal(body, bdata, job, carrier, cdata, now, settings)
    job.phase, job.phaseMs, job.deadlineMs = "heal", now, now + settings.healMs
    bdata.ProjectALifeInjured = "healing"
    Injury.stamp(body, bdata, now)
    Rescue.hold(carrier, cdata, now, "carrier", false)
    local healing = ProjectALife.ModuleHealing
    if healing ~= nil and type(healing.dressingOf) == "function" then
        local ok, item = pcall(healing.dressingOf, carrier)
        if ok and item ~= nil then
            job.item = item
            pcall(function() carrier:setPrimaryHandItem(item) end)
        end
    end
    local pose = "heal_body"
    if healing ~= nil and type(healing.poseFor) == "function" then
        local ok, id = pcall(healing.poseFor, bdata)
        if ok and type(id) == "string" then pose = id end
    end
    local animations = ProjectALife.Animations
    if animations ~= nil then pcall(animations.apply, carrier, pose, true) end
    local bx, by = Injury.xyz(body)
    if bx ~= nil then Rescue.face(carrier, bx, by, now) end
    if animations ~= nil then
        bdata.ProjectALifeInjuryClip = "drag_lie"
        pcall(animations.apply, body, "drag_lie")
    end
    Rescue.helpLine(job, carrier, cdata, body, now, settings)
    Injury.log("rescue heal body=" .. tostring(bdata.ProjectALifeUID) .. " pose=" .. tostring(pose)
        .. " travelled=" .. string.format("%.1f", tonumber(job.travelled) or 0)
        .. (job.forced == true and " forced=1" or ""))
end

function Rescue.completeHeal(body, bdata, job, carrier, cdata, now, settings)
    if job.item ~= nil then
        pcall(function()
            carrier:setPrimaryHandItem(nil)
            local inventory = carrier:getInventory()
            if inventory ~= nil then inventory:Remove(job.item) end
        end)
    end
    local list = ProjectALife.Health.injuriesOf(body, bdata)
    if list ~= nil then
        ProjectALife.Wounds.bandage(list)
        pcall(ProjectALife.Health.persistInjuries, bdata)
    end
    Injury.recover(body, bdata, now, "rescued", settings.reviveFraction, false)
    Injury.say(body, bdata, "INJURED_RESCUED", carrier)
    Rescue.finish(bdata.ProjectALifeUID, job, "healed", now, true)
end

function Rescue.advance(body, bdata, job, now, settings)
    local bodyUid = bdata.ProjectALifeUID
    local carrier = Injury.shellOf(job.rescuer)
    local cdata = carrier ~= nil and Injury.dataOf(carrier) or nil
    if carrier == nil or cdata == nil then return Rescue.abort(body, bdata, job, "rescuer_gone", now) end
    if Rescue.hostile(Injury.recordOf(bdata), Injury.recordOf(cdata)) then
        return Rescue.abort(body, bdata, job, "hostile", now)
    end
    if now > job.deadlineMs then return Rescue.abort(body, bdata, job, "timeout_" .. job.phase, now) end
    if job.forced ~= true and settings.rescueInView ~= true and Injury.playerNear(body, settings.playerRange) then
        return Rescue.abort(body, bdata, job, "player_near", now)
    end
    if cdata.ProjectALifeInjured ~= nil then return Rescue.abort(body, bdata, job, "rescuer_injured", now) end
    local bx, by, bz = Injury.xyz(body)
    local cx, cy, cz = Injury.xyz(carrier)
    if bx == nil or cx == nil then return Rescue.abort(body, bdata, job, "no_position", now) end
    if job.phase ~= "approach" and (math.abs(cz - bz) > 0.5 or (cx - bx) ^ 2 + (cy - by) ^ 2 > 1.9 * 1.9) then
        return Rescue.abort(body, bdata, job, "separated", now)
    end
    if now >= (job.nextDangerMs or 0) then
        job.nextDangerMs = now + 1000
        local record = Injury.recordOf(bdata)
        if record ~= nil and Rescue.danger(record, cx, cy, cz, now, settings.meleeTiles) ~= nil then
            return Rescue.abort(body, bdata, job, "danger", now)
        end
    end
    if job.phase == "approach" then
        if job.forced ~= true and Rescue.engaged(job.rescuer) then
            return Rescue.abort(body, bdata, job, "rescuer_engaged", now)
        end
        if math.abs(cz - bz) > 0.5 then return Rescue.abort(body, bdata, job, "floor", now) end
        if (cx - bx) ^ 2 + (cy - by) ^ 2 <= 1.9 * 1.9 then
            local record = Injury.recordOf(bdata)
            local threatened = job.forced == true
                or (record ~= nil and Rescue.danger(record, bx, by, bz, now, settings.hostileTiles) ~= nil)
            if not threatened then
                Rescue.metrics.healedInPlace = Rescue.metrics.healedInPlace + 1
                job.travelled = 0
                Rescue.beginHeal(body, bdata, job, carrier, cdata, now, settings)
                return true
            end
            if settings.rescueDrag ~= true then return Rescue.abort(body, bdata, job, "danger", now) end
            local ok, why = Rescue.beginDrag(body, bdata, job, carrier, cdata, now, settings)
            if not ok then return Rescue.abort(body, bdata, job, why or "drag_refused", now) end
            Rescue.metrics.dragged = Rescue.metrics.dragged + 1
        end
        return true
    end
    if job.phase == "drag" then
        local status, why = Rescue.dragStep(body, bdata, job, carrier, cdata, now, settings)
        if status == nil then return Rescue.abort(body, bdata, job, why or "drag_failed", now) end
        if status == "done" then Rescue.beginHeal(body, bdata, job, carrier, cdata, now, settings) end
        return true
    end
    if job.phase == "heal" then
        Rescue.hold(carrier, cdata, now, "carrier", false)
        Injury.stamp(body, bdata, now)
        if now - job.phaseMs >= settings.healWorkMs then
            Rescue.completeHeal(body, bdata, job, carrier, cdata, now, settings)
        end
        return true
    end
    return false
end

function Rescue.step(body, data, now)
    Rescue.expire(now)
    local settings = Rules.settings()
    local uid = data.ProjectALifeUID
    local job = Rescue.active[uid]
    if job == nil then
        if data.ProjectALifeInjured ~= "down" then return false end
        return Rescue.consider(body, data, now, settings)
    end
    return Rescue.advance(body, data, job, now, settings)
end

return Rescue
