require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Activities/ALifeFishing"
require "ProjectALife/Activities/ALifeHunting"
require "ProjectALife/Combat/ALifeCombatFire"
require "ProjectALife/Core/ALifePlayerLocator"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Catalog = ProjectALife.ActivityCatalog
local Fish = ProjectALife.ActivityFishing
local Hunt = ProjectALife.ActivityHunting

local Activity = {
    hunting = setmetatable({}, { __mode = "k" }),

    handlers = {},
    metrics = { evaluations = 0, claimed = 0, notDriven = 0, reports = 0, calmDropped = 0 },
}
ProjectALife.ModuleActivity = Activity

function Activity.drives(shell)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.drivesBody) ~= "function" then return false end
    return fence.drivesBody(shell) == true
end

function Activity.report(actor, context, kind)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" or type(kind) ~= "string" or type(context) ~= "table"
            or type(context.persistMemory) ~= "function" then return false end
    context.persistMemory(actor, "activityEvent", { kind = kind, seq = tonumber(memory.activitySeq) or 0 })
    Activity.metrics.reports = Activity.metrics.reports + 1
    return true
end

function Activity.dropStaleCalm(actor, memory, context)
    if memory.stanceAwareness == nil or memory.activityId == "hold" or memory.nightCamp == true
            or memory.nightHoldAwarenessHome ~= nil then return false end
    if memory.stance ~= nil and memory.stance ~= "" then return false end
    if type(context) ~= "table" or type(context.persistMemory) ~= "function" then return false end
    context.persistMemory(actor, "stanceAwareness", nil)
    Activity.metrics.calmDropped = Activity.metrics.calmDropped + 1
    return true
end

function Activity.evaluate(actor, shell, context)
    local memory = actor.memory
    local animations = ProjectALife.Animations
    if Activity.hunting[shell] ~= nil and (type(memory) ~= "table" or memory.activityId ~= "hunt"
            or not Hunt.liveEnabled() or context.threat ~= nil or not Activity.drives(shell)) then
        Activity.hunting[shell] = nil
        if Activity.drives(shell) and animations ~= nil and type(animations.clear) == "function" then animations.clear(shell) end
    end
    if (type(memory) ~= "table" or memory.activityId ~= "fish" or not Fish.enabled()) and animations ~= nil
            and type(animations.isFishing) == "function" and animations.isFishing(shell)
            and type(animations.clear) == "function" and Activity.drives(shell) then animations.clear(shell) end
    if type(memory) ~= "table" or memory.activityId == nil then return nil end
    local handler = Activity.handlers[memory.activityId]
    if handler == nil and memory.stanceAwareness == nil then return nil end
    Activity.metrics.evaluations = Activity.metrics.evaluations + 1
    if not Catalog.enabled() then return nil end
    if not Activity.drives(shell) then
        if animations ~= nil and type(animations.fishing) == "table" then animations.fishing[shell] = nil end
        Activity.metrics.notDriven = Activity.metrics.notDriven + 1
        return nil
    end
    if memory.stanceAwareness ~= nil then Activity.dropStaleCalm(actor, memory, context) end
    if handler == nil then return nil end
    local decision = handler(actor, shell, context)
    if decision ~= nil then Activity.metrics.claimed = Activity.metrics.claimed + 1 end
    return decision
end

function Activity.fishCancelled(actor)
    local memory = actor.memory
    local event = type(memory) == "table" and memory.activityEvent or nil
    return type(event) == "table" and event.kind == "done" and tonumber(event.seq) == (tonumber(memory.activitySeq) or 0)
end

function Activity.fishNoticed(actor, shell, context)
    local caution = ProjectALife.Caution
    if context.threat ~= nil or Activity.fishCancelled(actor) then return true end
    if caution == nil or type(caution.idleDanger) ~= "function" then return false end
    return caution.idleDanger(actor, shell, tonumber(context.now)) ~= nil
end

function Activity.fishCancel(actor, context)
    if Activity.fishCancelled(actor) then return false end
    return Activity.report(actor, context, "done")
