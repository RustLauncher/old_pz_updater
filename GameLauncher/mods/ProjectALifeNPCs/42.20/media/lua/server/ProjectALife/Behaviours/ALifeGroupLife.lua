require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Movement/ALifeGroupSpread"
require "ProjectALife/Behaviours/ALifeGroupVenue"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate
local Spread = ProjectALife.GroupSpread
local Venue = ProjectALife.GroupVenue

local Life = {
    settings = {
        minFraction = 0.5,
        maxFraction = 2.0,
        rotateMinutes = 6,
        gatherMs = 30000,
        settledShare = 0.6,
        musterMs = 14000,
        musterNear = 1.6,
        planMs = 9000,
        planGapMs = 120,
        cooldownMs = 120000,
        pruneMs = 90000,
        slotTolerance = 0.9,
        maxWalks = 6,
        memberRadius = 40,
        beatSitMs = 2500,
        beatLookoutMs = 1500,
        beatTalkMs = 2000,
        beatCommentMs = 2200,
        scanMinMs = 4000,
        scanSpreadMs = 5000,
        scanDegrees = 40,
        gestureMinMs = 6000,
        gestureSpreadMs = 8000,
        pauseMinMs = 5000,
        pauseSpreadMs = 7000,
        gossipMs = 15000,
        barkMs = 15000,
    },
    pool = { "talker", "talker", "lookout", "sitter", "commenter", "quiet",
        "smoker", "eater", "sitter", "quiet", "smoker", "eater" },
    leaderPrefs = { "lookout", "commenter", "talker", "smoker" },
    gestures = { "yes", "shrug", "no", "thumbs_up" },
    snacks = { smoker = { "smoke" }, eater = { "eat", "drink" } },
    snackMs = { smoke = 20000, eat = 12000, drink = 9000 },
    adapters = {},
    stops = {},
    posed = {},
    ambient = {},
    cooldowns = {},
    serial = 0,
    sweptAtMs = 0,
    planGate = 0,
    metrics = { shelterStops = 0, coverStops = 0, openStops = 0, rolesAssigned = 0, idleMinutes = 0,
        rotations = 0, alerts = 0, musters = 0, settled = 0, stuck = 0, abandoned = 0, spares = 0 },
}
ProjectALife.GroupLife = Life

function Life.nowMs()
    return Spread.nowMs()
end

function Life.hours()
    if type(Life.adapters.hours) == "function" then return Life.adapters.hours() end
    local hours = 0
    if type(getGameTime) == "function" then
        pcall(function() hours = getGameTime():getWorldAgeHours() end)
    end
    return tonumber(hours) or 0
end

function Life.enabled()
    return Spread.enabled() and Gate.authority()
end

function Life.rolesEnabled()
    return Gate.flag("GroupLife_Roles", true)
end

function Life.idleMinutes()
    return Gate.number("GroupLife_ShelterIdleMinutes", 20, 5, 90)
end

function Life.minutesFor(groupId, hours)
    local settings = Life.settings
    local fraction = settings.minFraction
        + (settings.maxFraction - settings.minFraction) * Spread.unit(tostring(groupId) .. ":" .. math.floor(hours * 4))
    return Life.idleMinutes() * fraction
end

