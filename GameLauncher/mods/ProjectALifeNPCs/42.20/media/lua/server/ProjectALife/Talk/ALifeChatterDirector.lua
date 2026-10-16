ProjectALife = ProjectALife or {}

require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeChatterKit"
require "ProjectALife/Audio/ALifeGossip"
require "ProjectALife/Activities/ALifeFishing"

local Gate = ProjectALife.FeatureGate
local Kit = ProjectALife.ChatterKit

local Director = {
    settings = {
        scanMs = 800,
        playMs = 100,
        scanRadius = 60,
        startRadius = 40,
        scanCap = 90,
        groupRadius = 6.5,
        gapMinMs = 25000,
        gapMaxMs = 90000,
        firstGapMinMs = 5000,
        firstGapMaxMs = 18000,
        retryMs = 6000,
        noSceneMs = 15000,
        dangerGapMs = 25000,
        afterStopMs = 30000,
        gatherMs = 7000,
        arriveTiles = 1.3,
        moveMinTiles = 0.9,
        aimMs = 1200,
        interruptTiles = 3.5,
        approachGapMs = 20000,
        afterSceneMs = 8000,
        hazardEveryMs = 400,
        cohesionTiles = 14,
        quietPlayerTiles = 55,
        quietPlayerMs = 10000,
        passNpcTiles = 8,
        passNpcCooldownMs = 180000,
        passNpcAnswerMs = 1100,
        meetWatchMs = 30000,
        greetNearTiles = 2.5,
        greetFarTiles = 14,
        greetTalkTiles = 8,
        greetGroupMs = 45000,
        greetFloorMs = 25000,
        greetRetryMs = 45000,
        greetEvaluate = 4,
        stateKeepMs = 300000,
        pruneMs = 60000,
        pumpMs = 3000,
        queueCap = 32,
    },
    groups = {},
    scenes = {},
    inScene = {},
    active = 0,
    snapshot = nil,
    nextScanAt = 0,
    nextPlayAt = 0,
    nextPruneAt = 0,
    nextPumpAt = 0,
    scanTurn = 0,
    groupGreeted = {},
    playerGreeted = {},
    pairGreeted = {},
    meetWatch = {},
    queue = {},
    playKeys = {},
    dangerReasons = { hit = true, fire = true, zombie = true, light = true, noise = true, hostile = true,
        player = true, fear = true, busy = true, orders = true },
    metrics = {
        chatterScenes = 0, chatterBarks = 0, passingGreets = 0, passingNpcGreets = 0, refusedDanger = 0,
        stoppedDanger = 0, noSceneAvailable = {}, comments = 0, gestures = 0, stepUps = 0, scans = 0,
        requests = 0, meetProbes = 0, meetHalts = 0, approached = 0, active = 0,
    },
}
ProjectALife.ChatterDirector = Director

function Director.enabled()
    if not Kit.enabled() then return false end
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.settings) == "table" and talk.settings.enabled == false then return false end
    local speech = ProjectALife.Speech
    return speech ~= nil and speech.authoritative() == true
end

function Director.nowMs()
    return Gate.nowMs()
end

function Director.noScene(topic, reason)
    local key = tostring(topic) .. ":" .. tostring(reason)
    local counts = Director.metrics.noSceneAvailable
    counts[key] = (counts[key] or 0) + 1
end