end

function Activity.fish(actor, shell, context)
    local animations = ProjectALife.Animations
    if not Fish.enabled() or Activity.fishNoticed(actor, shell, context) then
        if animations ~= nil and type(animations.isFishing) == "function" and animations.isFishing(shell)
                and type(animations.clear) == "function" then animations.clear(shell) end
        if Fish.enabled() then Activity.fishCancel(actor, context) end
        return nil
    end
    local memory = actor.memory
    local state = type(memory.activityState) == "table" and memory.activityState.activity or nil
    local session = type(state) == "table" and state.fishing or nil
    local work = type(session) == "table" and type(session.work) == "table" and session.work[tostring(actor.uid)] or nil
    if work == nil or state.seq ~= memory.activitySeq or shell == nil
            or type(shell.getX) ~= "function" or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function" then
        if animations ~= nil and type(animations.isFishing) == "function" and animations.isFishing(shell)
                and type(animations.clear) == "function" then animations.clear(shell) end
        return nil
    end
    local post = work.post
    local here = { lifecycle = "active", worldPosition = { x = shell:getX(), y = shell:getY(), z = shell:getZ() } }
    if not Fish.atPost(here, post) then
        if animations ~= nil and type(animations.isFishing) == "function" and animations.isFishing(shell)
                and type(animations.clear) == "function" then animations.clear(shell) end
        if type(context.startMovement) ~= "function" then return nil end
        return context.startMovement(actor, shell, post, "activity_fish", {
            pace = "walk", timeoutMs = 15000, doorsOnly = true, tolerance = 0.55,
        })
    end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.faceAimPoint) == "function" then
        fence.faceAimPoint(shell, post.waterX, post.waterY, tonumber(context.now))
    end
    if work.watch == true and animations ~= nil and type(animations.isFishing) == "function"
            and animations.isFishing(shell) and type(animations.clear) == "function" then animations.clear(shell) end
    if work.watch ~= true and animations ~= nil and type(animations.fishCycle) == "function" then
        animations.fishCycle(shell, tonumber(context.now))
    end
    local intent = work.watch == true and "fishing_watch" or "fishing"
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", intent) end
    return { kind = "idle", intent = intent, cooldownUntilMs = (tonumber(context.now) or 0) + 1200 }
end

Activity.handlers.fish = Activity.fish

function Activity.haven(actor)
    local havens = ProjectALife.Havens
    local found = havens ~= nil and type(havens.of) == "function" and havens.of(actor.memory.havenId) or nil
    if found ~= nil then return found end
    return Activity.remoteHaven(actor)
end

