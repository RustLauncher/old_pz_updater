require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Records/ALifeMeleeFaction"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Faction = ProjectALife.MeleeFaction

local Crew = {
    settings = {
        sideStep = 0.9,
        retreatScale = 1.4,
        returnDelayMs = 1400,
        returnReach = 2.4,
        matesRadius = 3.5,
        mateCacheMs = 400,
        flankRange = 12,
        flankMinimum = 2.5,
        flankRadius = 10,
        flankEngagerRange = 8,
        flankOffsetDegrees = 110,
        flankWideDegrees = 160,
        waypointDegrees = 50,
        waypointTrigger = 70,
        arrivedRadius = 0.6,
        intimidateNear = 4,
        intimidateFar = 12,
        axeScale = 1.6,
    },
    axeWords = { "axe", "sledgehammer" },
    intents = { investigate = true, investigate_sound = true, investigate_shout = true, investigate_clue = true },
    mateCache = {},
    blockedBy = {},
    metrics = {
        footwork = 0, sidesteps = 0, retreats = 0, returns = 0, asked = 0, idle = 0, blocked = 0, holds = 0,
        flankCircles = 0, flankEngages = 0, intimidations = 0, intimidateTicks = 0,
        breachMotives = 0, breachSwings = 0, cautionRetreats = 0, backpedals = 0, lateralFallbacks = 0,
    },
    force = nil,
}
ProjectALife.MeleeCrew = Crew

function Crew.reset()
    Crew.mateCache = {}
    Crew.blockedBy = {}
    for key in pairs(Crew.metrics) do Crew.metrics[key] = 0 end
end

function Crew.hash(value)
    local result = 17
    value = tostring(value or "")
    for index = 1, #value do result = (result * 31 + string.byte(value, index)) % 2147483647 end
    return result
end

function Crew.on(actor, name)
    local module = Faction.modules[name]
    if module == nil or type(actor) ~= "table" then return false end
    if not Faction.moduleOn(name) then return false end
    if name == "footwork" and Crew.forced(actor) then return true end
    return Registry.allows(actor, module) == true
end

function Crew.setForce(value)
    value = tostring(value or "")
    Crew.force = nil
    if value ~= "" and value ~= "off" then
        Crew.force = {}
        for id in string.gmatch(value, "[^,%s]+") do Crew.force[id] = true end
    end
    return Crew.forceText()
end

function Crew.forceText()
    if Crew.force == nil then return "off" end
    local ids = {}
    for id in pairs(Crew.force) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

function Crew.forced(actor)
    local force = Crew.force
    if force == nil or type(actor) ~= "table" then return false end
    return force.all == true or force[tostring(actor.factionId or "")] == true
end

function Crew.why(actor, name)
    local id = Faction.modules[name]
    if id == nil or type(actor) ~= "table" then return "no_actor" end
    if not Faction.enabled() then return "sandbox:" .. Faction.options.enabled end
    if not Faction.moduleOn(name) then return "sandbox:" .. Faction.options[name] end
    local switches = ProjectALife.ModuleSwitches
    if switches ~= nil and switches.get(id) == false then return "switch:" .. id end
    local override = Registry.override(actor, id)
    if override == "off" then return id .. ":off" end
    if Registry.allowsBase(actor, id) ~= true then return id .. ":inherit" end
    if Registry.allows(actor, id) ~= true then
        local rules = ProjectALife.ModuleRules
        local entry = rules ~= nil and rules.blockedBy(actor, id) or nil
        return "rule:" .. tostring(entry ~= nil and (entry.needs or entry.by) or "?")
    end
    return nil
end

function Crew.noteHeld(combat, reason)
    if type(combat.noteFootBlocked) == "function" then combat.noteFootBlocked(reason) end
end

function Crew.noteBlocked(reason)
    local held = Crew.blockedBy
    held[reason] = (held[reason] or 0) + 1
end