function Director.later(delayMs, fn, now)
    if #Director.queue >= Director.settings.queueCap then return false end
    Director.queue[#Director.queue + 1] = { at = now + delayMs, fn = fn }
    return true
end

function Director.flush(now)
    local pending = Director.queue
    if #pending == 0 then return 0 end
    Director.queue = {}
    local done = 0
    for index = 1, #pending do
        local item = pending[index]
        if now >= item.at then
            done = done + 1
            pcall(item.fn)
        else
            Director.queue[#Director.queue + 1] = item
        end
    end
    return done
end

function Director.pump()
    local data = ProjectALife.DialogueData
    if data == nil or type(data.load) ~= "function" then return end
    data.load()
    local pool = data.scenesByTopic.any
    if type(pool) == "table" then Kit.partition(pool) end
end

function Director.playerPoints(now)
    local presence = ProjectALife.ModuleTalkPresence
    local result = {}
    if presence == nil or type(presence.playersAt) ~= "function" then return result end
    local list = presence.playersAt(now)
    for index = 1, #list do
        local player = list[index]
        if presence.standing(player) then
            local x, y, z = Kit.position(player)
            if x ~= nil then result[#result + 1] = { player = player, x = x, y = y, z = z } end
        end
    end
    return result
end

function Director.nearestPlayer(points, x, y)
    local best, bestD2 = nil, nil
    for index = 1, #points do
        local point = points[index]
        local d2 = (point.x - x) ^ 2 + (point.y - y) ^ 2
        if bestD2 == nil or d2 < bestD2 then best, bestD2 = point, d2 end
    end
    return best, bestD2
end

function Director.stateFor(key, now)
    local state = Director.groups[key]
    if state == nil then
        local s = Director.settings
        state = {
            nextAt = now + s.firstGapMinMs + Kit.roll(s.firstGapMaxMs - s.firstGapMinMs + 1),
            played = {}, playedCount = 0, count = 0,
        }
        Director.groups[key] = state
    end
    state.seenAt = now
    return state
end

function Director.gap()
    local s = Director.settings
    local base = s.gapMinMs + Kit.roll(s.gapMaxMs - s.gapMinMs + 1)
    return math.floor(base * 100 / Kit.frequency())
end

function Director.calmCheck(entry, now)
    local actor, shell = entry.actor, entry.shell
    local speech, talk = ProjectALife.Speech, ProjectALife.Talk
    if speech.talkable(shell, actor, now) ~= true then return false, "talkable" end
    if talk ~= nil and type(talk.busy) == "function" and talk.busy(actor, now) then return false, "busy" end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.orderedTo ~= nil or memory.robbery ~= nil or memory.walkWith ~= nil then return false, "orders" end
    if (tonumber(memory.talkHoldUntilMs) or 0) > now or (tonumber(memory.gossipHoldUntilMs) or 0) > now then
        return false, "hold"
    end
    local decisions = ProjectALife.DecisionLoop
    local order = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders[entry.uid] or nil
    if type(order) == "table" and order.source ~= "leader" and order.generation == actor.generation
            and (order.untilMs == nil or now < order.untilMs) then return false, "orders" end
    local fear = ProjectALife.ModuleFear
    local record = fear ~= nil and type(fear.actors) == "table" and fear.actors[entry.uid] or nil
    if type(record) == "table" and record.flight ~= nil then return false, "fear" end
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear ~= nil and type(gunFear.flights) == "table" and gunFear.flights[entry.uid] ~= nil then return false, "fear" end
    local leader = ProjectALife.ModuleLeader
    local group = leader ~= nil and type(leader.groups) == "table" and memory.groupId ~= nil
        and leader.groups[memory.groupId] or nil
    if type(group) == "table" and group.inContact == true then return false, "busy" end
    local caution = ProjectALife.Caution
    if caution ~= nil and type(caution.idleDanger) == "function" then
        local reason, x, y = caution.idleDanger(actor, shell, now)
        if reason ~= nil then return false, reason, x, y end
    end
    return true
end

function Director.calm(entry, now)
    if entry.calm == nil then entry.calm, entry.why, entry.hx, entry.hy = Director.calmCheck(entry, now) end
    return entry.calm, entry.why
end

function Director.cluster(group, now)
    local members = group.members
    local count = #members
    if count < 2 then return nil, "alone" end
    local anchor, best = nil, nil
    for left = 1, count do
        local sum = 0
        for right = 1, count do
            sum = sum + (members[left].x - members[right].x) ^ 2 + (members[left].y - members[right].y) ^ 2
        end
        if best == nil or sum < best then best, anchor = sum, members[left] end
    end
    local radius2 = Director.settings.groupRadius ^ 2
    local near = {}
    for index = 1, count do
        local member = members[index]
        member.ad2 = (member.x - anchor.x) ^ 2 + (member.y - anchor.y) ^ 2
        if member.ad2 <= radius2 and math.abs(member.z - anchor.z) < 1.5 and Director.inScene[member.uid] == nil then
            near[#near + 1] = member
        end
    end
    if #near < 2 then return nil, "spread" end
    table.sort(near, function(a, b)
        if a.ad2 ~= b.ad2 then return a.ad2 < b.ad2 end
        return a.uid < b.uid
    end)
    local calm, danger = {}, false
    for index = 1, #near do
        local ok, why = Director.calm(near[index], now)
        if ok then
            calm[#calm + 1] = near[index]
        elseif Director.dangerReasons[why] then
            danger = true
        end
    end
    if danger then return nil, "danger" end
    if #calm < 2 then return nil, "busy" end
    return calm
end

function Director.isMoving(member)
    if member.actor.activity == "moving" then return true end
    local ok, moving = pcall(member.shell.isMoving, member.shell)
    return ok and moving == true
end

function Director.isSeated(member)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.presetOf) ~= "function" or type(animations.current) ~= "table" then return false end
    local current = animations.current[member.shell]
    local preset = current ~= nil and animations.presetOf(current) or nil
    return preset ~= nil and preset.idle == true
end

function Director.steppable(member)
    local actor = member.actor
    if actor.activity == "scavenging" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.lootPhase ~= nil or memory.activityId ~= nil then return false end
    if Kit.stayRoles[member.role] then return false end
    return not Director.isSeated(member)
end

function Director.rolesOf(group, cluster)
    local life = ProjectALife.GroupLife
    if life == nil or type(life.rolesOf) ~= "function" then return nil end
    local memory = type(cluster[1].actor.memory) == "table" and cluster[1].actor.memory or {}
    local ok, map = pcall(life.rolesOf, memory.squadId or memory.groupId or group.key)
    if ok and type(map) == "table" then return map end
    return nil
end

function Director.planOf(group, cluster)
    local plans = ProjectALife.GroupPlan
    if plans == nil or type(plans.current) ~= "function" then return nil end
    local memory = type(cluster[1].actor.memory) == "table" and cluster[1].actor.memory or {}
    local ok, plan = pcall(plans.current, memory.squadId or memory.groupId or group.key)
    if ok and type(plan) == "table" then return plan end
    return nil
end

function Director.insideAll(cluster)
    for index = 1, #cluster do
        local shell = cluster[index].shell
        local square = type(shell.getCurrentSquare) == "function" and shell:getCurrentSquare() or nil
        if square == nil or type(square.isOutside) ~= "function" or square:isOutside() then return false end
    end
    return true
end

function Director.situation(group, cluster, state, now)
    local actor = cluster[1].actor
    local clock = ProjectALife.Speech.clock()
    local moving, fishing, fishers = 0, 0, 0
    local fish = ProjectALife.ActivityFishing
    for index = 1, #cluster do
        if Director.isMoving(cluster[index]) then moving = moving + 1 end
        local member = cluster[index].actor
        local memory = type(member.memory) == "table" and member.memory or {}
        local activity = type(memory.activityState) == "table" and memory.activityState.activity or nil
        if memory.activityId == "fish" and type(activity) == "table" and activity.id == "fish"
                and tonumber(memory.activitySeq) ~= nil and activity.seq == memory.activitySeq
                and (member.intent == "fishing" or member.intent == "fishing_watch")
                and type(activity.fishing) == "table" and type(activity.fishing.work) == "table"
                and fish ~= nil and type(fish.atPost) == "function" then
            local work = activity.fishing.work[tostring(member.uid)]
            local x, y, z = Kit.position(cluster[index].shell)
            if type(work) == "table" and type(work.post) == "table" and x ~= nil then
                local ok, atPost = pcall(fish.atPost, { lifecycle = member.lifecycle,
                    worldPosition = { x = x, y = y, z = z } }, work.post)
                if ok and atPost == true then
                    fishing = fishing + 1
                    if work.watch ~= true and member.intent == "fishing" then fishers = fishers + 1 end
                end
            end
        end
    end
    local situation = {
        moving = moving * 2 >= #cluster,
        day = tonumber(clock.daysSurvived) or 0,
        plan = Director.planOf(group, cluster),
        shelter = Director.insideAll(cluster),
    }
    situation.panic = situation.day <= 4
    situation.fishing = fishers > 0 and fishing * 2 >= #cluster
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.ambientTopic) == "function" then
        local topic = decisions.ambientTopic(actor, now)
        situation.fight = topic == "after_fight"
        situation.scavenging = topic == "scavenge"
    end
    local request = state.request
    if request ~= nil then
        if now < request.expiresAt then situation.requested = request.topic else state.request = nil end
    end
    return situation
end

function Director.request(key, topic, options)
    if type(key) ~= "string" or type(topic) ~= "string" then return false end
    options = type(options) == "table" and options or {}
    local now = Director.nowMs()
    local state = Director.stateFor(key, now)
    state.request = { topic = topic, expiresAt = now + (tonumber(options.ttlMs) or 90000) }
    if state.nextAt > now + 800 then state.nextAt = now + 800 end
    Director.metrics.requests = Director.metrics.requests + 1
    return true
end

function Director.centroid(members)
    local sx, sy = 0, 0
    for index = 1, #members do sx, sy = sx + members[index].x, sy + members[index].y end
    return sx / #members, sy / #members, members[1].z
end

function Director.facingOf(scene, cx, cy)
    local point = scene.viewer
    if point ~= nil then
        local dx, dy = point.x - cx, point.y - cy
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.5 then return dx / length, dy / length end
    end
    local angle = (Kit.hash(scene.token .. ":face") % 628) / 100
    return math.cos(angle), math.sin(angle)
end

function Director.stepUp(scene, now)
    local ring = scene.ring
    if #ring < 2 then return 0 end
    local cx, cy, cz = Director.centroid(ring)
    local ux, uy = Director.facingOf(scene, cx, cy)
    local points, focusX, focusY = Kit.arc(cx, cy, #ring, ux, uy, scene.token)
    scene.center = { x = focusX, y = focusY }
    local assigned = Kit.assign(points, ring, ux, uy)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.setOrder) ~= "function" then return 0 end
    local square = type(ring[1].shell.getCurrentSquare) == "function" and ring[1].shell:getCurrentSquare() or nil
    local reference = Kit.placeKey(square)
    local moved, minimum = 0, Director.settings.moveMinTiles ^ 2
    for index = 1, #ring do
        local member, target = ring[index], assigned[index]
        if target ~= nil and Director.steppable(member) then
            local dx, dy = target.x - member.x, target.y - member.y
            if dx * dx + dy * dy >= minimum and Kit.freeSquare(target.x, target.y, cz, reference) then
                local anchor = { x = target.x, y = target.y, z = math.floor(cz) }
                local ok, accepted = pcall(decisions.setOrder, member.uid, member.actor.generation,
                    { kind = "hold", anchor = anchor, untilMs = scene.untilMs, source = "leader", quiet = true })
                if ok and accepted == true then
                    scene.ordered[member.uid] = anchor
                    moved = moved + 1
                end
            end
        end
    end
    Director.metrics.stepUps = Director.metrics.stepUps + moved
    return moved
end

function Director.release(scene)
    local decisions = ProjectALife.DecisionLoop
    for uid, anchor in pairs(scene.ordered) do
        local order = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders[uid] or nil
        if type(order) == "table" and order.anchor == anchor then
            local actor = ProjectALife.ActorRegistry.peek(uid)
            if actor ~= nil then pcall(decisions.clearLeaderOrder, uid, actor.generation) end
        end
        scene.ordered[uid] = nil
    end
end

function Director.begin(group, state, now)
    local settings = Director.settings
    local cluster, why = Director.cluster(group, now)
    if cluster == nil then
        if why == "danger" then
            Director.metrics.refusedDanger = Director.metrics.refusedDanger + 1
            state.nextAt = now + settings.dangerGapMs
        else
            state.nextAt = now + settings.retryMs
        end
        return false, why
    end
    local situation = Director.situation(group, cluster, state, now)
    state.count = state.count + 1
    local seed = tostring(group.key) .. ":" .. tostring(state.count)
    local assignment = Kit.roles(cluster, Director.rolesOf(group, cluster), seed)
    local pool = {}
    for index = 1, #assignment.speakers do
        pool[#pool + 1] = assignment.speakers[index]
        if index == 2 and assignment.commenter ~= nil then pool[#pool + 1] = assignment.commenter end
    end
    if #pool < 2 then
        state.nextAt = now + settings.retryMs
        return false, "speakers"
    end
    local chain = Kit.topicChain(situation)
    local picked, topic
    local options = { exclude = state.played, prefer = #pool >= 3 and 3 or nil }
    for index = 1, #chain do
        local result, reason = Kit.pickScene(chain[index], pool, seed .. ":" .. chain[index], options)
        if result ~= nil then
            picked, topic = result, chain[index]
            break
        end
        Director.noScene(chain[index], reason)
    end
    if picked == nil then
        state.nextAt = now + settings.noSceneMs
        return false, "no_scene"
    end
    return Director.launch(group, state, assignment, picked, topic, situation, seed, now)
end

function Director.launch(group, state, assignment, picked, topic, situation, seed, now)
    local settings = Director.settings
    local turns = picked.source.turns
    if type(turns) ~= "table" or #turns == 0 then
        state.nextAt = now + settings.noSceneMs
        return false, "turns"
    end
    local total = 0
    for index = 1, #turns do total = total + Kit.turnMs(turns[index].t) + 280 end
    local nearest = group.members[1] ~= nil and group.members[1].player or nil
    local scene = {
        key = group.key, token = seed, topic = topic, id = picked.id, turns = turns, slots = picked.slots,
        ring = assignment.ring, silent = assignment.silent, commenter = assignment.commenter,
        phase = "talk", turnIndex = 0, startedAt = now, ordered = {}, aimUntil = 0,
        stationary = (not situation.moving) and topic ~= "walk", nextHazardAt = now,
        viewer = nearest, nearAt = now, untilMs = now + settings.gatherMs + total + 4000,
    }
    scene.members = scene.ring
    if situation.plan ~= nil and situation.plan.targetName ~= nil then
        local name = tostring(situation.plan.targetName)
        scene.vars = { destination = name, target = name, place = name }
    end
    if scene.stationary then
        Director.stepUp(scene, now)
        for uid in pairs(scene.ordered) do
            scene.phase = "gather"
            scene.gatherUntil = now + settings.gatherMs
            scene.nextTurnAt = scene.gatherUntil
            break
        end
    end
    if scene.phase == "talk" then scene.nextTurnAt = now + 700 end
    Director.scenes[group.key] = scene
    Director.active = Director.active + 1
    for index = 1, #scene.members do Director.inScene[scene.members[index].uid] = scene end
    state.played[picked.id] = true
    state.playedCount = state.playedCount + 1
    if state.playedCount > 40 then state.played, state.playedCount = {}, 0 end
    local gossip = ProjectALife.Gossip
    if type(gossip.notePlayed) == "function" then gossip.notePlayed(picked.slots, picked.id) end
    if type(gossip.setCooldown) == "function" then gossip.setCooldown(group.key, "ambient", scene.untilMs + 20000) end
    Director.metrics.chatterScenes = Director.metrics.chatterScenes + 1
    Director.metrics.active = Director.active
    return true, scene
end

function Director.faceTick(scene)
    local speech, speaker = ProjectALife.Speech, scene.aimSpeaker
    if speaker == nil then
        local center = scene.center
        if center == nil then
            local cx, cy = Director.centroid(scene.members)
            center = { x = cx, y = cy }
            scene.center = center
        end
        for index = 1, #scene.members do speech.face(scene.members[index].shell, center) end
        return
    end
    for index = 1, #scene.members do
        local member = scene.members[index]
        if member ~= speaker then
            speech.face(member.shell, speaker.shell)
        elseif scene.aimTarget ~= nil and scene.aimTarget ~= speaker then
            speech.face(member.shell, scene.aimTarget.shell)
        end
    end
end

function Director.aim(scene, now, speaker, target)
    scene.aimUntil = now + Director.settings.aimMs
    scene.aimSpeaker, scene.aimTarget = speaker, target
    Director.faceTick(scene)
end

function Director.arrived(scene)
    local limit = Director.settings.arriveTiles ^ 2
    for index = 1, #scene.members do
        local member = scene.members[index]
        local anchor = scene.ordered[member.uid]
        if anchor ~= nil then
            local x, y = Kit.position(member.shell)
            if x == nil or (x - anchor.x) ^ 2 + (y - anchor.y) ^ 2 > limit then return false end
        end
    end
    return true
end

function Director.hazard(member, now)
    local actor = ProjectALife.ActorRegistry.peek(member.uid)
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= member.actor.generation then return "gone" end
    member.actor = actor
    if not ProjectALife.Speech.alive(member.shell) then return "gone" end
    member.calm = nil
    local ok, why, x, y = Director.calmCheck(member, now)
    if ok then return nil end
    return why, x, y
end

function Director.alert(member, reason, x, y, now)
    if x ~= nil and y ~= nil then ProjectALife.Speech.face(member.shell, { x = x, y = y }) end
    local decisions, voice = ProjectALife.DecisionLoop, ProjectALife.Voice
    if decisions == nil or voice == nil or type(voice.play) ~= "function" then return false end
    local lines = type(decisions.dangerLines) == "table" and decisions.dangerLines or {}
    local line = lines[reason]
    if line == nil then return false end
    local seen = type(decisions.idleAlertAtMs) == "table" and decisions.idleAlertAtMs[member.uid] or nil
    if seen ~= nil and now - seen <= 15000 then return false end
    if type(decisions.idleAlertAtMs) == "table" then decisions.idleAlertAtMs[member.uid] = now end
    voice.play(member.shell, line, { context = { targetKind = reason == "zombie" and "zombie" or "player" } })
    return true
end

function Director.close(scene, now, delayMs)
    Director.release(scene)
    for index = 1, #scene.members do
        if Director.inScene[scene.members[index].uid] == scene then Director.inScene[scene.members[index].uid] = nil end
    end
    if Director.scenes[scene.key] == scene then
        Director.scenes[scene.key] = nil
        Director.active = math.max(0, Director.active - 1)
    end
    local state = Director.groups[scene.key]
    if state ~= nil then state.nextAt = now + delayMs end
    Director.metrics.active = Director.active
end

function Director.stop(scene, reason, member, x, y, now)
    local danger = Director.dangerReasons[reason] == true
    if danger then
        Director.metrics.stoppedDanger = Director.metrics.stoppedDanger + 1
        if member ~= nil then Director.alert(member, reason, x, y, now) end
    end
    Director.close(scene, now, danger and Director.settings.afterStopMs or Director.settings.dangerGapMs)
end

function Director.finish(scene, now)
    local wait = scene.startedAt + Director.gap() - now
    if wait < Director.settings.afterSceneMs then wait = Director.settings.afterSceneMs end
    Director.close(scene, now, wait)
end

function Director.stopAll(now)
    local keys = {}
    for key in pairs(Director.scenes) do keys[#keys + 1] = key end
    for index = 1, #keys do
        local scene = Director.scenes[keys[index]]
        if scene ~= nil then Director.close(scene, now, Director.settings.retryMs) end
    end
end

function Director.watch(scene, now)
    for index = 1, #scene.members do
        local member = scene.members[index]
        local reason, x, y = Director.hazard(member, now)
        if reason ~= nil then return reason, member, x, y end
    end
    if scene.stationary == false then
        local limit = Director.settings.cohesionTiles ^ 2
        local first = scene.members[1]
        for index = 2, #scene.members do
            local other = scene.members[index]
            local ax, ay = Kit.position(first.shell)
            local bx, by = Kit.position(other.shell)
            if ax == nil or bx == nil or (ax - bx) ^ 2 + (ay - by) ^ 2 > limit then return "spread", other end
        end
    end
    return nil
end

function Director.playerNear(scene, now)
    local points = Director.snapshot ~= nil and Director.snapshot.players or {}
    local first = scene.members[1]
    local x, y = Kit.position(first.shell)
    if x == nil then return false end
    local best = Director.nearestPlayer(points, x, y)
    if best ~= nil then
        scene.viewer = best
        if (best.x - x) ^ 2 + (best.y - y) ^ 2 <= Director.settings.quietPlayerTiles ^ 2 then
            scene.nearAt = now
            return true
        end
    end
    return now - scene.nearAt < Director.settings.quietPlayerMs
end

function Director.approached(scene)
    local points = Director.snapshot ~= nil and Director.snapshot.players or {}
    local limit = Director.settings.interruptTiles ^ 2
    for pIndex = 1, #points do
        for index = 1, #scene.members do
            local x, y = Kit.position(scene.members[index].shell)
            if x ~= nil and (points[pIndex].x - x) ^ 2 + (points[pIndex].y - y) ^ 2 <= limit then return true end
        end
    end
    return false
end

function Director.registerOf(member)
    if member.register == nil then
        local gossip = ProjectALife.Gossip
        member.register = type(gossip.registerOf) == "function" and gossip.registerOf({ actor = member.actor }) or ""
    end
    if member.register == "" then return nil end
    return member.register
end

function Director.armed(shell)
    if type(shell.getPrimaryHandItem) ~= "function" then return false end
    local ok, held = pcall(shell.getPrimaryHandItem, shell)
    return ok and held ~= nil
end

function Director.gestureFor(member, text, speaking)
    local speech = ProjectALife.Speech
    if speaking then
        local id, chance = speech.gestureFor(text)
        if id ~= nil and Kit.roll(100) < chance then return id end
    end
    local id = Kit.gesture(Director.registerOf(member), Director.armed(member.shell), text, speaking, Kit.roll(100))
    if id == "undecided" then return nil end
    return id
end

function Director.gesture(member, text, speaking, target)
    if target == nil then return false end
    local id = Director.gestureFor(member, text, speaking)
    if id == nil then return false end
    if ProjectALife.Speech.gestureNow(member.shell, id, target.shell) then
        Director.metrics.gestures = Director.metrics.gestures + 1
        return true
    end
    return false
end

function Director.addressee(scene, speaker)
    local slots = scene.slots
    for index = 1, #slots do
        if slots[index] == speaker then return slots[index % #slots + 1] end
    end
    return nil
end

function Director.listenerFor(scene, speaker)
    local commenter = scene.commenter
    if commenter ~= nil and commenter ~= speaker and Kit.roll(100) < 60 then return commenter end
    local member = scene.members[Kit.roll(#scene.members) + 1]
    if member == nil or member == speaker or member == scene.silent then return nil end
    return member
end

function Director.turn(scene, now)
    local index = scene.turnIndex + 1
    local turn = scene.turns[index]
    if turn == nil then
        scene.phase = "outro"
        scene.endsAt = now + 1500
        return
    end
    scene.turnIndex = index
    local slots = scene.slots
    local speaker = slots[tonumber(turn.s) or 1] or slots[(index - 1) % #slots + 1]
    local speech = ProjectALife.Speech
    local rendered, text = pcall(speech.render, turn.t, scene.vars, speaker.shell, nil)
    local spoke = rendered and type(text) == "string" and speech.say(speaker.shell, text, { chat = true, scope = "ambient" }) == true
    if not spoke then
        scene.nextTurnAt = now + 900
        return
    end
    Director.metrics.chatterBarks = Director.metrics.chatterBarks + 1
    if speaker == scene.commenter then Director.metrics.comments = Director.metrics.comments + 1 end
    scene.nextTurnAt = now + Kit.turnMs(text) + 280
    if scene.stationary then
        local target = Director.addressee(scene, speaker)
        Director.aim(scene, now, speaker, target)
        Director.gesture(speaker, text, true, target)
        local listener = Director.listenerFor(scene, speaker)
        if listener ~= nil then Director.gesture(listener, text, false, speaker) end
    end
end

function Director.step(scene, now)
    if now >= scene.nextHazardAt then
        scene.nextHazardAt = now + Director.settings.hazardEveryMs
        local reason, member, x, y = Director.watch(scene, now)
        if reason ~= nil then
            Director.stop(scene, reason, member, x, y, now)
            return
        end
        if not Director.playerNear(scene, now) then
            Director.close(scene, now, Director.settings.retryMs)
            return
        end
        if Director.approached(scene) then
            Director.metrics.approached = Director.metrics.approached + 1
            Director.close(scene, now, Director.settings.approachGapMs)
            return
        end
    end
    if now >= scene.untilMs + 3000 then
        Director.finish(scene, now)
        return
    end
    if scene.phase == "gather" then
        if now >= scene.gatherUntil or Director.arrived(scene) then
            scene.phase = "talk"
            Director.aim(scene, now, nil, nil)
            scene.nextTurnAt = now + 500
        end
    elseif scene.phase == "talk" or scene.phase == "outro" then
        if scene.stationary and now < scene.aimUntil then Director.faceTick(scene) end
        if scene.phase == "talk" then
            if now >= scene.nextTurnAt then Director.turn(scene, now) end
        elseif now >= scene.endsAt then
            Director.finish(scene, now)
        end
    end
end

function Director.play(now)
    local keys = Director.playKeys
    for index = #keys, 1, -1 do keys[index] = nil end
    for key in pairs(Director.scenes) do keys[#keys + 1] = key end
    for index = 1, #keys do
        local scene = Director.scenes[keys[index]]
        if scene ~= nil then Director.step(scene, now) end
    end
    return #keys + Director.flush(now)
end

function Director.cooled(map, key, now, hours)
    local entry = map[key]
    return entry == nil or (now >= entry.untilMs and hours >= entry.untilHours)
end

function Director.stamp(map, key, untilMs, untilHours)
    map[key] = { untilMs = untilMs, untilHours = untilHours }
end

function Director.sees(shell, player)
    local careful = ProjectALife.ModuleCareful
    if careful == nil or type(careful.lineOfSight) ~= "function" then return true end
    return careful.lineOfSight(shell, player) == true
end

function Director.presenceBlocks(actor, player, now)
    local presence = ProjectALife.ModuleTalkPresence
    local speech = ProjectALife.Speech
    if presence == nil or type(presence.partyKey) ~= "function" then return false end
    local playerKey = speech.playerKey(player)
    if playerKey == nil then return false end
    local party = presence.partyKey(actor, playerKey)
    local key = tostring(playerKey) .. ":" .. tostring(actor.uid)
    return now < (presence.greeted[party] or 0) or now < (presence.greeted[key] or 0)
end

function Director.greetPlayer(entry, point, distance, rule, now)
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    local player = point.player
    local context = speech.contextFor(entry.actor, player)
    context.stance = talk.stance(entry.actor, player)
    local first, second = "PASSING_PLAYER", "GREET_PLAYER"
    if distance <= Director.settings.greetTalkTiles and Kit.roll(100) < 55 then first, second = second, first end
    local said = talk.bark(entry.actor, entry.shell, player, first, context)
    if said == nil then
        Director.noScene(first, "no_line")
        said = talk.bark(entry.actor, entry.shell, player, second, context)
        if said == nil then Director.noScene(second, "no_line") end
    end
    if said == nil then return false end
    Director.metrics.passingGreets = Director.metrics.passingGreets + 1
    Director.metrics.chatterBarks = Director.metrics.chatterBarks + 1
    if type(talk.awaitAnswer) == "function" then talk.awaitAnswer(entry.actor, player, said, now) end
    if rule.gesture ~= nil and Kit.roll(100) < rule.gestureChance then
        if speech.gestureNow(entry.shell, rule.gesture, player) then
            Director.metrics.gestures = Director.metrics.gestures + 1
        end
    end
    local presence = ProjectALife.ModuleTalkPresence
    local playerKey = speech.playerKey(player)
    if presence ~= nil and playerKey ~= nil and type(presence.partyKey) == "function" then
        local memory = type(entry.actor.memory) == "table" and entry.actor.memory or {}
        presence.greeted[presence.partyKey(entry.actor, playerKey)] = now + presence.settings.greetCooldownMs
        presence.passed[tostring(memory.groupId or entry.actor.uid) .. ":" .. tostring(playerKey)] =
            now + presence.settings.passCooldownMs
    end
    return true
end

function Director.passPlayers(snapshot, now)
    local percent = Kit.passingPercent()
    if percent <= 0 then return 0 end
    local settings, talk, speech = Director.settings, ProjectALife.Talk, ProjectALife.Speech
    if talk == nil or type(talk.stance) ~= "function" or type(talk.bark) ~= "function" then return 0 end
    local scale = percent / 70
    local near2, far2 = settings.greetNearTiles ^ 2, settings.greetFarTiles ^ 2
    local done, hours = 0, Gate.worldHours()
    for pIndex = 1, #snapshot.players do
        local point = snapshot.players[pIndex]
        local playerKey = speech.playerKey(point.player)
        local list = {}
        for _, entry in pairs(snapshot.entries) do
            if entry.key ~= nil or entry.solo then
                local d2 = (entry.x - point.x) ^ 2 + (entry.y - point.y) ^ 2
                if d2 >= near2 and d2 <= far2 and math.abs(entry.z - point.z) < 3 then
                    list[#list + 1] = { entry = entry, d2 = d2 }
                end
            end
        end
        table.sort(list, function(a, b)
            if a.d2 ~= b.d2 then return a.d2 < b.d2 end
            return a.entry.uid < b.entry.uid
        end)
        local checked = 0
        for index = 1, #list do
            if checked >= settings.greetEvaluate then break end
            local entry = list[index].entry
            local key = tostring(playerKey) .. ":" .. entry.uid
            local groupKey = tostring(playerKey) .. ":" .. tostring(entry.key or entry.uid)
            local ready = Director.inScene[entry.uid] == nil
                and Director.cooled(Director.playerGreeted, key, now, hours)
                and Director.cooled(Director.groupGreeted, groupKey, now, hours)
            if ready then
                checked = checked + 1
                if Director.sees(entry.shell, point.player) then
                    done = done + Director.greetEntry(entry, point, math.sqrt(list[index].d2), key, groupKey, scale, now, hours)
                end
            end
        end
    end
    return done
end

function Director.greetEntry(entry, point, distance, key, groupKey, scale, now, hours)
    local settings = Director.settings
    local stance = ProjectALife.Talk.stance(entry.actor, point.player)
    local rule = Kit.greetRule(stance)
    if rule == nil or Director.presenceBlocks(entry.actor, point.player, now) or not Director.calm(entry, now) then
        return 0
    end
    if Kit.roll(100) >= math.min(100, rule.chance * scale) then
        Director.stamp(Director.playerGreeted, key, now + settings.greetRetryMs, hours)
        return 0
    end
    if not Director.greetPlayer(entry, point, distance, rule, now) then
        Director.stamp(Director.playerGreeted, key, now + settings.greetRetryMs, hours)
        return 0
    end
    Director.stamp(Director.playerGreeted, key, now + settings.greetFloorMs, hours + rule.minutes / 60)
    Director.stamp(Director.groupGreeted, groupKey, now + settings.greetGroupMs, hours)
    return 1
end

function Director.unitOf(group)
    local count, cx, cy, radius = #group.members, 0, 0, 0
    for index = 1, count do cx, cy = cx + group.members[index].x, cy + group.members[index].y end
    cx, cy = cx / count, cy / count
    for index = 1, count do
        local d = math.sqrt((group.members[index].x - cx) ^ 2 + (group.members[index].y - cy) ^ 2)
        if d > radius then radius = d end
    end
    return { key = group.key, members = group.members, cx = cx, cy = cy, radius = radius }
end

function Director.pairDistance2(a, b)
    local best = nil
    for left = 1, #a.members do
        for right = 1, #b.members do
            local d2 = (a.members[left].x - b.members[right].x) ^ 2 + (a.members[left].y - b.members[right].y) ^ 2
            if best == nil or d2 < best.d2 then best = { d2 = d2, left = a.members[left], right = b.members[right] } end
        end
    end
    return best
end

function Director.passingStance(a, b)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.status) ~= "function" then return true end
    local one, two = relations.status(a.actor, b.actor), relations.status(b.actor, a.actor)
    local ok = { friendly = true, allied = true, neutral = true }
    return ok[one] == true and ok[two] == true
end

function Director.greetNpc(speaker, other, now)
    local speech = ProjectALife.Speech
    local face = nil
    if not Director.isMoving(speaker) then face = other.shell end
    local text = speech.bark(speaker.actor, speaker.shell, "PASSING_NPC_GREET", { face = face })
    if text == nil then
        Director.noScene("PASSING_NPC_GREET", "no_line")
        return false
    end
    Director.metrics.passingNpcGreets = Director.metrics.passingNpcGreets + 1
    Director.metrics.chatterBarks = Director.metrics.chatterBarks + 1
    if face ~= nil and Kit.roll(100) < 45 then
        if speech.gestureNow(speaker.shell, "yes", other.shell) then
            Director.metrics.gestures = Director.metrics.gestures + 1
        end
    end
    return true
end

function Director.passNpcs(snapshot, now)
    local percent = Kit.passingPercent()
    if percent <= 0 then return 0 end
    local settings = Director.settings
    local units, audible = {}, settings.startRadius ^ 2
    for _, group in pairs(snapshot.groups) do
        if group.d2 <= audible then units[#units + 1] = Director.unitOf(group) end
    end
    for index = 1, #snapshot.solos do
        local entry = snapshot.solos[index]
        if entry.d2 <= audible then
            units[#units + 1] = { key = "solo:" .. entry.uid, members = { entry }, cx = entry.x, cy = entry.y, radius = 0 }
        end
    end
    table.sort(units, function(a, b) return a.key < b.key end)
    local reach, done = settings.passNpcTiles, 0
    for left = 1, #units - 1 do
        local a = units[left]
        for right = left + 1, #units do
            local b = units[right]
            local span = reach + a.radius + b.radius
            local dx, dy = a.cx - b.cx, a.cy - b.cy
            if dx * dx + dy * dy <= span * span then
                local pairKey = a.key .. "|" .. b.key
                if now >= (Director.pairGreeted[pairKey] or 0) then
                    local best = Director.pairDistance2(a, b)
                    if best.d2 <= reach * reach and math.abs(best.left.z - best.right.z) < 2 then
                        done = done + Director.meetPair(a, b, best, pairKey, percent, now)
                    end
                end
            end
        end
    end
    return done
end

function Director.meetPair(a, b, best, pairKey, percent, now)
    local settings = Director.settings
    local one, two = best.left, best.right
    if Director.inScene[one.uid] ~= nil or Director.inScene[two.uid] ~= nil then return 0 end
    if not (Director.calm(one, now) and Director.calm(two, now)) then
        Director.pairGreeted[pairKey] = now + 15000
        return 0
    end
    if not Director.passingStance(one, two) then
        Director.pairGreeted[pairKey] = now + settings.passNpcCooldownMs
        return 0
    end
    if Kit.roll(100) >= percent or not Director.greetNpc(one, two, now) then
        Director.pairGreeted[pairKey] = now + 60000
        return 0
    end
    Director.pairGreeted[pairKey] = now + settings.passNpcCooldownMs + Kit.roll(120000)
    Director.later(settings.passNpcAnswerMs + Kit.roll(700), function()
        Director.greetNpc(two, one, Director.nowMs())
    end, now)
    Director.watchMeeting(a, b, now)
    return 1
end

function Director.watchMeeting(a, b, now)
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.probeMeeting) ~= "function" or a.members[1].key == nil or b.members[1].key == nil then return end
    Director.meetWatch[a.key .. "|" .. b.key] = { untilMs = now + Director.settings.meetWatchMs, a = a.key, b = b.key }
end

function Director.probeMeetings(snapshot, now)
    local gossip = ProjectALife.Gossip
    for key, watch in pairs(Director.meetWatch) do
        local group = snapshot.groups[watch.a]
        local other = snapshot.groups[watch.b]
        if now >= watch.untilMs or group == nil or other == nil then
            Director.meetWatch[key] = nil
        else
            local member = group.members[1]
            if Director.calm(member, now) then
                Director.metrics.meetProbes = Director.metrics.meetProbes + 1
                pcall(gossip.probeMeeting, member.shell, { groupId = watch.a, now = now })
            end
        end
    end
end

function Director.haltMeetings(now)
    local gossip, decisions = ProjectALife.Gossip, ProjectALife.DecisionLoop
    if gossip == nil or decisions == nil or type(decisions.stopNow) ~= "function" or type(gossip.active) ~= "table" then return 0 end
    local halted = 0
    for _, state in pairs(gossip.active) do
        if state.meeting == true and state.haltedAtMs == nil and type(state.meetingMembers) == "table" then
            state.haltedAtMs = now
            for index = 1, #state.meetingMembers do
                local uid = state.meetingMembers[index].uid
                local ok, stopped = false, false
                if uid ~= nil then ok, stopped = pcall(decisions.stopNow, uid, now) end
                if ok and stopped == true then halted = halted + 1 end
            end
            Director.metrics.meetHalts = Director.metrics.meetHalts + 1
        end
    end
    return halted
end

function Director.dispatch(snapshot, now)
    local settings = Director.settings
    local work = 0
    local gossip = ProjectALife.Gossip
    if Director.active < Kit.maxConcurrent() then
        local best, bestD2 = nil, nil
        for _, group in pairs(snapshot.groups) do
            local state = Director.stateFor(group.key, now)
            if now >= state.nextAt and Director.scenes[group.key] == nil and #group.members >= 2
                    and gossip.active[group.key] == nil
                    and group.d2 <= settings.startRadius ^ 2 and (bestD2 == nil or group.d2 < bestD2) then
                best, bestD2 = group, group.d2
            end
        end
        if best ~= nil then
            local started = Director.begin(best, Director.stateFor(best.key, now), now)
            if started then work = work + 1 end
        end
    else
        for _, group in pairs(snapshot.groups) do Director.stateFor(group.key, now) end
    end
    Director.scanTurn = Director.scanTurn + 1
    if Director.scanTurn % 3 == 0 then work = work + Director.passNpcs(snapshot, now) end
    work = work + Director.passPlayers(snapshot, now)
    Director.probeMeetings(snapshot, now)
    if type(gossip.tickServer) == "function" then gossip.tickServer(now) end
    Director.haltMeetings(now)
    return work
end

function Director.prune(now)
    for key, state in pairs(Director.groups) do
        if Director.scenes[key] == nil and now - (state.seenAt or 0) > Director.settings.stateKeepMs then
            Director.groups[key] = nil
        end
    end
    local hours = Gate.worldHours()
    for _, map in ipairs({ Director.playerGreeted, Director.groupGreeted }) do
        for key, entry in pairs(map) do
            if now >= entry.untilMs and hours >= entry.untilHours then map[key] = nil end
        end
    end
    for key, untilMs in pairs(Director.pairGreeted) do
        if untilMs <= now then Director.pairGreeted[key] = nil end
    end
end

function Director.scan(now)
    Director.metrics.scans = Director.metrics.scans + 1
    if now >= Director.nextPumpAt then
        Director.nextPumpAt = now + Director.settings.pumpMs
        Director.pump()
    end
    local players = Director.playerPoints(now)
    local snapshot = { at = now, players = players, entries = {}, groups = {}, solos = {}, count = 0 }
    Director.snapshot = snapshot
    local watchdog, registry, gossip = ProjectALife.Watchdog, ProjectALife.ActorRegistry, ProjectALife.Gossip
    if #players == 0 or watchdog == nil or registry == nil or type(watchdog.order) ~= "table" then return 0 end
    local limit = Director.settings.scanRadius ^ 2
    for index = 1, #watchdog.order do
        if snapshot.count >= Director.settings.scanCap then break end
        local uid = watchdog.order[index]
        local binding = watchdog.bindings[uid]
        local shell = binding ~= nil and binding.shell or nil
        local actor = shell ~= nil and registry.peek(uid) or nil
        if actor ~= nil and actor.lifecycle == "active" then
            local x, y, z = Kit.position(shell)
            local point, d2
            if x ~= nil then point, d2 = Director.nearestPlayer(players, x, y) end
            if point ~= nil and d2 <= limit then
                local entry = { uid = uid, actor = actor, shell = shell, x = x, y = y, z = z, d2 = d2, player = point }
                snapshot.count = snapshot.count + 1
                snapshot.entries[uid] = entry
                local memory = type(actor.memory) == "table" and actor.memory or {}
                if memory.outpostId == nil then
                    if memory.groupId ~= nil and memory.groupId ~= "" then
                        local key = gossip.groupKey(actor)
                        entry.key = key
                        local group = snapshot.groups[key]
                        if group == nil then
                            group = { key = key, members = {}, d2 = d2 }
                            snapshot.groups[key] = group
                        end
                        group.members[#group.members + 1] = entry
                        if d2 < group.d2 then group.d2 = d2 end
                    else
                        entry.solo = true
                        snapshot.solos[#snapshot.solos + 1] = entry
                    end
                end
            end
        end
    end
    if now >= Director.nextPruneAt then
        Director.nextPruneAt = now + Director.settings.pruneMs
        Director.prune(now)
    end
    return Director.dispatch(snapshot, now)
end

function Director.tick(now)
    now = tonumber(now) or Director.nowMs()
    if not Director.enabled() then
        if Director.active > 0 then Director.stopAll(now) end
        Director.snapshot = nil
        return 0
    end
    local work = 0
    if now >= Director.nextPlayAt then
        Director.nextPlayAt = now + Director.settings.playMs
        work = work + Director.play(now)
    end
    if now >= Director.nextScanAt then
        Director.nextScanAt = now + Director.settings.scanMs
        work = work + Director.scan(now)
    end
    return work
end

function Director.ownsAmbient(shell)
    local snapshot = Director.snapshot
    if snapshot == nil or not Director.enabled() or Director.nowMs() - snapshot.at > 4000 then return false end
    local uid = ProjectALife.Speech.variable(shell, "ALifeUID")
    local entry = uid ~= nil and snapshot.entries[tostring(uid)] or nil
    if entry == nil or entry.key == nil then return false end
    local group = snapshot.groups[entry.key]
    return group ~= nil and #group.members >= 2
end

function Director.reset()
    Director.groups, Director.scenes, Director.inScene, Director.active = {}, {}, {}, 0
    Director.snapshot, Director.nextScanAt, Director.nextPlayAt, Director.nextPruneAt = nil, 0, 0, 0
    Director.nextPumpAt = 0
    Director.scanTurn = 0
    Director.groupGreeted, Director.playerGreeted, Director.pairGreeted = {}, {}, {}
    Director.meetWatch, Director.queue, Director.playKeys = {}, {}, {}
    Director.metrics = {
        chatterScenes = 0, chatterBarks = 0, passingGreets = 0, passingNpcGreets = 0, refusedDanger = 0,
        stoppedDanger = 0, noSceneAvailable = {}, comments = 0, gestures = 0, stepUps = 0, scans = 0,
        requests = 0, meetProbes = 0, meetHalts = 0, approached = 0, active = 0,
    }
end

return Director