function Activity.remoteHaven(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    local executor = ProjectALife.Executor
    if type(memory) ~= "table" or type(memory.havenId) ~= "string" or type(memory.supplyDepot) ~= "table"
            or executor == nil or type(executor.clientAuthority) ~= "function" or not executor.clientAuthority() then
        return nil
    end
    local x, y = tonumber(memory.supplyDepot.x), tonumber(memory.supplyDepot.y)
    if x == nil or y == nil then return nil end
    return { id = memory.havenId, remote = true, depot = { x = x, y = y, z = tonumber(memory.supplyDepot.z) or 0 } }
end

function Activity.returnBase(actor, shell, context)
    local haven = Activity.haven(actor)
    if haven == nil then
        Activity.report(actor, context, "failed")
        return nil
    end
    if type(shell.getX) ~= "function" or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function" then return nil end
    local depot = haven.depot
    local near = (shell:getX() - depot.x) ^ 2 + (shell:getY() - depot.y) ^ 2 <= 6.25
        and math.floor(shell:getZ()) == math.floor(depot.z)
    if not near then
        if type(context.startMovement) ~= "function" then return nil end
        return context.startMovement(actor, shell, depot, "activity_haven", {
            pace = "walk", timeoutMs = 20000, doorsOnly = true, tolerance = 1.5,
        })
    end
    if haven.remote == true then
        if type(context.persistMemory) == "function" then
            context.persistMemory(actor, "havenVisit", tonumber(actor.memory.activitySeq) or 0)
        end
        Activity.report(actor, context, "done")
        return { kind = "idle", intent = "haven_arrived", cooldownUntilMs = (tonumber(context.now) or 0) + 1200 }
    end
    local scavenging = ProjectALife.Scavenging
    local container = ProjectALife.Havens.containerAt(depot)
    local moved = 0
    local stash = ProjectALife.Stash
    if container ~= nil and stash ~= nil and type(stash.depositFrom) == "function" then
        local ok, stashed = pcall(stash.depositFrom, actor, container)
        if ok then moved = type(stashed) == "number" and stashed or (stashed == true and 1 or 0) end
    end
    if moved == 0 and container ~= nil and scavenging ~= nil and type(scavenging.deposit) == "function" then
        moved = scavenging.deposit(shell, container, 4) or 0
    end
    if moved > 0 then
        ProjectALife.Havens.arrive(haven, ProjectALife.Havens.hours(), moved)
        return { kind = "idle", intent = "deposit_supplies", cooldownUntilMs = (tonumber(context.now) or 0) + 1600 }
    end
    ProjectALife.Havens.arrive(haven, ProjectALife.Havens.hours(), 0)
    Activity.report(actor, context, "done")
    return { kind = "idle", intent = "haven_arrived", cooldownUntilMs = (tonumber(context.now) or 0) + 1200 }
end

Activity.handlers.return_base = Activity.returnBase

function Activity.havenIdle(actor, shell, context)
    local haven = Activity.haven(actor)
    if haven == nil then
        Activity.report(actor, context, "failed")
        return nil
    end
    if type(shell.getX) ~= "function" or type(shell.getY) ~= "function" then return nil end
    local depot = haven.depot
    if (shell:getX() - depot.x) ^ 2 + (shell:getY() - depot.y) ^ 2 > 64 and type(context.startMovement) == "function" then
        return context.startMovement(actor, shell, depot, "activity_haven", {
            pace = "walk", timeoutMs = 20000, doorsOnly = true, tolerance = 3,
        })
    end
    local camp, animations = ProjectALife.CampLife, ProjectALife.Animations
    if haven.remote ~= true and camp ~= nil and animations ~= nil and type(animations.apply) == "function" then
        local now = tonumber(context.now) or 0
        camp.render(haven, now)
        local chore = camp.choreFor(actor, now)
        local station = camp.station(haven, actor)
        if (shell:getX() - station.x) ^ 2 + (shell:getY() - station.y) ^ 2 > 4 and type(context.startMovement) == "function" then
            return context.startMovement(actor, shell, station, "activity_haven", {
                pace = "walk", timeoutMs = 12000, doorsOnly = true, tolerance = 1.5,
            })
        end
        Activity.workLook(actor, shell, camp.presets[chore], now)
        if type(context.setActivity) == "function" then context.setActivity(actor, "idle", chore) end
        return { kind = "idle", intent = chore, cooldownUntilMs = now + 2000 }
    end
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "haven_idle") end
    return { kind = "idle", intent = "haven_idle", cooldownUntilMs = (tonumber(context.now) or 0) + 2000 }
end

Activity.handlers.haven_idle = Activity.havenIdle