function Life.rolePool(count)
    local roles = {}
    if count <= 1 then return { "quiet" } end
    if count == 2 then return { "talker", "smoker" } end
    for index = 1, count do roles[index] = Life.pool[((index - 1) % #Life.pool) + 1] end
    return roles
end

function Life.indexOf(list, value)
    for index, item in ipairs(list) do
        if item == value then return index end
    end
    return nil
end

function Life.assign(members, seed)
    local pool = Life.rolePool(#members)
    local ordered = {}
    for _, member in ipairs(members) do
        ordered[#ordered + 1] = { uid = member.uid, leader = member.leader == true,
            key = Spread.hash(tostring(seed) .. ":" .. member.uid) }
    end
    table.sort(ordered, function(left, right)
        if left.key ~= right.key then return left.key < right.key end
        return left.uid < right.uid
    end)
    local left = {}
    for _, role in ipairs(pool) do left[#left + 1] = role end
    local result = {}
    for _, member in ipairs(ordered) do
        if member.leader then
            for _, preference in ipairs(Life.leaderPrefs) do
                local at = Life.indexOf(left, preference)
                if at ~= nil then
                    result[member.uid] = preference
                    table.remove(left, at)
                    break
                end
            end
            if result[member.uid] == nil then result[member.uid] = table.remove(left, 1) end
        end
    end
    for _, member in ipairs(ordered) do
        if result[member.uid] == nil then result[member.uid] = table.remove(left, 1) end
    end
    local owners, used = {}, {}
    for index, role in ipairs(pool) do
        for _, member in ipairs(ordered) do
            if result[member.uid] == role and not used[member.uid] then
                owners[index] = member.uid
                used[member.uid] = true
                break
            end
        end
    end
    return result, pool, owners
end

function Life.eligibleMembers(group, stop)
    local list = {}
    local registry = ProjectALife.ActorRegistry
    local radius2 = Life.settings.memberRadius * Life.settings.memberRadius
    for _, entry in ipairs(group.list) do
        local dx, dy = entry.x - stop.anchor.x, entry.y - stop.anchor.y
        if dx * dx + dy * dy <= radius2 and math.abs(entry.z - stop.anchor.z) < 1.5 then
            local record = registry ~= nil and registry.peek(entry.uid) or nil
            local memory = type(record) == "table" and record.memory or nil
            if Spread.eligible(memory) and memory.activityId == nil then list[#list + 1] = entry end
        end
    end
    return list
end

function Life.begin(groupId, spec)
    if not Life.enabled() or type(groupId) ~= "string" then return nil, "disabled" end
    spec = type(spec) == "table" and spec or {}
    local now = tonumber(spec.now) or Life.nowMs()
    local held = Life.stops[groupId]
    if held ~= nil then return held end
    if now < (Life.cooldowns[groupId] or 0) then return nil, "cooldown" end
    local group = Spread.groupOf(groupId, now)
    if group == nil or group.size < 2 then return nil, "no_group" end
    local lead = group.leader or group.list[1]
    local anchor = type(spec.anchor) == "table" and spec.anchor or { x = lead.x, y = lead.y, z = lead.z }
    local hours = tonumber(spec.hours) or Life.hours()
    local minutes = tonumber(spec.minutes) or Life.minutesFor(groupId, hours)
    Life.serial = Life.serial + 1
    local stop = {
        id = groupId, source = tostring(spec.source or "api"), phase = "plan", serial = Life.serial,
        startedMs = now, startedHours = hours, durationHours = minutes / 60, seenMs = now,
        untilHours = hours + minutes / 60 + 0.25,
        anchor = { x = anchor.x, y = anchor.y, z = math.floor(tonumber(anchor.z) or 0) },
        leaderUid = spec.leaderUid or lead.uid, members = {}, member = {}, roles = {}, slots = {},
        seed = groupId .. ":" .. Life.serial,
    }
    Life.stops[groupId] = stop
    return stop
end

function Life.finish(stop, reason, now)
    if stop == nil or Life.stops[stop.id] ~= stop then return false end
    now = tonumber(now) or Life.nowMs()
    Life.stops[stop.id] = nil
    Venue.release(stop.id)
    stop.phase, stop.reason = "done", reason
    if stop.settledHours ~= nil then
        local minutes = math.max(0, (math.min(Life.hours(), stop.untilHours or Life.hours()) - stop.settledHours) * 60)
        Life.metrics.idleMinutes = Life.metrics.idleMinutes + minutes
    end
    if reason == "danger" or reason == "fight" or reason == "threat" then
        Life.cooldowns[stop.id] = now + Life.settings.cooldownMs
    end
    if reason == "abandoned" then Life.metrics.abandoned = Life.metrics.abandoned + 1 end
    return true
end

function Life.cooling(groupId, now)
    if not Life.enabled() then return false end
    return (tonumber(now) or Life.nowMs()) < (Life.cooldowns[groupId] or 0)
end

function Life.endStop(groupId, reason)
    local stop = Life.stops[groupId]
    if stop == nil then return false end
    return Life.finish(stop, reason or "ended")
end

function Life.sweep(now)
    if now - Life.sweptAtMs < 5000 then return end
    Life.sweptAtMs = now
    for _, stop in pairs(Life.stops) do
        if now - stop.seenMs > Life.settings.pruneMs then Life.finish(stop, "abandoned", now) end
    end
    for uid, mark in pairs(Life.posed) do
        if now - mark.atMs > 600000 then Life.posed[uid] = nil end
    end
    Spread.sweep(now)
    local groups = Spread.refresh(now)
    for groupId in pairs(Life.ambient) do
        if groups[groupId] == nil then Life.ambient[groupId] = nil end
    end
end

function Life.ambientRoles(squadId)
    if not Life.enabled() or not Life.rolesEnabled() then return {} end
    local group = Spread.groupOf(squadId, Life.nowMs())
    if group == nil or group.size < 2 then return {} end
    local names = {}
    for _, entry in ipairs(group.list) do names[#names + 1] = entry.uid .. (entry.leader and "*" or "") end
    local signature = table.concat(names, ",")
    local held = Life.ambient[squadId]
    if held ~= nil and held.signature == signature then return held.roles end
    local roles = Life.assign(group.list, squadId)
    Life.ambient[squadId] = { signature = signature, roles = roles }
    return roles
end

function Life.rolesOf(squadId)
    local result = {}
    local stop = Life.stops[squadId]
    local source
    if stop ~= nil and stop.phase ~= "plan" then
        source = stop.roles
    else
        source = Life.ambientRoles(squadId)
    end
    for uid, role in pairs(source) do result[uid] = role end
    return result
end

function Life.slotsOf(squadId)
    local result = {}
    local stop = Life.stops[squadId]
    if stop == nil or stop.phase == "plan" then return result end
    for uid, slot in pairs(stop.slots) do
        result[uid] = { x = slot.x, y = slot.y, z = slot.z, role = slot.role,
            facingTarget = slot.facingTarget, facingUid = slot.facingUid }
    end
    return result
end

function Life.pairOf(squadId)
    local stop = Life.stops[squadId]
    if stop == nil or stop.pair == nil then return nil end
    return { stop.pair[1], stop.pair[2] }
end

function Life.stateOf(squadId)
    local stop = Life.stops[squadId]
    if stop == nil then return nil end
    return stop.phase
end

function Life.kindOf(squadId)
    local stop = Life.stops[squadId]
    if stop == nil or stop.venue == nil then return nil end
    return stop.venue.kind
end

function Life.chatTopic(squadId)
    local stop = Life.stops[squadId]
    local gossip = ProjectALife.Gossip
    local fallback = gossip ~= nil and type(gossip.topicFallback) == "table" and gossip.topicFallback or nil
    if stop ~= nil and stop.venue ~= nil and stop.venue.kind == "building" and fallback ~= nil
            and fallback.shelter ~= nil then
        return "shelter"
    end
    return "rest"
end

function Life.conversationSlots(from, to, z)
    if type(from) ~= "table" or type(to) ~= "table" then return nil end
    local mx, my = (from.x + to.x) / 2, (from.y + to.y) / 2
    local dx, dy = Venue.unitVector(from, to)
    if dx == 0 and dy == 0 then dx = 1 end
    local half = 1.0
    local a = { x = mx - dx * half, y = my - dy * half, z = z or from.z or 0 }
    local b = { x = mx + dx * half, y = my + dy * half, z = z or from.z or 0 }
    a.facingTarget = { x = b.x, y = b.y }
    b.facingTarget = { x = a.x, y = a.y }
    return a, b
end

function Life.positionOf(shell)
    local ok, x, y, z = pcall(Spread.positionOf, shell)
    if not ok then return nil end
    return x, y, z
end

function Life.face(shell, point, now, turns)
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then return false end
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.faceAimPoint) ~= "function" then return false end
    local turned = false
    for index = 0, (turns or 1) - 1 do
        if pcall(fence.faceAimPoint, shell, point.x, point.y, now + index * 100) then turned = true end
    end
    return turned
end

function Life.currentPose(shell)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.current) ~= "table" then return nil end
    return animations.current[shell]
end

function Life.pose(shell, id)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" then return false, "no_animations" end
    local ok, applied, why = pcall(animations.apply, shell, id)
    if not ok then return false, "error" end
    return applied == true, why
end

function Life.release(shell)
    local animations = ProjectALife.Animations
    if animations == nil then return false end
    local current = Life.currentPose(shell)
    if current == nil then return false end
    local sitting = current == "sit_ground" or current == "sit_down" or current == "warm_hands"
    if sitting and type(animations.apply) == "function" then
        pcall(animations.apply, shell, "sit_up", true)
        return true
    end
    if type(animations.clear) == "function" then pcall(animations.clear, shell) end
    return false
end

function Life.say(shell, event)
    local voice = ProjectALife.Voice
    if voice ~= nil and type(voice.play) == "function" then pcall(voice.play, shell, event) end
end

function Life.idle(context, actor, intent, now, delay)
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", intent) end
    return { kind = "idle", intent = intent, cooldownUntilMs = now + delay }
end

function Life.letGo(actor, shell, context, now)
    local mark = Life.posed[actor.uid]
    if mark == nil then return nil end
    Life.posed[actor.uid] = nil
    local stood = Life.release(shell)
    if mark.rest then Life.say(shell, "REST_END") end
    if stood then return Life.idle(context, actor, "idle_stand_up", now, 1000) end
    return nil
end

function Life.danger(actor, shell, now)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.idleDanger) ~= "function" then return nil end
    local ok, reason, x, y = pcall(caution.idleDanger, actor, shell, now)
    if not ok then return nil end
    return reason, x, y
end

function Life.raise(stop, actor, shell, reason, x, y, now)
    if stop.alert ~= nil then return end
    stop.alert = { reason = reason, x = x, y = y, atMs = now, by = actor.uid }
    Life.metrics.alerts = Life.metrics.alerts + 1
    Life.cooldowns[stop.id] = now + Life.settings.cooldownMs
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.states) == "table" then
        for uid in pairs(stop.member) do
            local held = decisions.states[uid]
            if type(held) == "table" and held.kind == "idle" then held.cooldownUntilMs = 0 end
        end
    end
    local line = decisions ~= nil and type(decisions.dangerLines) == "table" and decisions.dangerLines[reason] or nil
    local last = Life.barkedAt ~= nil and Life.barkedAt[actor.uid] or nil
    if line ~= nil and (last == nil or now - last > Life.settings.barkMs) then
        Life.barkedAt = Life.barkedAt or {}
        Life.barkedAt[actor.uid] = now
        local voice = ProjectALife.Voice
        if voice ~= nil and type(voice.play) == "function" then
            pcall(voice.play, shell, line, { context = { targetKind = reason == "zombie" and "zombie" or "player" } })
        end
    end
end

function Life.react(stop, actor, shell, context, now, member)
    member.alerted = true
    Life.posed[actor.uid] = nil
    local stood = Life.release(shell)
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.setPosture) == "function" then pcall(combat.setPosture, actor, shell, true, now) end
    if stop.alert ~= nil and stop.alert.x ~= nil and stop.alert.y ~= nil then
        Life.face(shell, { x = stop.alert.x, y = stop.alert.y }, now, 12)
    end
    local reacted, total = 0, 0
    for _, row in pairs(stop.member) do
        total = total + 1
        if row.alerted then reacted = reacted + 1 end
    end
    if reacted >= total or now - stop.alert.atMs > 4000 then Life.finish(stop, "danger", now) end
    return Life.idle(context, actor, "idle_alert", now, stood and 1100 or 400)
end

function Life.rotationHours(stop)
    return math.max(Life.settings.rotateMinutes, stop.durationHours * 60 / 3) / 60
end

function Life.commit(stop, venue, slots, now, roleOf, pool, owners)
    stop.venue = venue
    stop.pool = pool
    stop.owners = owners
    stop.roles, stop.slots = {}, {}
    local rolesOn = Life.rolesEnabled()
    for index, slot in ipairs(slots) do
        local uid = owners[index]
        if uid ~= nil then
            local role = "idle"
            if rolesOn then role = slot.role end
            stop.roles[uid] = role
            stop.slots[uid] = { x = slot.x, y = slot.y, z = venue.z, role = role, index = index,
                facingTarget = slot.facing ~= nil and { x = slot.facing.x, y = slot.facing.y, z = venue.z } or nil }
            stop.member[uid] = stop.member[uid] or {}
            stop.member[uid].role = role
        end
    end
    for index, slot in ipairs(slots) do
        local uid = owners[index]
        if uid ~= nil and slot.facingIndex ~= nil and owners[slot.facingIndex] ~= nil then
            stop.slots[uid].facingUid = owners[slot.facingIndex]
        end
    end
    local pairA, pairB
    if #pool == 2 then
        pairA, pairB = owners[1], owners[2]
    else
        for index, role in ipairs(pool) do
            if role == "talker" and owners[index] ~= nil then
                if pairA == nil then pairA = owners[index] elseif pairB == nil then pairB = owners[index] end
            end
        end
    end
    if pairA ~= nil and pairB ~= nil then stop.pair = { pairA, pairB } end
    stop.pairSits = Spread.unit(stop.seed .. ":sit") < 0.55
    stop.chatUid = stop.leaderUid
    if stop.member[stop.chatUid] == nil then stop.chatUid = pairA end
    stop.phase = "gather"
    stop.gatherMs = now
    stop.arrived = 0
    stop.rotations = 0
    stop.rotateAtHours = Life.hours() + Life.rotationHours(stop)
    if rolesOn then Life.metrics.rolesAssigned = Life.metrics.rolesAssigned + #stop.members end
    if venue.kind == "building" then
        Life.metrics.shelterStops = Life.metrics.shelterStops + 1
        Venue.claim(venue.key, stop.id)
    elseif venue.kind == "cover" then
        Life.metrics.coverStops = Life.metrics.coverStops + 1
    else
        Life.metrics.openStops = Life.metrics.openStops + 1
    end
    return true
end

function Life.planStep(stop, now)
    if stop.plan ~= nil and stop.plan.pool ~= nil and now - stop.startedMs > Life.settings.planMs
            and stop.plan.stage ~= "fallback" then
        stop.plan.stage = "fallback"
    end
    if now < Life.planGate then return false end
    Life.planGate = now + Life.settings.planGapMs
    local plan = stop.plan
    if plan == nil then
        plan = { stage = "members" }
        stop.plan = plan
    end
    if plan.stage == "members" then
        local group = Spread.groupOf(stop.id, now)
        stop.members = group ~= nil and Life.eligibleMembers(group, stop) or {}
        if #stop.members < 2 then
            Life.finish(stop, "no_members", now)
            return false
        end
        plan.roleOf, plan.pool, plan.owners = Life.assign(stop.members, stop.id)
        plan.stage = "scan"
    elseif plan.stage == "scan" then
        if (stop.replans or 0) >= 2 then
            plan.stage = "cover"
        else
            plan.list = Venue.candidates(stop.anchor, stop.id, now)
            plan.index = 1
            plan.stage = "analyze"
        end
    elseif plan.stage == "analyze" then
        local entry = plan.list[plan.index]
        plan.index = plan.index + 1
        if entry == nil then
            plan.stage = "cover"
        elseif Venue.infested(entry, stop.anchor.z, now) then
            Venue.ban(entry.key, now)
        else
            local analysis = Venue.analyze(entry, stop.anchor.z, now)
            if Venue.usable(analysis, #stop.members) then
                local venue = Venue.buildingVenue(analysis)
                local slots = Venue.solve(venue, plan.pool, stop.seed)
                if slots ~= nil then
                    return Life.commit(stop, venue, slots, now, plan.roleOf, plan.pool, plan.owners)
                end
            end
        end
    elseif plan.stage == "cover" then
        local venue = Venue.cover(stop.anchor, stop.id)
        local slots = venue ~= nil and Venue.solve(venue, plan.pool, stop.seed) or nil
        if slots ~= nil then
            return Life.commit(stop, venue, slots, now, plan.roleOf, plan.pool, plan.owners)
        end
        plan.stage = "fallback"
    else
        local venue = Venue.ring(stop.anchor, #stop.members, stop.id)
        local slots = Venue.solve(venue, plan.pool, stop.seed)
        if slots == nil then
            Life.finish(stop, "no_slots", now)
            return false
        end
        return Life.commit(stop, venue, slots, now, plan.roleOf, plan.pool, plan.owners)
    end
    return false
end

function Life.slotClear(stop, candidate)
    for _, slot in pairs(stop.slots) do
        if (slot.x - candidate.x) ^ 2 + (slot.y - candidate.y) ^ 2 < 1.5 * 1.5 then return false end
    end
    return true
end

function Life.spare(stop, uid)
    local venue = stop.venue
    if venue == nil then return nil end
    local free = {}
    for _, candidate in ipairs(venue.list) do
        if Life.slotClear(stop, candidate) then free[#free + 1] = candidate end
    end
    local sub = { list = free, byKey = venue.byKey, tableList = {}, tables = {}, centre = venue.centre,
        entry = venue.entry, cluster = venue.cluster, kind = venue.kind, z = venue.z }
    local slots = Venue.solve(sub, { "eater" }, stop.seed .. ":" .. uid)
    if slots == nil then return nil end
    local slot = slots[1]
    stop.roles[uid] = "eater"
    stop.slots[uid] = { x = slot.x, y = slot.y, z = venue.z, role = "eater", index = 0,
        facingTarget = slot.facing ~= nil and { x = slot.facing.x, y = slot.facing.y, z = venue.z } or nil }
    stop.member[uid] = stop.member[uid] or {}
    stop.member[uid].role = "eater"
    Life.metrics.spares = Life.metrics.spares + 1
    Life.metrics.rolesAssigned = Life.metrics.rolesAssigned + 1
    return stop.slots[uid]
end

function Life.rotate(stop, now)
    local lookout
    local others = {}
    for uid, role in pairs(stop.roles) do
        if role == "lookout" then
            lookout = uid
        elseif role == "sitter" or role == "quiet" or role == "smoker" or role == "eater" then
            others[#others + 1] = uid
        end
    end
    table.sort(others)
    if lookout == nil or #others == 0 then return false end
    stop.rotations = stop.rotations + 1
    local pick = others[(Spread.hash(stop.seed .. ":rot:" .. stop.rotations) % #others) + 1]
    stop.roles[lookout], stop.roles[pick] = stop.roles[pick], stop.roles[lookout]
    local a, b = stop.slots[lookout], stop.slots[pick]
    if a == nil or b == nil then return false end
    stop.slots[lookout], stop.slots[pick] = b, a
    a.role, b.role = stop.roles[pick], stop.roles[lookout]
    for _, uid in ipairs({ lookout, pick }) do
        local member = stop.member[uid]
        if member ~= nil then
            member.role = stop.roles[uid]
            member.arrivedMs, member.sitStage, member.nextPoseMs, member.walks, member.stuck = nil, nil, nil, 0, nil
        end
    end
    Life.metrics.rotations = Life.metrics.rotations + 1
    Life.metrics.rolesAssigned = Life.metrics.rolesAssigned + 2
    stop.rotateAtHours = Life.hours() + Life.rotationHours(stop)
    return true
end

function Life.beginMuster(stop, now)
    local venue = stop.venue
    if venue == nil or venue.kind ~= "building" or venue.exit == nil then
        Life.finish(stop, "done", now)
        return
    end
    stop.phase = "muster"
    stop.musterAtMs = now
    Life.metrics.musters = Life.metrics.musters + 1
    local slots = Venue.musterSlots(venue.exit, #stop.members, stop.id, venue.z)
    stop.muster = {}
    local uids = {}
    for uid in pairs(stop.member) do uids[#uids + 1] = uid end
    table.sort(uids)
    for index, uid in ipairs(uids) do
        stop.muster[uid] = slots[index] or { x = venue.exit.x, y = venue.exit.y, z = venue.z }
    end
end

function Life.musterStep(stop, actor, shell, context, now, member)
    local spot = stop.muster and stop.muster[actor.uid] or nil
    Life.posed[actor.uid] = Life.posed[actor.uid] or { atMs = now, rest = stop.source == "rest" }
    local pose = Life.currentPose(shell)
    if pose ~= nil then
        local stood = Life.release(shell)
        if stood then return Life.idle(context, actor, "group_muster", now, 1000) end
    end
    local x, y = Life.positionOf(shell)
    if spot == nil or x == nil then
        member.mustered = true
    else
        local near = Life.settings.musterNear
        if (x - spot.x) ^ 2 + (y - spot.y) ^ 2 <= near * near then member.mustered = true end
    end
    local done, total = 0, 0
    for _, row in pairs(stop.member) do
        total = total + 1
        if row.mustered then done = done + 1 end
    end
    if done >= total or now - stop.musterAtMs > Life.settings.musterMs then
        Life.finish(stop, "done", now)
        return Life.idle(context, actor, "group_muster", now, 600)
    end
    if member.mustered then return Life.idle(context, actor, "group_muster", now, 800) end
    local state = context.startMovement(actor, shell, { x = spot.x, y = spot.y, z = spot.z }, "rest",
        { pace = "walk", tolerance = 1.0, timeoutMs = 12000, activity = "moving" })
    if state ~= nil then return state end
    member.mustered = true
    return Life.idle(context, actor, "group_muster", now, 800)
end

function Life.standBeat(stop, actor, shell, context, now, member, slot)
    local current = Life.currentPose(shell)
    if current == "sit_ground" or current == "sit_down" then
        Life.release(shell)
        member.sitStage = nil
        return Life.idle(context, actor, "group_" .. member.role, now, 1000)
    end
    return nil
end

function Life.sitBeat(stop, actor, shell, context, now, member, slot)
    local current = Life.currentPose(shell)
    if current == "sit_ground" then
        member.sitStage = "down"
        return Life.idle(context, actor, "group_" .. member.role, now, Life.settings.beatSitMs)
    end
    if member.sitStage == "in" and now - (member.sitAtMs or now) >= 2400 then
        local applied = Life.pose(shell, "sit_ground")
        if applied then
            member.sitStage = "down"
            return Life.idle(context, actor, "group_" .. member.role, now, Life.settings.beatSitMs)
        end
    end
    if member.sitStage ~= "in" then
        Life.face(shell, slot.facingTarget, now, 12)
        local applied, why = Life.pose(shell, "sit_down")
        if applied then
            member.sitStage, member.sitAtMs = "in", now
            return Life.idle(context, actor, "group_" .. member.role, now, 2500)
        end
        if why == "idle_danger" then return nil, "danger" end
        member.poseFailed = (member.poseFailed or 0) + 1
    end
    return Life.idle(context, actor, "group_" .. member.role, now, Life.settings.beatSitMs)
end

function Life.rotated(slot, degrees)
    if type(slot.facingTarget) ~= "table" then return nil end
    local dx, dy = slot.facingTarget.x - slot.x, slot.facingTarget.y - slot.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then return nil end
    local radians = math.rad(degrees)
    local cx, cy = math.cos(radians), math.sin(radians)
    local rx, ry = (dx * cx - dy * cy) / length, (dx * cy + dy * cx) / length
    return { x = slot.x + rx * 4, y = slot.y + ry * 4 }
end

function Life.lookoutBeat(stop, actor, shell, context, now, member, slot)
    local standing = Life.standBeat(stop, actor, shell, context, now, member, slot)
    if standing ~= nil then return standing end
    if now >= (member.scanAtMs or 0) then
        member.scans = (member.scans or 0) + 1
        member.scanAtMs = now + Life.settings.scanMinMs + Life.settings.scanSpreadMs * Spread.unit(actor.uid .. ":s:" .. member.scans)
        local degrees = Spread.signed(actor.uid .. ":d:" .. member.scans) * Life.settings.scanDegrees
        local point = Life.rotated(slot, degrees) or slot.facingTarget
        Life.face(shell, point, now, 4)
    end
    return Life.idle(context, actor, "group_lookout", now, Life.settings.beatLookoutMs)
end

function Life.gesture(shell, actor, now, member)
    if now < (member.gestureAtMs or 0) then return false end
    member.gestures = (member.gestures or 0) + 1
    member.gestureAtMs = now + Life.settings.gestureMinMs
        + Life.settings.gestureSpreadMs * Spread.unit(actor.uid .. ":g:" .. member.gestures)
    local id = Life.gestures[(Spread.hash(actor.uid .. ":gs:" .. member.gestures) % #Life.gestures) + 1]
    Life.pose(shell, id)
    return true
end

function Life.commentBeat(stop, actor, shell, context, now, member, slot)
    local standing = Life.standBeat(stop, actor, shell, context, now, member, slot)
    if standing ~= nil then return standing end
    if now >= (member.faceAtMs or 0) then
        member.faceAtMs = now + 4000
        Life.face(shell, slot.facingTarget, now, 2)
    end
    Life.gesture(shell, actor, now, member)
    return Life.idle(context, actor, "group_commenter", now, Life.settings.beatCommentMs)
end

function Life.snackBeat(stop, actor, shell, context, now, member, slot)
    local standing = Life.standBeat(stop, actor, shell, context, now, member, slot)
    if standing ~= nil then return standing end
    if now >= (member.nextPoseMs or 0) then
        local menu = Life.snacks[member.role] or Life.snacks.eater
        member.snacks = (member.snacks or 0) + 1
        local id = menu[((member.snacks - 1) % #menu) + 1]
        local applied, why = Life.pose(shell, id)
        if why == "idle_danger" then return nil, "danger" end
        local length = Life.snackMs[id] or 12000
        member.nextPoseMs = now + length + Life.settings.pauseMinMs
            + Life.settings.pauseSpreadMs * Spread.unit(actor.uid .. ":p:" .. member.snacks)
        if not applied then member.nextPoseMs = now + Life.settings.pauseMinMs end
    end
    if now >= (member.faceAtMs or 0) then
        member.faceAtMs = now + 5000
        Life.face(shell, slot.facingTarget, now, 2)
    end
    return Life.idle(context, actor, "group_" .. member.role, now, Life.settings.beatTalkMs)
end

function Life.talkBeat(stop, actor, shell, context, now, member, slot)
    if stop.pairSits then
        local state, why = Life.sitBeat(stop, actor, shell, context, now, member, slot)
        return state, why
    end
    local standing = Life.standBeat(stop, actor, shell, context, now, member, slot)
    if standing ~= nil then return standing end
    if now >= (member.faceAtMs or 0) then
        member.faceAtMs = now + 3000
        Life.face(shell, slot.facingTarget, now, 2)
    end
    Life.gesture(shell, actor, now, member)
    return Life.idle(context, actor, "group_talker", now, Life.settings.beatTalkMs)
end

function Life.chat(stop, actor, shell, now)
    if actor.uid ~= stop.chatUid or now < (stop.chatAtMs or 0) then return end
    stop.chatAtMs = now + Life.settings.gossipMs
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.tryStart) ~= "function" then return end
    pcall(gossip.tryStart, shell, { context = "ambient", groupId = stop.id, topic = Life.chatTopic(stop.id), now = now })
end

function Life.hold(stop, actor, shell, context, now, member, slot)
    local first = member.arrivedMs == nil
    if first then
        member.arrivedMs = now
        stop.arrived = stop.arrived + 1
        Life.posed[actor.uid] = { atMs = now, rest = stop.source == "rest" }
        Life.face(shell, slot.facingTarget, now, 12)
        if stop.source == "rest" then Life.say(shell, "REST_START") end
    end
    if stop.settledHours == nil and (stop.arrived >= math.ceil(#stop.members * Life.settings.settledShare)
            or now - stop.gatherMs > Life.settings.gatherMs) then
        stop.settledHours = Life.hours()
        stop.untilHours = stop.settledHours + stop.durationHours
        stop.phase = "idle"
        Life.metrics.settled = Life.metrics.settled + 1
    end
    Life.chat(stop, actor, shell, now)
    local role = member.role
    local state, why
    if role == "sitter" or role == "quiet" then
        state, why = Life.sitBeat(stop, actor, shell, context, now, member, slot)
    elseif role == "talker" then
        state, why = Life.talkBeat(stop, actor, shell, context, now, member, slot)
    elseif role == "lookout" then
        state = Life.lookoutBeat(stop, actor, shell, context, now, member, slot)
    elseif role == "commenter" then
        state = Life.commentBeat(stop, actor, shell, context, now, member, slot)
    elseif role == "smoker" or role == "eater" then
        state, why = Life.snackBeat(stop, actor, shell, context, now, member, slot)
    else
        state = Life.standBeat(stop, actor, shell, context, now, member, slot)
    end
    if why == "danger" then
        local reason, x, y = Life.danger(actor, shell, now)
        Life.raise(stop, actor, shell, reason or "zombie", x, y, now)
        return Life.react(stop, actor, shell, context, now, member)
    end
    if state == nil then state = Life.idle(context, actor, "group_" .. tostring(role), now, Life.settings.beatTalkMs) end
    return state
end

function Life.replan(stop, now)
    if stop.venue ~= nil then Venue.ban(stop.venue.key, now) end
    Venue.release(stop.id)
    stop.replans = (stop.replans or 0) + 1
    stop.venue, stop.plan, stop.pair = nil, nil, nil
    stop.roles, stop.slots, stop.member = {}, {}, {}
    stop.phase, stop.startedMs, stop.stuckCount, stop.settledHours = "plan", now, 0, nil
    Life.metrics.replans = (Life.metrics.replans or 0) + 1
end

function Life.noteStuck(stop, member, now)
    member.stuck = true
    Life.metrics.stuck = Life.metrics.stuck + 1
    if stop.venue == nil or stop.venue.kind ~= "building" or (stop.replans or 0) >= 2 then return end
    stop.stuckCount = (stop.stuckCount or 0) + 1
    if stop.stuckCount >= math.ceil(#stop.members / 2) then Life.replan(stop, now) end
end

function Life.walk(stop, actor, shell, context, now, member, slot, x, y, z)
    if Life.currentPose(shell) ~= nil and Life.posed[actor.uid] ~= nil then
        Life.release(shell)
        member.sitStage = nil
    end
    member.walks = (member.walks or 0) + 1
    if member.walks > Life.settings.maxWalks then
        Life.noteStuck(stop, member, now)
        return nil
    end
    local state = context.startMovement(actor, shell, { x = slot.x, y = slot.y, z = slot.z }, "rest",
        { pace = "walk", tolerance = 0.5, timeoutMs = 15000, activity = "moving" })
    if state ~= nil then return state end
    member.fails = (member.fails or 0) + 1
    if member.fails >= 3 then
        Life.noteStuck(stop, member, now)
        return nil
    end
    return Life.idle(context, actor, "group_gather", now, 700)
end

function Life.slotStep(stop, actor, shell, context, now, member)
    local slot = stop.slots[actor.uid]
    if slot == nil then
        slot = Life.spare(stop, actor.uid)
        if slot == nil then return nil end
        member = stop.member[actor.uid]
    end
    member.role = member.role or slot.role
    local x, y, z = Life.positionOf(shell)
    if x == nil then return nil end
    local tolerance = Life.settings.slotTolerance
    local away = (x - slot.x) ^ 2 + (y - slot.y) ^ 2 > tolerance * tolerance
        or math.floor(z or 0) ~= math.floor(slot.z or 0)
    if away and not member.stuck then
        local state = Life.walk(stop, actor, shell, context, now, member, slot, x, y, z)
        if stop.phase == "plan" then return Life.idle(context, actor, "group_gather", now, 500) end
        if state ~= nil then return state end
        if not member.stuck then return nil end
    end
    if member.stuck then
        slot = { x = x, y = y, z = z, role = member.role, facingTarget = slot.facingTarget }
    else
        member.walks = 0
    end
    return Life.hold(stop, actor, shell, context, now, member, slot)
end

function Life.advance(stop, actor, shell, context, now)
    stop.seenMs = now
    local member = stop.member[actor.uid]
    if member == nil then
        member = {}
        stop.member[actor.uid] = member
    end
    if stop.alert ~= nil and not member.alerted then
        return Life.react(stop, actor, shell, context, now, member)
    end
    if stop.alert ~= nil then
        if now - stop.alert.atMs > 4000 then Life.finish(stop, "danger", now) end
        return Life.idle(context, actor, "idle_alert", now, 500)
    end
    if context.threat ~= nil then
        Life.raise(stop, actor, shell, "threat", nil, nil, now)
        return Life.react(stop, actor, shell, context, now, member)
    end
    local reason, dx, dy = Life.danger(actor, shell, now)
    if reason ~= nil then
        Life.raise(stop, actor, shell, reason, dx, dy, now)
        return Life.react(stop, actor, shell, context, now, member)
    end
    if stop.phase == "plan" then
        Life.planStep(stop, now)
        return Life.idle(context, actor, "group_gather", now, 500)
    end
    local hours = Life.hours()
    if stop.phase ~= "muster" and hours >= stop.untilHours then Life.beginMuster(stop, now) end
    if Life.stops[stop.id] ~= stop then return Life.letGo(actor, shell, context, now) end
    if stop.phase == "muster" then return Life.musterStep(stop, actor, shell, context, now, member) end
    if stop.phase == "idle" and hours >= (stop.rotateAtHours or math.huge) then Life.rotate(stop, now) end
    return Life.slotStep(stop, actor, shell, context, now, member)
end

function Life.excused(actor, shell, memory, context)
    if not Spread.eligible(memory) then return true end
    if memory.activityId ~= nil then return true end
    local order = context.orders ~= nil and context.orders[actor.uid] or nil
    if type(order) == "table" and order.source ~= "leader" and order.generation == actor.generation
            and (order.untilMs == nil or (tonumber(context.now) or 0) < order.untilMs) then
        return true
    end
    if type(shell.getVehicle) ~= "function" then return false end
    local ok, vehicle = pcall(shell.getVehicle, shell)
    return ok and vehicle ~= nil
end

function Life.heldStop(actor, shell, context)
    if not Life.enabled() or type(actor) ~= "table" or type(context) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or type(memory.groupId) ~= "string" then return nil end
    local stop = Life.stops[memory.groupId]
    if stop == nil or Life.excused(actor, shell, memory, context) then return nil end
    return stop
end

function Life.governs(actor, shell, context)
    return Life.heldStop(actor, shell, context) ~= nil
end

function Life.step(actor, shell, context)
    if not Life.enabled() or type(actor) ~= "table" or type(context) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or type(memory.groupId) ~= "string" then return nil end
    local now = tonumber(context.now) or Life.nowMs()
    Life.sweep(now)
    local stop = Life.stops[memory.groupId]
    if stop == nil then return Life.letGo(actor, shell, context, now) end
    if Life.heldStop(actor, shell, context) == nil then return nil end
    return Life.advance(stop, actor, shell, context, now)
end

function Life.restStep(actor, shell, context, groupId, group, fought)
    if not Life.enabled() then return false end
    local stop = Life.stops[groupId]
    if stop == nil then
        group.untilHours = 0
        return false
    end
    if fought then
        Life.finish(stop, "fight")
        group.untilHours = 0
        return false
    end
    local state = Life.step(actor, shell, context)
    if Life.stops[groupId] ~= nil then group.untilHours = stop.untilHours end
    if state == nil and Life.stops[groupId] == nil then
        group.untilHours = 0
        return false
    end
    if state == nil then return false end
    return true, state
end

function Life.beginRest(actor, shell, groupId, now, hours, group)
    if not Life.enabled() then return false end
    local x, y, z = Life.positionOf(shell)
    if x == nil then return false end
    local stop = Life.begin(groupId, { source = "rest", leaderUid = actor.uid, now = now, hours = hours,
        anchor = { x = x, y = y, z = z } })
    if stop == nil then return false end
    group.untilHours = stop.untilHours
    group.life = true
    return true
end

function Life.reset()
    Life.stops, Life.posed, Life.cooldowns, Life.barkedAt, Life.ambient = {}, {}, {}, nil, {}
    Life.sweptAtMs, Life.planGate = 0, 0
    Venue.reset()
    Spread.reset()
end

return Life