function Crew.footworkLine()
    local combat = ProjectALife.Combat
    local cm = combat ~= nil and type(combat.metrics) == "table" and combat.metrics or {}
    local m = Crew.metrics
    local stock = (tonumber(cm.meleeBackSteps) or 0) + (tonumber(cm.meleeStepIns) or 0)
    local crew = (tonumber(cm.crewSideSteps) or 0) + (tonumber(cm.crewRetreats) or 0) + (tonumber(cm.crewReturns) or 0)
    local parts = {}
    for reason, count in pairs(Crew.blockedBy) do parts[#parts + 1] = reason .. ":" .. tostring(count) end
    for reason, count in pairs(type(combat) == "table" and combat.footBlockedBy or {}) do
        parts[#parts + 1] = "hold_" .. reason .. ":" .. tostring(count)
    end
    if m.holds > 0 then parts[#parts + 1] = "mates:" .. tostring(m.holds) end
    if m.blocked > 0 then parts[#parts + 1] = "wall:" .. tostring(m.blocked) end
    table.sort(parts)
    return "Footwork: steps=" .. tostring(stock + crew) .. " stock=" .. tostring(stock) .. " crew=" .. tostring(crew)
        .. " asked=" .. tostring(m.asked) .. " blockedBy=" .. (#parts > 0 and table.concat(parts, ",") or "none")
        .. " force=" .. Crew.forceText()
end

function Crew.facingLine()
    local combat = ProjectALife.Combat
    local cm = combat ~= nil and type(combat.metrics) == "table" and combat.metrics or {}
    return "MeleeFootwork: steps=" .. tostring(cm.footSteps or 0) .. " back=" .. tostring(cm.footBack or 0)
        .. " side=" .. tostring(cm.footSide or 0) .. " facingKept=" .. tostring(cm.footFacingKept or 0)
        .. " blocked=" .. tostring(cm.footBlocked or 0) .. " reengaged=" .. tostring(cm.footReengaged or 0)
end

function Crew.wrapAngle(angle)
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    return angle
end

function Crew.bearing(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    if dx == 0 then
        if dy > 0 then return math.pi / 2 end
        if dy < 0 then return -math.pi / 2 end
        return 0
    end
    local angle = math.atan(dy / dx)
    if dx < 0 then
        if dy >= 0 then return angle + math.pi end
        return angle - math.pi
    end
    return angle
end

function Crew.sideOf(uid, aim)
    if type(aim) == "table" then
        if aim.crewSide == nil then aim.crewSide = (Crew.hash(uid) % 2 == 0) and 1 or -1 end
        return aim.crewSide
    end
    return (Crew.hash(uid) % 2 == 0) and 1 or -1
end

function Crew.stepPlan(i)
    local s = Crew.settings
    local crowd = tonumber(i.crowd) or 0
    if crowd > 0 and (tonumber(i.mates) or 0) > 0 then crowd = crowd + 1 end
    local gap, reach = tonumber(i.gap) or 0, tonumber(i.reach) or 1
    local pressing = tonumber(i.pressing) or 0
    if crowd > 0 and pressing >= crowd then
        local step = math.min((tonumber(i.kiteStep) or 1.6) * s.retreatScale, reach - 0.15 - gap)
        if step < 0.3 then return nil end
        if i.hold ~= nil then return nil, i.hold end
        return { kind = "crewRetreats", dx = i.pushX, dy = i.pushY, step = step, away = true, retreat = true }
    end
    local back = tonumber(i.backTiles) or 0
    local single = back > 0 and pressing == 1 and (tonumber(i.zombies) or 0) <= 1
    if pressing > 0 and not single then return nil end
    local fx, fy = i.tx - i.sx, i.ty - i.sy
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.05 then return nil end
    local ideal = math.min(1.1, reach * 0.6)
    if single then
        if i.hold ~= nil then return nil, i.hold end
        if i.lastStep ~= "back" then
            local over = math.max(0, tonumber(i.backOver) or 0)
            local step = math.min(back, reach + over - 0.2 - gap)
            if step < 0.3 then return nil end
            return { kind = "crewBackpedals", dx = -fx, dy = -fy, step = step, away = true, backpedal = true,
                fitReach = reach + over }
        end
    elseif i.returning == true and gap > ideal + 0.3 and gap <= reach + s.returnReach then
        local lead = (tonumber(i.stepIn) or 1.1) * 1.5
        return { kind = "crewReturns", dx = fx, dy = fy, step = math.min(lead, gap - ideal), returned = true }
    end
    local zombies = tonumber(i.zombies) or 0
    if gap > reach then return nil end
    local sign = tonumber(i.side) == -1 and -1 or 1
    local px, py = -fy / length, fx / length
    if zombies >= 2 then
        local away = (i.sx - i.cx) * px + (i.sy - i.cy) * py
        sign = away >= 0 and 1 or -1
    elseif not single and (tonumber(i.swing) or 0) % 2 ~= 0 then
        return nil
    end
    if i.hold ~= nil then return nil, i.hold end
    return { kind = "crewSideSteps", dx = px * sign, dy = py * sign, step = s.sideStep, fit = true, sidestep = true }
end

function Crew.lateralPoint(combat, shell, sx, sy, tx, ty, step, target, reach, side)
    local fx, fy = tx - sx, ty - sy
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.05 then return nil end
    for _, sign in ipairs({ side, -side }) do
        local point = combat.footPoint(shell, -fy / length * sign, fx / length * sign,
            math.min(step, Crew.settings.sideStep), target, reach)
        if point ~= nil then return point end
    end
    return nil
end

function Crew.mates(actor, x, y, radius, now)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    local group = memory ~= nil and memory.groupId or nil
    local tactics = ProjectALife.SquadTactics
    if group == nil or tactics == nil or type(tactics.livingMembers) ~= "function" then return 0, nil end
    local held = Crew.mateCache[actor.uid]
    if held ~= nil and now - held.atMs < Crew.settings.mateCacheMs and held.radius == radius then
        return held.count, held.list
    end
    local count, list = tactics.livingMembers(group, actor.uid, x, y, radius)
    Crew.mateCache[actor.uid] = { atMs = now, count = count, list = list, radius = radius }
    return count, list
end

function Crew.footwork(actor, shell, target, aim, now, c)
    if type(aim) ~= "table" or type(c) ~= "table" then return nil end
    if not Crew.on(actor, "footwork") then
        Crew.noteBlocked(Crew.why(actor, "footwork") or "unknown")
        return nil
    end
    local combat = ProjectALife.Combat
    local sx, sy = combat.xyzOf(shell)
    local tx, ty = combat.xyOf(target)
    if sx == nil or tx == nil then return nil end
    local metrics = Crew.metrics
    metrics.asked = metrics.asked + 1
    aim.crewSwing = (aim.crewSwing or 0) + 1
    local cx, cy, count = 0, 0, 0
    for _, other in ipairs(c.zombies) do
        cx, cy, count = cx + other.x, cy + other.y, count + 1
    end
    if count > 0 then cx, cy = cx / count, cy / count else cx, cy = tx, ty end
    local mates = Crew.mates(actor, tx, ty, Crew.settings.matesRadius, now)
    local settings = combat.settings
    local plan, heldBy = Crew.stepPlan({
        gap = c.gap, reach = c.reach, pressing = c.pressing, pushX = c.pushX, pushY = c.pushY,
        crowd = c.crowd, mates = mates, zombies = count, swing = aim.crewSwing,
        sx = sx, sy = sy, tx = tx, ty = ty, cx = cx, cy = cy, hold = c.hold, backTiles = c.backTiles, backOver = c.backOver, lastStep = aim.crewLastStep,
        side = Crew.sideOf(actor.uid, aim), kiteStep = settings.meleeKiteStep, stepIn = settings.meleeStepIn,
        returning = aim.crewReturnAtMs ~= nil and now >= aim.crewReturnAtMs,
    })
    if plan == nil then
        if heldBy ~= nil then Crew.noteHeld(combat, heldBy) end
        metrics.idle = metrics.idle + 1
        local crowd, pressing = tonumber(c.crowd) or 0, tonumber(c.pressing) or 0
        if mates > 0 and crowd > 0 and pressing >= crowd and pressing < crowd + 1 then
            metrics.holds = metrics.holds + 1
            return nil, "hold"
        end
        return nil
    end
    local point
    if plan.away then
        point = combat.footPoint(shell, plan.dx, plan.dy, plan.step, target, plan.fitReach or c.reach)
        if point == nil then point = combat.footPoint(shell, sx - tx, sy - ty, plan.step, target, plan.fitReach or c.reach) end
    else
        point = combat.footPoint(shell, plan.dx, plan.dy, plan.step, target, plan.fit and c.reach or nil)
    end
    if point == nil and plan.away then
        point = Crew.lateralPoint(combat, shell, sx, sy, tx, ty, plan.step, target, c.reach, Crew.sideOf(actor.uid, aim))
        if point ~= nil then
            metrics.lateralFallbacks = metrics.lateralFallbacks + 1
            plan = { kind = "crewSideSteps", sidestep = true }
        end
    end
    if point == nil then
        metrics.blocked = metrics.blocked + 1
        Crew.noteHeld(combat, "wall")
        return nil
    end
    metrics.footwork = metrics.footwork + 1
    if plan.backpedal then
        metrics.backpedals = metrics.backpedals + 1
        aim.crewLastStep = "back"
    elseif plan.retreat then
        aim.crewReturnAtMs = now + Crew.settings.returnDelayMs
        metrics.retreats = metrics.retreats + 1
    elseif plan.returned then
        aim.crewReturnAtMs = nil
        metrics.returns = metrics.returns + 1
    elseif plan.sidestep then
        aim.crewLastStep = "side"
        aim.crewSideSteps = (aim.crewSideSteps or 0) + 1
        if aim.crewSideSteps % 2 == 0 then aim.crewSide = -Crew.sideOf(actor.uid, aim) end
        metrics.sidesteps = metrics.sidesteps + 1
    end
    return point, plan.kind
end

function Crew.pairRank(actor, selfDistance, members, tx, ty, radius)
    local ownKey = tonumber(type(actor.memory) == "table" and actor.memory.groupIndex) or Crew.hash(actor.uid)
    local ahead, engager = 0, nil
    for _, entry in ipairs(members) do
        local mate = entry.actor
        local shell = entry.shell
        if type(mate) == "table" and shell ~= nil and Crew.on(mate, "flank") then
            local dx, dy = shell:getX() - tx, shell:getY() - ty
            if dx * dx + dy * dy <= radius * radius then
                local key = tonumber(type(mate.memory) == "table" and mate.memory.groupIndex) or Crew.hash(mate.uid)
                if key < ownKey or (key == ownKey and tostring(mate.uid) < tostring(actor.uid)) then
                    ahead = ahead + 1
                    if engager == nil or key < engager.key then
                        engager = { key = key, x = shell:getX(), y = shell:getY() }
                    end
                end
            end
        end
    end
    return ahead, engager
end

function Crew.circleGoal(i)
    local s = Crew.settings
    local radius = math.max(1.0, (tonumber(i.standoff) or 1.2) + 0.3)
    local engager = Crew.bearing(i.tx, i.ty, i.ex, i.ey)
    local side = tonumber(i.side) == -1 and -1 or 1
    local sign = (i.rank % 2 == 1) and side or -side
    local degrees = i.rank <= 2 and s.flankOffsetDegrees or s.flankWideDegrees
    local goal = engager + sign * math.rad(degrees)
    local current = Crew.bearing(i.tx, i.ty, i.sx, i.sy)
    local delta = Crew.wrapAngle(goal - current)
    local angle, reach, waypoint = goal, radius, false
    if math.abs(delta) > math.rad(s.waypointTrigger) then
        angle = current + (delta > 0 and 1 or -1) * math.rad(s.waypointDegrees)
        reach = math.max(radius + 0.9, 2.4)
        waypoint = true
    end
    return i.tx + math.cos(angle) * reach, i.ty + math.sin(angle) * reach, waypoint, math.abs(delta)
end

function Crew.flank(actor, shell, target, origin, tpos, distance, standoff, canRun, now)
    if not Crew.on(actor, "flank") then return nil end
    local s = Crew.settings
    if distance > s.flankRange or distance < s.flankMinimum then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or memory.groupId == nil then return nil end
    local count, members = Crew.mates(actor, tpos.x, tpos.y, s.flankRadius, now)
    if count == 0 or members == nil then return nil end
    local rank, engager = Crew.pairRank(actor, distance, members, tpos.x, tpos.y, s.flankEngagerRange)
    if rank == 0 or engager == nil then
        Crew.metrics.flankEngages = Crew.metrics.flankEngages + 1
        return nil
    end
    local gx, gy, waypoint = Crew.circleGoal({
        tx = tpos.x, ty = tpos.y, ex = engager.x, ey = engager.y, sx = origin.x, sy = origin.y,
        standoff = standoff, rank = rank, side = (Crew.hash(memory.groupId) % 2 == 0) and 1 or -1,
    })
    Crew.metrics.flankCircles = Crew.metrics.flankCircles + 1
    local dx, dy = origin.x - gx, origin.y - gy
    local gap = math.sqrt(dx * dx + dy * dy)
    if not waypoint and gap <= s.arrivedRadius then return nil, "walk", "crew_flank_hold" end
    return { x = gx, y = gy, z = tpos.z }, (canRun and gap > 6) and "run" or "walk", "crew_flank"
end

function Crew.intimidate(actor, shell, target, origin, tpos, distance, standoff, now)
    if not Crew.on(actor, "intimidate") then return nil end
    local s = Crew.settings
    if distance < s.intimidateNear or distance > s.intimidateFar then return nil end
    local fair = ProjectALife.Fairness
    if fair == nil or type(fair.isPlayer) ~= "function" or fair.isPlayer(target) ~= true then return nil end
    if fair.underAttack(actor, target, now) or not fair.mayInitiate(actor, target, now) then return nil end
    local warned = type(fair.metrics) == "table" and tonumber(fair.metrics.warned) or 0
    if fair.tell(actor, shell, target, now) == true then return nil end
    if type(fair.metrics) == "table" and (tonumber(fair.metrics.warned) or 0) > warned then
        Crew.metrics.intimidations = Crew.metrics.intimidations + 1
    end
    Crew.metrics.intimidateTicks = Crew.metrics.intimidateTicks + 1
    local dx, dy = origin.x - tpos.x, origin.y - tpos.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then return nil end
    local hold = math.max(standoff, s.intimidateNear)
    return { x = tpos.x + dx / length * hold, y = tpos.y + dy / length * hold, z = tpos.z }, "walk", "intimidate"
end

function Crew.melee(actor, shell, target, origin, tpos, distance, standoff, canRun, now)
    if not Faction.enabled() or type(actor) ~= "table" then return nil end
    local point, pace, kind = Crew.intimidate(actor, shell, target, origin, tpos, distance, standoff, now)
    if kind ~= nil then return point, pace, kind end
    return Crew.flank(actor, shell, target, origin, tpos, distance, standoff, canRun, now)
end

function Crew.shellOf(actor)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[actor.uid] or nil
    return binding ~= nil and binding.shell or nil
end

function Crew.axeName(name)
    name = string.lower(tostring(name or ""))
    for _, word in ipairs(Crew.axeWords) do
        if string.find(name, word, 1, true) ~= nil then return true end
    end
    return false
end

function Crew.axeHeld(shell)
    if shell == nil then return false end
    for _, getter in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        if type(shell[getter]) == "function" then
            local item = shell[getter](shell)
            if item ~= nil and type(item.getType) == "function" and Crew.axeName(item:getType()) then
                return true
            end
        end
    end
    return false
end

function Crew.breachMotive(actor, state)
    if not Crew.on(actor, "breach") then return false end
    local intent = type(state) == "table" and state.intent or nil
    if intent == nil or Crew.intents[intent] ~= true then return false end
    if not Crew.axeHeld(Crew.shellOf(actor)) then return false end
    Crew.metrics.breachMotives = Crew.metrics.breachMotives + 1
    return true
end

function Crew.breachScale(shell)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or policy == nil or type(policy.actorOf) ~= "function" then return 1 end
    local actor = policy.actorOf(shell)
    if actor == nil or not Crew.on(actor, "breach") or not Crew.axeHeld(shell) then return 1 end
    Crew.metrics.breachSwings = Crew.metrics.breachSwings + 1
    return Crew.settings.axeScale
end

function Crew.crowdLimit(actor, base)
    base = tonumber(base) or 5
    if not Crew.on(actor, "caution") then return base end
    return math.min(base, Faction.cautionCrowd())
end

function Crew.noteCaution()
    Crew.metrics.cautionRetreats = Crew.metrics.cautionRetreats + 1
end

local function passive() return nil end

local definitions = {
    {
        id = "meleeFootwork",
        label = "Melee footwork",
        summary = "Melee fighters step back and sideways between swings with their face to the enemy, back off from a press of zombies and step back in; tuned for pairs and groups.",
    },
    {
        id = "meleeFlank",
        label = "Melee flanking pair",
        summary = "In a melee group one member engages and the others circle round to the far side of the target.",
    },
    {
        id = "meleeBreach",
        label = "Axe breacher",
        summary = "A fighter holding an axe cuts through doors and windows faster, and does it when checking a noise.",
    },
    {
        id = "meleeIntimidate",
        label = "Intimidating approach",
        summary = "Walk up on a player at a walk, shout the warning from range, and only then close in to strike.",
    },
    {
        id = "meleeCaution",
        label = "Cautious melee retreat",
        summary = "Retreat early when fewer zombies than usual close in, then come back in.",
    },
}

for _, definition in ipairs(definitions) do
    Registry.register({
        id = definition.id,
        kind = "craft",
        label = definition.label,
        summary = definition.summary,
        defaultEnabled = true,
        evaluate = passive,
    })
end

return Crew