function Activity.huntReload(state, shell, gun, now)
    local weapons, magazines, relay, combat, animations = ProjectALife.Weapons, ProjectALife.MagazineState,
        ProjectALife.NPCHitRelay, ProjectALife.Combat, ProjectALife.Animations
    if state.reload == nil then
        local transaction = weapons.beginReload(shell, gun)
        if transaction == nil then return false end
        local settings = combat.settings or {}
        local duration = settings.reloadMs or 2500
        if transaction.internal then
            duration = (settings.internalReloadMs or 650) + math.max(0, transaction.rounds - 1) * (settings.internalReloadPerRoundMs or 950)
        end
        local preset = combat.loopReloadPresetFor(shell, gun) or combat.reloadPresetFor(shell, gun)
        state.reload = { transaction = transaction, insert = now + duration * (transaction.internal and 0.82 or 0.55), finish = now + duration }
        relay.reload(shell, gun, false)
        combat.cancelPath(shell)
        animations.apply(shell, preset)
    end
    local reload = state.reload
    if not reload.committed and now >= reload.insert then
        if not magazines.commitReload(reload.transaction) then state.reload = nil; return false end
        reload.committed = true
        relay.reload(shell, gun, true)
    end
    if now < reload.finish then return true end
    if not reload.racked and weapons.racksAfterReload(gun) then
        reload.racked = true
        reload.finish = now + ((combat.settings or {}).rackMs or 550)
        animations.apply(shell, combat.rackPresetFor(shell, gun, "reload"))
        return true
    end
    state.reload, state.aimAt = nil, nil
    return true
end

function Activity.hunt(actor, shell, context)
    if context.threat ~= nil or not Hunt.liveEnabled() then return nil end
    local memory = actor.memory
    local stateRecord = type(memory.activityState) == "table" and memory.activityState.activity or nil
    local session = type(stateRecord) == "table" and stateRecord.hunting or nil
    local work = type(session) == "table" and type(session.work) == "table" and session.work[tostring(actor.uid)] or nil
    if work == nil or stateRecord.seq ~= memory.activitySeq or work.generation ~= actor.generation then return nil end
    local here, now = Hunt.point(shell), tonumber(context.now) or 0
    if here == nil or type(session.anchor) ~= "table" then return nil end
    local state = Activity.hunting[shell]
    if state == nil or state.seq ~= memory.activitySeq or state.generation ~= actor.generation then
        state = { seq = memory.activitySeq, generation = actor.generation, nextScan = 0 }
        Activity.hunting[shell] = state
    end
    local weapons, magazines, relay, combat, animations, locator = ProjectALife.Weapons, ProjectALife.MagazineState,
        ProjectALife.NPCHitRelay, ProjectALife.Combat, ProjectALife.Animations, ProjectALife.PlayerLocator
    if weapons == nil or magazines == nil or relay == nil or combat == nil or animations == nil
            or locator == nil or type(locator.list) ~= "function" then return nil end
    local idle = { kind = "idle", intent = "hunting", cooldownUntilMs = now + 250 }
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "hunting") end
    if (here.x - session.anchor.x) ^ 2 + (here.y - session.anchor.y) ^ 2 > 1600 then
        state.target, state.aimAt = nil, nil
        if type(context.startMovement) ~= "function" then return idle end
        return context.startMovement(actor, shell, session.anchor, "activity_hunt_return", { pace = "walk", doorsOnly = true, tolerance = 1 })
    end
    if work.watch == true then
        local position = tonumber(work.index) or tonumber(memory.groupIndex) or 1
        local angle = position * math.pi * 2 / math.max(1, tonumber(session.memberCount) or 1)
        local post = { x = session.anchor.x + math.cos(angle) * 12, y = session.anchor.y + math.sin(angle) * 12, z = session.anchor.z }
        if (here.x - post.x) ^ 2 + (here.y - post.y) ^ 2 > 1 and type(context.startMovement) == "function" then
            return context.startMovement(actor, shell, post, "activity_hunt_watch", { pace = "walk", doorsOnly = true, tolerance = 0.8 })
        end
        return idle
    end
    if not Hunt.available(session) then return idle end
    if not relay.ready(shell) then
        state.reload, state.aimAt, state.target = nil, nil, nil
        return idle
    end
    local gun = weapons.current(shell)
    if gun == nil or type(gun.getFullType) ~= "function" or gun:getFullType() ~= work.weapon then
        gun = weapons.bestReloadableRanged(shell)
        if gun == nil or type(gun.getFullType) ~= "function" or gun:getFullType() ~= work.weapon
                or not weapons.select(shell, gun, weapons.slot(gun)) then
            Activity.report(actor, context, "failed")
            return idle
        end
    end
    if state.weapon ~= nil and state.weapon ~= gun then state.reload, state.aimAt, state.target = nil, nil, nil end
    state.weapon = gun
    relay.select(shell, gun)
    if state.reload ~= nil or magazines.current(gun) <= 0 then
        if not Activity.huntReload(state, shell, gun, now) then Activity.report(actor, context, "failed") end
        return idle
    end
    local players = Hunt.players()
    if state.target ~= nil and (not Hunt.available(session, state.target)
            or not Hunt.safeTarget(shell, state.target, players, 60)) then state.target, state.aimAt = nil, nil end
    if state.target == nil and now >= state.nextScan then
        state.target, state.nextScan, state.aimAt = Hunt.nearest(shell, players, session), now + 3000, nil
    end
    local animal = state.target
    if animal == nil or type(gun.getMaxRange) ~= "function" then return idle end
    local target = Hunt.point(animal)
    local dx, dy = target.x - here.x, target.y - here.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local reach = math.max(1, math.min(18, (tonumber(gun:getMaxRange()) or 0) - 0.5))
    if distance > reach then
        state.aimAt = nil
        local post = { x = target.x - dx / distance * reach, y = target.y - dy / distance * reach, z = target.z }
        if (post.x - session.anchor.x) ^ 2 + (post.y - session.anchor.y) ^ 2 > 1600 then
            Activity.report(actor, context, "failed")
            return idle
        end
        if type(context.startMovement) ~= "function" then return idle end
        return context.startMovement(actor, shell, post, "activity_hunt_stalk", { pace = "walk", doorsOnly = true, tolerance = 0.4 })
    end
    combat.cancelPath(shell)
    if type(shell.faceLocationF) == "function" then shell:faceLocationF(target.x, target.y) end
    if now < (tonumber(state.shotUntil) or 0) then return idle end
    animations.apply(shell, combat.readyPresetFor(shell, gun, animal))
    if state.aimAt == nil or now < state.aimAt then state.aimAt = now end
    if now - state.aimAt < 1500 or now < (tonumber(state.nextShot) or 0)
            or now - (tonumber(session.lastKillMs) or -60000) < 60000 then return idle end
    if type(animal.getOnlineID) ~= "function" or not Hunt.safeTarget(shell, animal, players, math.min(25, reach + 0.5)) then return idle end
    relay.beginAttack(shell)
    if not magazines.consumeRound(shell, gun) then return idle end
    local message = { uid = actor.uid, generation = actor.generation, seq = memory.activitySeq,
        weapon = work.weapon, attack = relay.attacks[shell], animal = animal:getOnlineID() }
    if type(isClient) == "function" and isClient() then
        if not relay.prepareAttack(shell, gun) or type(sendClientCommand) ~= "function" then return idle end
        sendClientCommand("ProjectALife", "executorHuntShot", message)
    else
        local watchdog, service = ProjectALife.Watchdog, ProjectALife.ActivityService
        local binding = watchdog ~= nil and watchdog.bindings[actor.uid] or nil
        if binding == nil or service == nil then return idle end
        binding.npcHitAttack = { id = message.attack, item = gun, weapon = work.weapon, atMs = now, count = 0, victims = {} }
        service.huntingShot(nil, message, animal)
    end
    animations.apply(shell, combat.shotPresetFor(shell))
    combat.reportSound(shell, gun)
    combat.presentShot(shell, gun, animal)
    local clip = type(animations.active) == "table" and animations.active[shell] or nil
    state.aimAt, state.nextShot = now, now + math.max(1500, weapons.fireIntervalMs(gun))
    state.shotUntil = type(clip) == "table" and tonumber(clip.deadlineAtMs) or now + 1100
    return idle
end

Activity.handlers.hunt = Activity.hunt

Activity.forageCycleMs = 42000
Activity.forageReachMs = 8000
Activity.forageStandMs = 6000

function Activity.seedOf(uid)
    local seed = 0
    uid = tostring(uid or "")
    for index = 1, #uid do seed = (seed * 31 + string.byte(uid, index)) % 2147483647 end
    return seed
end

function Activity.workLook(actor, shell, id, now)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or type(id) ~= "string" then return false end
    if id ~= "forage" then return animations.apply(shell, id) end
    local cycle = Activity.forageCycleMs
    local phase = ((tonumber(now) or 0) + Activity.seedOf(actor.uid)) % cycle
    if phase >= cycle - Activity.forageStandMs then
        if type(animations.current) == "table" and animations.current[shell] ~= nil
                and type(animations.clear) == "function" then animations.clear(shell) end
        return true
    end
    if phase >= cycle - Activity.forageStandMs - Activity.forageReachMs then return animations.apply(shell, "search_low") end
    return animations.apply(shell, id)
end

Activity.choreLooks = {
    forage = { "forage" }, water = { "search_low" }, firewood = { "chop_wood", "saw_planks" }, crate = { "build_crate" },
}
Activity.camps = {}

function Activity.choreCamp(memory, chore)
    if chore.kind ~= "firewood" and chore.kind ~= "crate" then return nil end
    local key = tostring(memory.groupId or "")
    local camp = Activity.camps[key]
    if camp == nil then
        local firewood = chore.kind == "firewood"
        camp = { id = "chore:" .. key, x = chore.spot.x, y = chore.spot.y,
            depot = { x = chore.spot.x, y = chore.spot.y, z = 0 },
            chores = { wood = firewood and 16 or 0, planks = firewood and 18 or 0, crates = firewood and 0 or 1, forage = 0 },
            visible = { logs = 0, planks = 0, crates = 0 } }
        Activity.camps[key] = camp
    end
    return camp
end

function Activity.chore(actor, shell, context)
    local memory = actor.memory
    local state = type(memory.activityState) == "table" and memory.activityState.activity or nil
    local chore = type(state) == "table" and state.chore or nil
    if type(chore) ~= "table" or type(chore.spot) ~= "table" or state.seq ~= memory.activitySeq
            or context.threat ~= nil or shell == nil or type(shell.getX) ~= "function" then return nil end
    local index = tonumber(memory.groupIndex) or 1
    local angle = index * 2.1
    local radius = chore.kind == "water" and 0 or 2.5
    local station = { x = chore.spot.x + math.cos(angle) * radius, y = chore.spot.y + math.sin(angle) * radius, z = 0 }
    if (shell:getX() - station.x) ^ 2 + (shell:getY() - station.y) ^ 2 > 4 and type(context.startMovement) == "function" then
        return context.startMovement(actor, shell, station, "activity_chore", {
            pace = "walk", timeoutMs = 15000, doorsOnly = true, tolerance = 1.2,
        })
    end
    local now = tonumber(context.now) or 0
    local looks = Activity.choreLooks[chore.kind] or Activity.choreLooks.forage
    Activity.workLook(actor, shell, looks[(index % #looks) + 1], now)
    local camp = ProjectALife.CampLife
    local site = Activity.choreCamp(memory, chore)
    if camp ~= nil and site ~= nil and type(camp.render) == "function" then camp.render(site, now) end
    if chore.kind == "forage" and camp ~= nil and type(camp.forageGather) == "function" then camp.forageGather(actor, chore.spot) end
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", chore.kind) end
    return { kind = "idle", intent = chore.kind, cooldownUntilMs = now + 1500 }
end

Activity.handlers.forage = Activity.chore
Activity.handlers.fetch_water = Activity.chore
Activity.handlers.chop_camp = Activity.chore
Activity.handlers.build_camp = Activity.chore

function Activity.reset()
    Activity.camps = {}
    Activity.hunting = setmetatable({}, { __mode = "k" })
    Activity.metrics = { evaluations = 0, claimed = 0, notDriven = 0, reports = 0, calmDropped = 0 }
    return true
end

Registry.register({
    id = "activity",
    label = "Squad activity",
    summary = "Runs the work steps of the activity the squad's planner picked; other activities run through the modules that already do them.",
    kind = "orders",
    priority = 94,
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        return Activity.evaluate(actor, shell, context)
    end,
})

return Activity
