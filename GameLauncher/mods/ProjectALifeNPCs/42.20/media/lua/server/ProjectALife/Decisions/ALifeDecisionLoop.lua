require "ProjectALife/Movement/ALifeMovement"
require "ProjectALife/Loot/ALifeScavenging"
require "ProjectALife/Senses/ALifePerception"
require "ProjectALife/Combat/ALifeCombat"
require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Fear/ALifeSurvival"
require "ProjectALife/Senses/ALifeInvestigation"
require "ProjectALife/Senses/ALifeCaution"
require "ProjectALife/Senses/ALifeClues"
require "ProjectALife/Records/ALifeBehaviorProfiles"
require "ProjectALife/Behaviours/ALifeModuleTravel"
require "ProjectALife/Fear/ALifeModuleSurvival"
require "ProjectALife/Behaviours/ALifeModuleCover"
require "ProjectALife/Fear/ALifeModuleWithdraw"
require "ProjectALife/Fear/ALifeModuleFear"
require "ProjectALife/Behaviours/ALifeModuleHealing"
require "ProjectALife/Behaviours/ALifeModuleGunner"
require "ProjectALife/Admin/ALifeBlackBox"
require "ProjectALife/Behaviours/ALifeModuleConducts"
require "ProjectALife/Behaviours/ALifeModuleLeader"
require "ProjectALife/Behaviours/ALifeModuleStrafe"
require "ProjectALife/Behaviours/ALifeModuleMeleeCrew"
require "ProjectALife/Behaviours/ALifeModuleStances"
require "ProjectALife/Behaviours/ALifeModuleActivity"
require "ProjectALife/Behaviours/ALifeModuleScavengeRun"
require "ProjectALife/Behaviours/ALifeModuleSearch"
require "ProjectALife/Behaviours/ALifeModulePatrolRest"
require "ProjectALife/Behaviours/ALifeModuleCareful"
require "ProjectALife/Behaviours/ALifeModuleWarning"
require "ProjectALife/Behaviours/ALifeModuleFortify"
require "ProjectALife/Decisions/ALifeRoutines"
require "ProjectALife/Decisions/ALifeKnowledge"
require "ProjectALife/Decisions/ALifeStandoff"
require "ProjectALife/Decisions/ALifeEngagementPolicy"
require "ProjectALife/Decisions/ALifeRelations"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeLoadoutProgression"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Fear/ALifeEncounterPolicy"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Watchdog = ProjectALife.Watchdog
local Catalog = ProjectALife.Catalog
local Movement = ProjectALife.Movement
local Scavenging = ProjectALife.Scavenging
local Perception = ProjectALife.Perception
local Combat = ProjectALife.Combat
local Survival = ProjectALife.Survival
local Profiles = ProjectALife.BehaviorProfiles
local Modules = ProjectALife.ModuleRegistry
local Programs = ProjectALife.Programs
local EngagementPolicy = ProjectALife.EngagementPolicy
local Relations = ProjectALife.Relations
local Endurance = ProjectALife.Endurance
local Tactics = ProjectALife.SquadTactics

local function voiceSilent() return false end
local Voice = setmetatable({}, {
    __index = function(_, key)
        local real = ProjectALife.Voice
        if type(real) == "table" then
            local value = real[key]

            if value ~= nil then return value end
        end

        return voiceSilent
    end,
})
local Ledger = ProjectALife.ActionLedger
local Animations = ProjectALife.Animations
local EncounterPolicy = ProjectALife.EncounterPolicy
local behaviorDefaults = ProjectALife.BehaviorSettings
local Telemetry = ProjectALife.Telemetry
local Decisions = {
    adapters = {},

    metrics = { magdumpsCut = 0, beginRefused = {}, leadsLeashed = 0, dressedUnderFire = 0 },
    states = {},
    order = {},
    cursor = 0,
    hotCursor = 0,
    lastSyncAtMs = -math.huge,
    orders = {},
    syncIntervalMs = 2000,

    traceDecisions = false,

    lullModules = { "orders", "medic", "healing", "search" },

    roamHoldAtMs = {},

    syncMisses = {},
    syncMissLimit = 3,
}
ProjectALife.DecisionLoop = Decisions

local function nowMs()
    if type(Decisions.adapters.nowMs) == "function" then return Decisions.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function shellFor(actor)
    local binding = Watchdog.bindings[actor.uid]
    if binding and binding.generation == actor.generation and Watchdog.matches(binding) then
        local executor = ProjectALife.Executor
        if executor ~= nil and type(executor.clientAuthority) == "function" and executor.clientAuthority()
                and not executor.authorityFor(binding.shell) then return nil end
        return binding.shell
    end
    return nil
end

local function setActivity(actor, activity, intent)

    local current = Registry.peek(actor.uid)
    if current == nil or current.lifecycle ~= "active" then return end

    if current.activity == (type(activity) == "string" and activity or "idle")
            and current.intent == (type(intent) == "string" and intent or "hold") then
        return
    end
    Registry.setActivity(current.uid, current.revision, activity, intent, true)
end

local function stampState(shell, state)
    if shell == nil or type(state) ~= "table" then return end
    local data = Combat.dataOf(shell)
    if data == nil then return end
    data.ProjectALifeBehaviorState = state.kind
    data.ProjectALifeBehaviorIntent = state.intent
end

local function randomTarget(shell, radius)
    if type(Decisions.adapters.randomTarget) == "function" then
        return Decisions.adapters.randomTarget(shell, radius)
    end
    local dx, dy
    if type(ZombRandBetween) == "function" then
        dx, dy = ZombRandBetween(-radius, radius + 1), ZombRandBetween(-radius, radius + 1)
    elseif type(ZombRand) == "function" then
        dx, dy = ZombRand(radius * 2 + 1) - radius, ZombRand(radius * 2 + 1) - radius
    else
        dx, dy = 0, 0
    end
    return { x = shell:getX() + dx, y = shell:getY() + dy, z = shell:getZ() }
end

local function positionOf(value)
    local x, y, z = Combat.xyzOf(value)
    if x == nil then return nil end
    return { x = x, y = y, z = z }
end

local function targetAlive(value)
    local kind = type(value)
    if (kind ~= "table" and kind ~= "userdata") or type(value.isDead) ~= "function" then return false end
    return value:isDead() ~= true
end

local function patrolPause(actor, now)
    local minimum = behaviorDefaults.movement.patrolPauseMinimumMs
    local maximum = behaviorDefaults.movement.patrolPauseMaximumMs
    local hash = math.floor(now / 1000)
    for index = 1, #actor.uid do hash = hash + string.byte(actor.uid, index) * index end
    return minimum + hash % math.max(1, maximum - minimum + 1)
end

Decisions.followGap = 1.8
Decisions.followHold = 2.2
function Decisions.followTarget(shell, spot)
    if spot == nil or shell == nil then return spot end
    local sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
    if math.abs(sz - (tonumber(spot.z) or sz)) > 0.5 then return spot end
    local dx, dy = sx - spot.x, sy - spot.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= Decisions.followHold then
        return { x = sx, y = sy, z = spot.z, close = true }
    end
    return { x = spot.x + dx / distance * Decisions.followGap,
        y = spot.y + dy / distance * Decisions.followGap, z = spot.z }
end

local function orderedTarget(order, shell)
    if order.kind == "follow" then return Decisions.followTarget(shell, positionOf(order.player)) end
    if order.kind == "patrol" and order.anchor ~= nil then
        local target = randomTarget(shell, 6)
        return {
            x = order.anchor.x + target.x - shell:getX(),
            y = order.anchor.y + target.y - shell:getY(),
            z = order.anchor.z,
        }
    end
    return nil
end
Decisions.orderedTarget = orderedTarget

local function programFor(actor)
    local faction = Catalog.faction(actor.factionId)
    local factionProgram = faction and faction.spawn
        and string.lower(tostring(faction.spawn.program or "patrol")) or "patrol"
    return Programs.mode(actor, factionProgram), factionProgram
end

function Decisions.personInstead(actor, shell, threat, threatKind, state, now)
    if threatKind ~= "zombie" or type(Perception.personPick) ~= "function" then return nil end
    local person, kind = Perception.personPick(actor.uid, now)
    if person == nil or person == threat then return nil end
    local choice = Decisions.engagement(actor, shell, person, kind, state, now)
    if choice == "watch" or choice == "bypass" then return nil end
    Decisions.metrics.personOverZombie = (Decisions.metrics.personOverZombie or 0) + 1
    return person, kind
end

function Decisions.zombieStance(actor, facts, choice, reason)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.zombieMode) ~= "function" then return choice, reason end
    local mode = caution.zombieMode(actor)
    if mode == "fight" and choice == "bypass" and reason ~= "recent_disengagement" then
        return "commit", "zombie_fight_mode"
    end
    if mode == "avoid" and choice == "commit" and reason ~= "explicit_mission"
            and facts.immediateDanger ~= true and facts.targetAttacking ~= true then
        return "bypass", "zombie_avoid_mode"
    end
    return choice, reason
end

function Decisions.engagement(actor, shell, threat, threatKind, state, now)
    local kind = threatKind == "actor" and "npc" or threatKind
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local facts = { targetKind = kind }
    local _, factionProgram = programFor(actor)
    local mission = "travel"
    local order = Decisions.orders[actor.uid]
    if type(order) == "table" and order.generation == actor.generation
            and (order.untilMs == nil or now < order.untilMs) then
        if order.kind == "attack" or order.kind == "hunt" then mission = "combat"
        elseif order.kind == "rescue" then mission = "rescue" end
    end
    if kind ~= "zombie" and (factionProgram == "hunt" or factionProgram == "manhunt"
            or factionProgram == "assault" or factionProgram == "full_raid") then mission = "combat" end
    local careful = ProjectALife.ModuleCareful
    if careful ~= nil and type(careful.territorialFacts) == "function" then
        local inTerritory, warned = careful.territorialFacts(actor, threat, now)
        facts.inTerritory, facts.warned = inTerritory == true, warned == true
        if facts.inTerritory then mission = "guard" end
    end
    if kind == "zombie" and mission == "travel" and type(Combat.leashFor) == "function"
            and Combat.leashFor(actor) ~= nil then
        mission, facts.inTerritory = "guard", true
    end
    facts.mission = mission
    if kind == "player" then
        facts.relation = Relations.playerStance(actor, threat)
    elseif kind == "npc" then
        local other = Perception.activeActorForShell(threat)
        facts.relation = other ~= nil and Relations.status(actor, other) or "neutral"
    end
    local held = type(Perception.attackers) == "table" and Perception.attackers[actor.uid] or nil
    facts.targetAttacking = type(held) == "table" and held.attacker == threat
        and now < (tonumber(held.untilMs) or -1e12)
    facts.immediateDanger = Decisions.immediateThreat(actor, shell, threat, threatKind, now)
    facts.exhausted = Endurance.value(actor, shell, now) <= Endurance.settings.retreatThreshold
    local resistance = ProjectALife.Resistance
    local woundedAt = Survival.retreatHealth
    if resistance ~= nil then
        facts.exhausted = resistance.tired(actor, shell, threat, kind, now, facts.exhausted)
        if resistance.person(kind) then woundedAt = resistance.retreatHealthFor(actor, shell, now, woundedAt) end
    end
    facts.wounded = Survival.retreat == true and type(Survival.healthRatio) == "function"
        and Survival.healthRatio(actor, shell) <= woundedAt
    local withdraw = ProjectALife.ModuleWithdraw
    local plan = withdraw ~= nil and type(withdraw.plans) == "table" and withdraw.plans[actor.uid] or nil
    facts.outnumbered = type(plan) == "table" and plan.reason == "withdraw_outnumbered"
        and now >= (tonumber(plan.startedAtMs) or now)
        and now < (tonumber(plan.untilMs) or -1e12)
    local data = Combat.dataOf(shell)
    facts.ammoLow = type(data) == "table" and now < (tonumber(data.ProjectALifeDryUntilMs) or -1e12)
    facts.canEscape = type(state) == "table" and type(state.action) == "table"
        and state.action.status == "running" and (state.kind == "movement" or state.kind == "retreat")
    local destination = type(state) == "table" and type(state.action) == "table"
        and state.action.target or memory.travelLeg
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(threat)
    if kind == "zombie" and type(destination) == "table" and sx ~= nil and tx ~= nil
            and sz ~= nil and tz ~= nil and math.abs(sz - tz) < 0.4 then
        local dx, dy = destination.x - sx, destination.y - sy
        local length2 = dx * dx + dy * dy
        if length2 > 0 then
            local along = ((tx - sx) * dx + (ty - sy) * dy) / length2
            local offsetX, offsetY = tx - sx - along * dx, ty - sy - along * dy
            facts.routeBlocked = along > 0 and along <= 1 and offsetX * offsetX + offsetY * offsetY <= 2.25
                and (tx - sx) ^ 2 + (ty - sy) ^ 2 <= 16
        end
    end
    local discretion = kind == "player" and ProjectALife.Discretion or nil
    if discretion ~= nil then facts.holdOff = discretion.holdOff(actor, shell, threat, now) end
    local choice, reason = EngagementPolicy.evaluate(facts)
    if Survival.avoidsTarget(actor, threat, now, facts.immediateDanger) then
        choice, reason = "bypass", "recent_disengagement"
    end
    local discipline = kind == "zombie" and ProjectALife.GunDiscipline or nil
    if discipline ~= nil then
        choice, reason = discipline.engagement(actor, shell, threat, facts, choice, reason, now)
        if choice == "bypass" then discipline.noteAvoid(actor, now) end
    end
    if kind == "zombie" then choice, reason = Decisions.zombieStance(actor, facts, choice, reason) end
    memory.engagementFacts = facts
    memory.engagementDecision, memory.engagementReason = choice, reason
    actor.memory = memory
    if resistance ~= nil and facts.relation == "hostile" and (choice == "watch" or choice == "bypass") then
        resistance.noteHold(actor, shell, threat, kind, choice, reason, now)
    end
    return choice, facts
end

local persistMemory
local function startMovement(actor, shell, target, intent, options)
    local given = options or {}
    options = {}
    for key, value in pairs(given) do options[key] = value end
    if intent == "patrol" and type(Movement.patrolBlocked) == "function"
            and Movement.patrolBlocked(shell, target, nowMs()) then return nil end
    local caution = ProjectALife.Caution
    if caution ~= nil then
        local verdict, goal, hold = caution.review(actor, shell, target, intent, options)
        if verdict == "wait" then
            setActivity(actor, "idle", "avoid_zombies")
            return { kind = "idle", intent = "avoid_zombies", cooldownUntilMs = nowMs() + (tonumber(hold) or 3000) }
        elseif verdict == "skip" then
            return nil
        elseif verdict == "detour" and type(goal) == "table" then
            target, options.cautionSkip = goal, true
        end
        caution.sneakRoll(actor, shell, intent, options, nowMs())
    end
    if intent == "patrol" and type(Movement.patrolBlocked) == "function"
            and Movement.patrolBlocked(shell, target, nowMs()) then return nil, "patrol_edge_banned" end
    local homes = ProjectALife.DoorPolicy
    if homes ~= nil and type(homes.pathRefusal) == "function" and options.homeOk ~= true
            and homes.pathRefusal(actor, shell, target, intent) ~= nil then
        if type(Movement.refuseGoal) == "function" then
            Movement.refuseGoal(actor.uid, target, nowMs(), homes.settings.pathRefusalMs)
        end
        return nil, "home_private"
    end
    local action = Movement.begin(actor, shell, target, {
        pace = options.pace,

        doorsOnly = options.doorsOnly == true or intent == "scavenge",
        tolerance = options.tolerance,
        stallMs = options.stallMs or behaviorDefaults.movement.stallMs,
        pathStartupGraceMs = options.pathStartupGraceMs
            or behaviorDefaults.movement.pathStartupGraceMs,
        maximumRepathMs = options.maximumRepathMs
            or behaviorDefaults.movement.maximumRepathMs,
        maximumConsecutiveStalls = options.maximumConsecutiveStalls
            or behaviorDefaults.movement.maximumConsecutiveStalls,
        maximumTraversalFailures = options.maximumTraversalFailures
            or behaviorDefaults.movement.maximumTraversalFailures,
        timeoutMs = options.timeoutMs or behaviorDefaults.movement.patrolTimeoutMs,

        maximumRecoveries = options.maximumRecoveries,
        operationId = options.operationId,
    })
    if action == nil then return nil end
    if ProjectALife.GunDiscipline ~= nil and intent ~= "avoid_zombies" then
        ProjectALife.GunDiscipline.noteMoving(actor, nowMs())
    end
    local movementReaction = ({
        patrol = "PATROL_START",
        regroup = "REGROUP",
        follow = "MOVE_OUT",
    })[intent]
    if movementReaction ~= nil then
        Voice.play(shell, movementReaction, { context = { activity = intent } })
    end
    setActivity(actor, options.activity or "moving", intent)
    return {
        kind = options.kind or "movement",
        action = action,
        intent = intent,
        cautionSkip = options.cautionSkip,
        threat = options.threat,
        threatKind = options.threatKind,
        cooldownUntilMs = 0,

        startedAtMs = nowMs(),
    }
end

function Decisions.homeLeaveBegin(actor, shell, target)
    return startMovement(actor, shell, target, "leave_home", { pace = "walk", timeoutMs = 20000, tolerance = 1.2 })
end

function Decisions.homeLeave(actor, shell, now)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.evictionStep) ~= "function" then return nil end
    return policy.evictionStep(actor, shell, now, Decisions.homeLeaveBegin)
end

Decisions.startMovement = startMovement

function Decisions.leashedLead(actor, shell, lead)
    if type(lead) ~= "table" or type(Combat.leashFor) ~= "function"
            or type(Combat.leashedPoint) ~= "function" then
        return lead
    end
    local anchor, leash = Combat.leashFor(actor)
    if anchor == nil then return lead end
    local clamped = Combat.leashedPoint(anchor, lead, leash)
    if clamped == lead then return lead end
    Decisions.metrics.leadsLeashed = (Decisions.metrics.leadsLeashed or 0) + 1
    local sx, sy = Combat.xyOf(shell)
    if sx == nil or (clamped.x - sx) ^ 2 + (clamped.y - sy) ^ 2 <= 9 then
        local investigation = ProjectALife.Investigation
        if investigation ~= nil and type(investigation.consume) == "function" then
            investigation.consume(actor, lead)
        end
        return nil
    end
    lead.x, lead.y, lead.z = clamped.x, clamped.y, clamped.z
    return lead
end

function Decisions.noteOpening(actor, threat)
    local fair = ProjectALife.Fairness
    if fair == nil or type(fair.noteOpened) ~= "function" then return false end
    return fair.noteOpened(actor, threat, nowMs())
end

function Decisions.noteEngaged(actor, threat)
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.engaged) == "function" then warning.engaged(actor, threat) end
end

function Decisions.noteBeginRefused(reason)
    local refused = Decisions.metrics.beginRefused
    if type(refused) ~= "table" then
        refused = {}
        Decisions.metrics.beginRefused = refused
    end
    local key = tostring(reason or "unknown")
    refused[key] = (refused[key] or 0) + 1
end

local function startCombat(actor, shell, threat, threatKind, intent)
    if Decisions.noncombat(actor) then return nil end
    if Survival.avoidsTarget(actor, threat, nowMs(), Decisions.immediateThreat(actor, shell, threat, threatKind, nowMs())) then return nil end
    if threatKind == "player" and ProjectALife.ModuleRobbery
            and ProjectALife.ModuleRobbery.consider(actor, threat, nowMs()) then
        Decisions.noteOpening(actor, threat)
        return { kind = "idle", intent = "robbery_pending", cooldownUntilMs = nowMs() + 250 }
    end
    if threatKind == "player" and intent ~= "recovery_self_defence" and ProjectALife.Standoff ~= nil
            and ProjectALife.Standoff.consider(actor, shell, threat, nowMs()) then
        return { kind = "idle", intent = "standoff_pending", cooldownUntilMs = nowMs() + 250 }
    end
    local mode = intent == "manhunt_player" and "manhunt"
        or intent == "hunt_nearby" and "hunt" or nil
    if mode == nil then mode = programFor(actor) end
    local action, refusal = Combat.begin(actor, shell, threat, {
        targetKind = threatKind,
        mode = mode,
    })

    if action == nil then
        Decisions.noteBeginRefused(refusal)
        return nil
    end
    local activity = ProjectALife.ModuleActivity
    if activity ~= nil and type(activity.hunting) == "table" then activity.hunting[shell] = nil end
    persistMemory(actor, "combatTargetKind", threatKind)
    persistMemory(actor, "combatTargetPlayerKey", threatKind == "player" and ProjectALife.Speech.playerKey(threat) or nil)
    if threatKind == "player" and intent ~= "recovery_self_defence" then Decisions.noteOpening(actor, threat) end
    if threatKind == "player" then Decisions.noteEngaged(actor, threat) end

    ProjectALife.ModuleSearch.cancel(actor.uid)
    if type(actor.memory) == "table" and actor.memory.lootPhase ~= nil then
        persistMemory(actor, "lootPhase", nil)
        persistMemory(actor, "lootSpot", nil)
        ProjectALife.Entrances.release(actor.uid)
    end
    ProjectALife.ModuleSearch.noteCombat(actor, nowMs(), persistMemory)
    setActivity(actor, "combat", intent or "engage_threat")
    local voiceEvent = threatKind == "player" and "CONTACT_PLAYER"
        or threatKind == "zombie" and "CONTACT_INFECTED"
        or "CONTACT_HOSTILE"
    local speech = ProjectALife.Speech
    Voice.play(shell, voiceEvent, { context = { targetKind = threatKind,
        psex = speech ~= nil and type(speech.threatSex) == "function" and speech.threatSex(threat, threatKind) or nil } })
    return {
        kind = "combat",
        action = action,
        threat = threat,
        threatKind = threatKind,
        mode = mode,
        intent = intent or "engage_threat",
        cooldownUntilMs = 0,
    }
end
Decisions.startCombat = startCombat

local function refreshRetreatAim(actor, shell, state, now)
    if type(state) ~= "table" or not targetAlive(state.threat) then return false end
    if state.aimed ~= true then return true end
    pcall(Animations.setCombatHold, shell, true)
    pcall(Combat.setPosture, actor, shell, true, now)
    pcall(Combat.stampAim, shell, state.threat)
    return true
end
Decisions.refreshRetreatAim = refreshRetreatAim

local function startRetreat(actor, shell, threat, threatKind, now, reason)
    if reason == "gun_fear" then
        local gunFear = ProjectALife.ModuleGunFear
        if gunFear ~= nil and type(gunFear.startFlight) == "function" then
            local flight = gunFear.startFlight(actor, shell, threat, threatKind, now,
                { startMovement = startMovement, setActivity = setActivity, persistMemory = persistMemory })
            if flight ~= nil then return flight end
        end
    end
    Survival.beginDisengage(actor, shell, threat, now, 25000)

    local distance = 12
    pcall(function()
        local combat = ProjectALife.Combat
        if combat ~= nil and combat.targetIsGunman(threat) == true then

            distance = reason == "gun_fear" and 35 or 22
        end
    end)
    local target = Survival.retreatTarget(shell, threat, distance)

    local aimed = Combat.targetIsGunman(shell) == true
    if aimed then
        Animations.setCombatHold(shell, true)
        Combat.setPosture(actor, shell, true, now)
        Combat.stampAim(shell, threat)
    end

    local sprint = Endurance.canSprint(actor, shell, now)
    local pace = sprint and "run" or "walk"
    local state = target and startMovement(actor, shell, target, "retreat", {
        kind = "retreat",
        activity = "moving",
        pace = pace,
        timeoutMs = distance > 12 and 14000 or 10000,
        threat = threat,
        threatKind = threatKind,
    }) or nil
    local speech = ProjectALife.Speech
    Voice.play(shell, "RETREAT", {
        urgent = true,
        context = { targetKind = threatKind, reason = reason,
            attack = reason == "gun_fear" and "firearm" or nil,
            psex = speech ~= nil and type(speech.threatSex) == "function" and speech.threatSex(threat, threatKind) or nil },
    })
    if state ~= nil then
        state.reason = reason
        state.aimed = aimed
        state.sprintUntilMs = sprint and (now + (tonumber(behaviorDefaults.combat.retreatSprintMs) or 2500)) or nil
        return state
    end
    if reason ~= "gun_fear" and reason ~= "out_of_ammo"
            and Decisions.restInSight(actor, shell, threat, threatKind, now) then
        setActivity(actor, "idle", "stand_ground")
        return { kind = "idle", intent = "stand_ground", cooldownUntilMs = now + 300 }
    end
    setActivity(actor, "idle", "recover_endurance")
    return {
        kind = "recovering",
        threat = threat,
        threatKind = threatKind,
        intent = "recover_endurance",
        cooldownUntilMs = now + 500,
    }
end

function Decisions.recoveryContact(shell, threat)
    if not targetAlive(threat) then return false end
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(threat)
    if sx == nil or tx == nil or sz == nil or tz == nil or math.abs(sz - tz) >= 0.4 then return false end
    return Combat.selfDefence(shell, threat)
        and type(Perception.visible) == "function" and Perception.visible(shell, threat) == true
end

function Decisions.immediateThreat(actor, shell, threat, threatKind, now)
    if threatKind == "zombie" then return Decisions.recoveryContact(shell, threat) end
    local held = type(Perception.attackers) == "table" and Perception.attackers[actor.uid] or nil
    return type(held) == "table" and held.attacker == threat
        and now < (tonumber(held.untilMs) or -1e12)
end

function Decisions.recoveryPursuit(shell, threat, threatKind)
    if threatKind == "zombie" and targetAlive(threat) then
        local sx, sy, sz = Combat.xyzOf(shell)
        local tx, ty, tz = Combat.xyzOf(threat)
        local withdraw = ProjectALife.ModuleWithdraw
        local radius = withdraw ~= nil and type(withdraw.settings) == "table"
            and tonumber(withdraw.settings.crowdTiles) or 4
        if sx ~= nil and tx ~= nil and sz ~= nil and tz ~= nil and math.abs(sz - tz) < 0.4
                and (tx - sx) ^ 2 + (ty - sy) ^ 2 <= radius * radius
                and type(Perception.visible) == "function" and Perception.visible(shell, threat) == true then
            return true
        end
    end
    return false
end

function Decisions.recoveryPressure(actor, shell, state, now)
    if Decisions.recoveryContact(shell, state.threat)
            or Decisions.recoveryPursuit(shell, state.threat, state.threatKind) then
        return true, state.threat, state.threatKind
    end
    local held = type(Perception.attackers) == "table" and Perception.attackers[actor.uid] or nil
    local data = Combat.dataOf(shell)
    local hitAt = type(data) == "table" and tonumber(data.ProjectALifeLastHitAtMs) or nil
    if type(held) ~= "table" or hitAt == nil or now < hitAt or now - hitAt > 6000
            or now >= (tonumber(held.untilMs) or -1e12) or not targetAlive(held.attacker) then return false end
    if type(Perception.visible) == "function" and Perception.visible(shell, held.attacker) == true then
        return true, held.attacker, held.kind
    end
    return false
end

local function findThreat(actor, shell, mode, factionProgram, now, includePursuit, recoveryPressure)

    local threat, _, threatKind = Perception.findThreat(actor, shell, mode)

    if type(threatKind) ~= "string" then threatKind = nil end

    local pursued = false
    if threat == nil and includePursuit and (mode == "hunt" or mode == "manhunt") then
        local pursuit, pursuitMode = Programs.pursuitThreat(actor, shell, factionProgram)
        if pursuit ~= nil then
            threat, threatKind, pursued = pursuit, "player", true
            mode = pursuitMode or mode
        end
    end
    if Survival.avoidsTarget(actor, threat, now, Decisions.immediateThreat(actor, shell, threat, threatKind, now))
            and not (recoveryPressure == true and Decisions.recoveryPursuit(shell, threat, threatKind)) then
        threat, threatKind, pursued = nil, nil, false
    end
    return threat, threatKind, mode, pursued
end

function Decisions.inMelee(shell, threat, reach)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(threat)
    if sx == nil or tx == nil or sz == nil or tz == nil or math.abs(sz - tz) >= 0.4 then return false end
    return (tx - sx) ^ 2 + (ty - sy) ^ 2 <= reach * reach
end

function Decisions.dressReady(shell, threat, now, actor)
    local modules = ProjectALife.ModuleRegistry
    if type(actor) == "table" and modules ~= nil and type(modules.modules) == "table"
            and type(modules.allows) == "function" and modules.modules.healing ~= nil
            and not modules.allows(actor, "healing") then return false end
    local healing = ProjectALife.ModuleHealing
    if healing == nil or type(healing.dressNow) ~= "function" or type(healing.bleeding) ~= "function"
            or type(healing.canDress) ~= "function" or type(healing.dressingOf) ~= "function"
            or type(healing.settings) ~= "table" then return false end
    local data = Combat.dataOf(shell)
    if not healing.canDress(shell, data, now) or not healing.bleeding(shell, data) then return false end
    if Decisions.inMelee(shell, threat, healing.settings.dressClearTiles) then return false end
    return healing.dressingOf(shell) ~= nil
end

function Decisions.dressFirst(actor, shell, threat, threatKind, now)
    if not Decisions.dressReady(shell, threat, now, actor) then return nil end
    local state = ProjectALife.ModuleHealing.dressNow(actor, shell, { now = now, setActivity = setActivity })
    if state ~= nil then Decisions.metrics.dressedUnderFire = (Decisions.metrics.dressedUnderFire or 0) + 1 end
    return state
end

local function respondToThreat(actor, shell, threat, threatKind, now, intent)
    if threat == nil then return nil end
    local choice, facts = Decisions.engagement(actor, shell, threat, threatKind, Decisions.states[actor.uid], now)
    if choice == "watch" or choice == "bypass" then return nil end
    local dressing = Decisions.dressFirst(actor, shell, threat, threatKind, now)
    if dressing ~= nil then return dressing end
    if choice == "disengage" then return startRetreat(actor, shell, threat, threatKind, now, "engagement_pressure") end

    local moduleResponse = Modules.evaluate("response", actor, shell, {
        now = now,
        threat = threat,
        threatKind = threatKind,
        startRetreat = startRetreat,

        persistMemory = persistMemory,

        startMovement = startMovement,
        setActivity = setActivity,
    })
    if moduleResponse ~= nil then return moduleResponse end
    local engageable, suppressReason, engageUntilMs = Combat.canEngage(actor, threat, now, shell)
    if not engageable then

        local reason = tostring(suppressReason or "")

        if reason == "combat_target_off_leash" then return nil end
        if (reason == "combat_line_blocked" or reason == "combat_target_other_floor"
                or reason == "combat_target_unreachable")
                and not Combat.retaliating(actor, threat, now) then
            pcall(function()
                local holdMs = math.max(500, (tonumber(engageUntilMs) or now) - now)
                Perception.ignore(actor.uid, threat, holdMs)
            end)
            return nil
        end
        if type(shell.faceThisObject) == "function" then pcall(shell.faceThisObject, shell, threat) end
        setActivity(actor, "idle", "hold_pressure")
        return { kind = "idle", intent = "hold_pressure",
            cooldownUntilMs = math.min(now + 600,
                math.max(now + 150, tonumber(engageUntilMs) or now)) }
    end

    local started = startCombat(actor, shell, threat, threatKind, intent)
    if started ~= nil and started.kind == "combat" and choice == "defend"
            and threatKind == "zombie" and facts.mission == "travel" then started.selfDefence = true end
    return started
end

function Decisions.fearVeto(actor, shell, threat, threatKind, now)
    if threatKind ~= "zombie" or ProjectALife.ModuleFear == nil then return nil end
    local ok, response = pcall(Modules.evaluate, "response", actor, shell, {
        now = now,
        threat = threat,
        threatKind = threatKind,
        startRetreat = startRetreat,
        persistMemory = persistMemory,
        startMovement = startMovement,
        setActivity = setActivity,
    }, "fear")
    if ok then return response end
    return nil
end

function Decisions.gunFlight(actor, shell, now)
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear == nil or type(gunFear.flights) ~= "table" or gunFear.flights[actor.uid] == nil
            or type(gunFear.continueFlight) ~= "function" then return nil end
    local ok, state = pcall(gunFear.continueFlight, actor, shell, {
        now = now,
        startRetreat = startRetreat,
        persistMemory = persistMemory,
        startMovement = startMovement,
        setActivity = setActivity,
    })
    if ok then return state end
    return nil
end

function Decisions.restInSight(actor, shell, threat, threatKind, now)
    local resistance = ProjectALife.Resistance
    if resistance == nil or threat == nil
            or not resistance.restRefused(actor, shell, threat, threatKind, now) then return false end
    Survival.forget(actor.uid, actor.generation)
    return true
end

function Decisions.fearFlight(actor, shell, now)
    local gunFlight = Decisions.gunFlight(actor, shell, now)
    if gunFlight ~= nil then return gunFlight end
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.continueFlight) ~= "function" then return nil end
    local ok, state = pcall(fear.continueFlight, actor, shell, {
        now = now,
        startRetreat = startRetreat,
        persistMemory = persistMemory,
        startMovement = startMovement,
        setActivity = setActivity,
    })
    if ok then return state end
    return nil
end

function Decisions.fearInCombat(actor, shell, state, now)
    local fear = ProjectALife.ModuleFear
    if fear == nil or state.threatKind ~= "zombie" or not fear.combatCheckDue(actor.uid, now) then return nil end
    return Decisions.fearVeto(actor, shell, state.threat, state.threatKind, now)
end

function Decisions.relaxAim(actor, shell, state, now)
    local watch = ProjectALife.ThreatWatch
    if watch == nil or type(watch.relax) ~= "function" then return false end
    return watch.relax(actor, shell, state, now)
end

function Decisions.fearOverlooks(actor, shell, threat, threatKind, now)
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.overlook) ~= "function" then return false end
    local ok, overlooked = pcall(fear.overlook, actor, shell, threat, threatKind, now)
    return ok and overlooked == true
end

local function cancelStateAction(actor, state, reason)
    if state.kind == "scavenging" and state.plan ~= nil then
        Scavenging.cancel(state.plan, reason)
    end
    Ledger.cancelActor(actor.uid, actor.generation, reason)
end

function Decisions.noncombat(actor)
    local progression = ProjectALife.LoadoutProgression
    if type(progression) ~= "table" or type(progression.noncombat) ~= "function"
            or type(actor) ~= "table" then return false end
    return progression.noncombat(Catalog.npc(actor.profileId))
end

function Decisions.elderState(actor, shell, state, now)
    local mode, factionProgram = programFor(actor)
    local threat, threatKind = findThreat(actor, shell, mode, factionProgram, now, true, true)
    if threat == nil and state ~= nil and state.kind == "combat" and targetAlive(state.threat)
            and type(Perception.visible) == "function" and Perception.visible(shell, state.threat) == true then
        threat, threatKind = state.threat, state.threatKind
    end
    if state ~= nil and state.kind == "recovering" then
        local pressured, target, kind = Decisions.recoveryPressure(actor, shell, state, now)
        if pressured then threat, threatKind = target, kind end
        if threat == nil then return nil end
    end
    if state ~= nil and state.kind ~= "idle" then
        cancelStateAction(actor, state, "elder_safety")
        persistMemory(actor, "travelLeg", nil)
    end
    if state ~= nil and state.kind == "combat" then
        local fleeing = Decisions.fearFlight(actor, shell, now)
        if fleeing ~= nil then return fleeing end
    end
    if threat ~= nil and state ~= nil and (state.intent == "idle_sit_down" or state.intent == "idle_sit_ground") then
        Animations.apply(shell, "sit_up")
        return { kind = "idle", intent = "idle_stand_up", cooldownUntilMs = now + 1000 }
    end
    if threat ~= nil then return startRetreat(actor, shell, threat, threatKind, now, "elder_safety") end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local presence = ProjectALife.ModuleTalkPresence
    if memory.talkHoldPlayerKey ~= nil and type(presence) == "table" and type(presence.evaluate) == "function" then
        local ok, held = pcall(presence.evaluate, actor, shell, { now = now })
        if ok and type(held) == "table" and held.intent == "talk_hold" then return held end
    end
    if state ~= nil and state.kind == "idle" then return nil end
    setActivity(actor, "idle", "elder_hold")
    return { kind = "idle", intent = "elder_hold", cooldownUntilMs = now + 1000 }
end

Decisions.panicHolds = { panic_stare = true, panic_startle = true, panic_alert = true }

function Decisions.panicAlarm(actor, shell, threat, threatKind, now)
    if threat == nil or threatKind ~= "zombie" then return false end
    local first = ProjectALife.FirstDays
    if first == nil or type(first.sees) ~= "function" then return false end
    local ok, alarmed = pcall(first.sees, actor, shell, threat, now)
    return ok and alarmed == true
end

function Decisions.panicClear(actor, state)
    if state.kind ~= "idle" then cancelStateAction(actor, state, "panic") end
end

function Decisions.panicStep(actor, shell, state, now)
    local first = ProjectALife.FirstDays
    if first == nil or type(first.step) ~= "function" or type(first.busy) ~= "function" then return nil end
    if first.busy(actor, now) ~= true then return nil end
    local ok, result = pcall(first.step, actor, shell, state, {
        now = now,
        persistMemory = persistMemory,
        startMovement = startMovement,
        setActivity = setActivity,
        clear = Decisions.panicClear,
    })
    if not ok or type(result) ~= "table" then return nil end
    return result
end

persistMemory = function(actor, key, value)
    if type(actor.memory) ~= "table" then actor.memory = {} end

    if actor.memory[key] == value and type(value) ~= "table" then return end
    actor.memory[key] = value

    local current = Registry.peek(actor.uid)
    if current == nil then return end

    Registry.updateTransient(current.uid, current.revision, function(record)
        record.memory = record.memory or {}
        record.memory[key] = value
    end, true)
end

local function persistRoamHeading(actor, nextHeading)
    if nextHeading == nil then return end
    persistMemory(actor, "roamHeadingRad", nextHeading)
end

local function memoryOf(actor)
    if type(actor.memory) ~= "table" then actor.memory = {} end
    return actor.memory
end

Decisions.afterFightMs = 120000
function Decisions.ambientTopic(actor, now)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.sceneTopic) == "function" then
        local ok, topic = pcall(first.sceneTopic, actor, now)
        if ok and type(topic) == "string" then return topic end
    end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local leader = ProjectALife.ModuleLeader
    local group = leader ~= nil and type(leader.groups) == "table" and memory.groupId ~= nil
        and leader.groups[memory.groupId] or nil
    local ended = group ~= nil and tonumber(group.fightEndedAtMs) or nil
    if ended ~= nil and now - ended >= 0 and now - ended <= Decisions.afterFightMs then return "after_fight" end
    if actor.activity == "scavenging" then return "scavenge" end
    return nil
end

local function decideInternal(actor, shell, now)
    if type(actor.memory) == "table" and actor.memory.dress ~= nil and ProjectALife.VisitorWardrobe ~= nil then
        ProjectALife.VisitorWardrobe.sync(actor, shell)
    end
    pcall(EncounterPolicy.reactToAim, actor, shell, now)
    local fleeing = Decisions.fearFlight(actor, shell, now)
    if fleeing ~= nil then return fleeing end
    if Decisions.noncombat(actor) then return Decisions.elderState(actor, shell, nil, now) end
    local mode, factionProgram = programFor(actor)
    local perceivedAt = nowMs()
    local threat, threatKind, threatMode, pursued =
        findThreat(actor, shell, mode, factionProgram, now, true)
    local overlooked = 0
    while threat ~= nil and overlooked < 3 and Decisions.fearOverlooks(actor, shell, threat, threatKind, now) do
        overlooked = overlooked + 1
        threat, threatKind, threatMode, pursued = findThreat(actor, shell, mode, factionProgram, now, true)
    end
    if Decisions.panicAlarm(actor, shell, threat, threatKind, now) then
        local panicked = Decisions.fearVeto(actor, shell, threat, threatKind, now)
        if panicked ~= nil then return panicked end
    end
    Decisions.notePhase("perception", nowMs() - perceivedAt)
    local quiet = ProjectALife.Caution
    if quiet ~= nil then quiet.noticed(actor, shell, threat, threatKind, now) end

    if threat ~= nil then
        local choice = Decisions.engagement(actor, shell, threat, threatKind, Decisions.states[actor.uid], now)
        if choice == "watch" or choice == "bypass" then
            local person, personKind = Decisions.personInstead(actor, shell, threat, threatKind,
                Decisions.states[actor.uid], now)
            if person ~= nil then
                threat, threatKind, pursued = person, personKind, false
            else
                threat, threatKind, pursued = nil, nil, false
            end
        end
    end

    mode = threatMode or mode

    local tierData = Combat.dataOf(shell)
    if tierData ~= nil then
        tierData.ProjectALifeBehaviorTier = Tactics.behaviorTier(actor, shell, threat)
    end

    pcall(Combat.setPosture, actor, shell, threat ~= nil, now)

    local data = tierData

    local seen = threat
    if pursued then seen = nil end
    local threatX, threatY = Combat.xyOf(seen)
    if data == nil then

    elseif seen ~= nil then
        if threatX ~= nil then
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = threatX, threatY

            local gunner = ProjectALife.ModuleGunner
            if gunner ~= nil and type(gunner.order) == "function" then
                local tracking = data.ProjectALifeSuppressTracking == true
                if tracking or data.ProjectALifeSuppressUntilMs == nil then

                    pcall(gunner.order, actor, shell, threat, now)
                elseif type(gunner.stop) == "function" then

                    if pcall(gunner.stop, data, shell) then
                        Decisions.metrics.magdumpsCut = (Decisions.metrics.magdumpsCut or 0) + 1
                    end
                end
            end
        end
    else
        local lead = Perception.lastKnownFor(actor, now)
        if lead ~= nil then
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = lead.x, lead.y
        else
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
        end
    end
    if threat == nil then Decisions.relaxAim(actor, shell, Decisions.states[actor.uid], now) end
    local respondedAt = nowMs()
    local response = respondToThreat(actor, shell, threat, threatKind, now,
        mode == "manhunt" and "manhunt_player"
            or mode == "hunt" and "hunt_nearby" or "engage_threat")
    Decisions.notePhase("response", nowMs() - respondedAt)
    if response ~= nil then return response end

    local order = Decisions.orders[actor.uid]
    local explicitOrder = order and order.generation == actor.generation and order.source ~= "leader"
        and (order.untilMs == nil or now < order.untilMs)
    if not explicitOrder then
        local destination, intent = Programs.supportDestination(actor, shell, now)
        if destination then
            local state = startMovement(actor, shell, destination, intent,
                { pace = "run", timeoutMs = 20000 })
            if state then return state end
        end
    end

    local leaving = Decisions.homeLeave(actor, shell, now)
    if leaving ~= nil then return leaving end

    local speech = ProjectALife.Voice
    if speech ~= nil and speech.adapters.enabled == true
            and speech.adapters.ambientEnabled ~= false then
        Voice.tickAmbient(shell, {
            state = mode == "patrol" and "patrol" or "idle",
            topic = Decisions.ambientTopic(actor, now),
            blocked = explicitOrder == true,
            context = {
                activity = actor.activity,
                intent = actor.intent,
                program = mode,
            },
        })
    end

    local moduleContext = {
        now = now,

        persistMemory = persistMemory,

        threat = threat,
        threatKind = threatKind,
        mode = mode,
        factionProgram = factionProgram,
        orders = Decisions.orders,
        defaults = behaviorDefaults,
        setActivity = setActivity,
        startMovement = startMovement,
        orderedTarget = orderedTarget,
    }

    local encounter = ProjectALife.Knowledge ~= nil and ProjectALife.Knowledge.decide(actor, shell, moduleContext) or nil
    if encounter ~= nil then return encounter end

    local abortHold = false
    local holdData = Combat.dataOf(shell)
    if holdData ~= nil then
        local untilMs = tonumber(holdData.ProjectALifeCombatAbortUntilMs)
        abortHold = untilMs ~= nil and now < untilMs + 2200

        local lullMs = tonumber(holdData.ProjectALifeCombatLullUntilMs)
        abortHold = abortHold or (lullMs ~= nil and now < lullMs)
    end
    if abortHold then

        for index = 1, #Decisions.lullModules do
            local held = Modules.evaluate("decision", actor, shell, moduleContext,
                Decisions.lullModules[index])
            if held ~= nil then return held end
        end
        setActivity(actor, "idle", "hold_after_abort")
        return { kind = "idle", intent = "hold_after_abort",
            cooldownUntilMs = now + 700 }
    end
    local moduleState = Modules.evaluate("decision", actor, shell, moduleContext)
    if moduleState ~= nil then return moduleState end

    local lead = Perception.lastKnownFor(actor, now)
    if lead ~= nil then
        local step = tonumber(memoryOf(actor).searchStep) or 0

        if step == 0 and lead.shared ~= true then
            Voice.play(shell, "LOST_TARGET")

            pcall(function()
                local gunner = ProjectALife.ModuleGunner
                if gunner ~= nil and type(gunner.order) == "function" then
                    gunner.order(actor, shell, lead, now)
                end
            end)
        end
        local destination = lead
        local sx, sy = Combat.xyOf(shell)
        local arrived = sx ~= nil and ((lead.x - sx) ^ 2 + (lead.y - sy) ^ 2) <= 9
        if arrived then

            step = step + 1
            persistMemory(actor, "searchStep", step)
            if step > 5 then
                Perception.clearLastKnown(actor)
                persistMemory(actor, "searchStep", nil)
            else
                local spread = 0
                for index = 1, #actor.uid do
                    spread = (spread * 31 + string.byte(actor.uid, index)) % 360
                end
                local angle = ((step * 137 + spread) % 360) * math.pi / 180
                local radius = 3.5 + (step % 3)
                destination = {
                    x = lead.x + math.cos(angle) * radius,
                    y = lead.y + math.sin(angle) * radius,
                    z = lead.z,
                }
            end
        end
        if Perception.lastKnownFor(actor, now) ~= nil then
            local state = startMovement(actor, shell, destination, "search", {
                timeoutMs = 9000,
            })
            if state ~= nil then
                state.lastKnownSearch = true
                setActivity(actor, "moving", "search_last_known")
                return state
            end
        end
    else

        persistMemory(actor, "searchStep", nil)
    end

    local heard = ProjectALife.Investigation
        and ProjectALife.Investigation.destinationFor(actor, shell, now) or nil
    if heard ~= nil then heard = Decisions.leashedLead(actor, shell, heard) end
    if heard ~= nil then
        local state = startMovement(actor, shell, heard, "investigate", {
            timeoutMs = 15000,
        })
        if state ~= nil then

            ProjectALife.Investigation.consume(actor, heard)
            Voice.play(shell, "SEARCH_START", {
                context = { source = heard.kind or "sound" },
            })
            setActivity(actor, "moving",
                heard.kind == "shout" and "investigate_shout"
                or heard.kind == "contact" and "join_contact"
                or "investigate_sound")
            return state
        end
    end

    local Clues = ProjectALife.Clues
    if Clues ~= nil then
        pcall(Clues.observe, actor, shell, now)
        local claimed = memoryOf(actor).clueZone
        if claimed ~= nil then
            local sx, sy = Combat.xyOf(shell)
            if sx ~= nil and ((claimed.x - sx) ^ 2 + (claimed.y - sy) ^ 2) <= 16 then

                local rooms = memoryOf(actor).searchRooms
                if rooms == nil then
                    local square
                    pcall(function() square = shell:getCurrentSquare() end)

                    pcall(function()
                        if square ~= nil and square:getBuilding() ~= nil then return end
                        local cell = getCell()
                        for ring = 2, 10, 2 do
                            for _, offset in ipairs({
                                    { ring, 0 }, { -ring, 0 },
                                    { 0, ring }, { 0, -ring },

                                    { ring, ring }, { -ring, ring },
                                    { ring, -ring }, { -ring, -ring } }) do
                                local probe = cell:getGridSquare(
                                    square:getX() + offset[1],
                                    square:getY() + offset[2], square:getZ())
                                if probe ~= nil and probe:getBuilding() ~= nil then
                                    square = probe
                                    return
                                end
                            end
                        end
                    end)

                    if type(ProjectALife.ModuleTalkPresence) == "table"
                            and type(ProjectALife.ModuleTalkPresence.refusesSweep) == "function"
                            and ProjectALife.ModuleTalkPresence.refusesSweep(actor, square, now) then
                        rooms = false
                    else
                        rooms = Clues.roomsToSearch(square, Clues.maximumRooms)
                    end
                    persistMemory(actor, "searchRooms", rooms or false)

                    persistMemory(actor, "searchRoomsUntilMs", now + 45000)
                end
                if now >= (tonumber(memoryOf(actor).searchRoomsUntilMs) or math.huge) then
                    rooms = false
                end
                local room = type(rooms) == "table" and rooms[1] or nil
                if room ~= nil then
                    local reached = ((room.x - sx) ^ 2 + (room.y - sy) ^ 2) <= 4
                    if reached then
                        table.remove(rooms, 1)
                        persistMemory(actor, "searchRooms", rooms)
                        room = rooms[1]
                    end
                end
                if room ~= nil then
                    local state = startMovement(actor, shell, room, "search", {
                        timeoutMs = 12000,
                    })
                    if state ~= nil then
                        setActivity(actor, "moving", "search_building")
                        return state
                    end
                end

                pcall(Clues.markSearched, actor, claimed.key, now)
                persistMemory(actor, "searchRooms", nil)
                persistMemory(actor, "searchRoomsUntilMs", nil)
                persistMemory(actor, "clueZone", nil)
            elseif now < (claimed.untilMs or 0) then
                local state = startMovement(actor, shell, claimed, "search", {
                    timeoutMs = 12000,
                })
                if state ~= nil then
                    setActivity(actor, "moving", "investigate_clue")
                    return state
                end
            else
                persistMemory(actor, "clueZone", nil)
                persistMemory(actor, "searchRooms", nil)
            end
        else

            local zone = Clues.selectZone(actor, shell, now, Clues.searchRadius)
            if zone ~= nil then

                zone.untilMs = now + 20000
                persistMemory(actor, "clueZone", zone)
                local state = startMovement(actor, shell, zone, "search", {
                    timeoutMs = 12000,
                })
                if state ~= nil then
                    setActivity(actor, "moving", "investigate_clue")
                    return state
                end
            end
        end
    end

    local memory = actor.memory or {}
    local target, intent, info, nextHeading = Programs.destination(
        actor, shell, randomTarget, factionProgram, now, memory.roamHeadingRad)
    persistRoamHeading(actor, nextHeading)

    local leg = type(info) == "table" and type(info.travelLeg) == "table" and info.travelLeg or nil

    if target ~= nil and type(memory.groupId) == "string"
            and Modules.get("groupMarch") == nil
            and Profiles.allows(actor, "groupMarch") then
        local slot = math.floor(now / 45000)
        local ok, sx, sy, sz = pcall(function()
            return shell:getX(), shell:getY(), shell:getZ()
        end)
        if ok then
            local march = memory.groupMarch
            local arrived = type(march) == "table" and march.x ~= nil
                and ((march.x - sx) ^ 2 + (march.y - sy) ^ 2) <= 4
            if type(march) ~= "table" or march.slot ~= slot or arrived then
                local seed = 0
                for index = 1, #memory.groupId do
                    seed = (seed * 31 + string.byte(memory.groupId, index)) % 2147483647
                end
                local heading = ((seed + slot * 137) % 360) * math.pi / 180

                local mine = 0
                for index = 1, #actor.uid do
                    mine = (mine * 31 + string.byte(actor.uid, index)) % 997
                end
                local spread = ((mine % 5) - 2) * 1.4
                march = {
                    slot = slot,
                    x = sx + math.cos(heading) * 22 - math.sin(heading) * spread,
                    y = sy + math.sin(heading) * 22 + math.cos(heading) * spread,
                    z = sz,
                }
                memory.groupMarch = march
            end
            target = { x = march.x, y = march.y, z = march.z }
            leg = nil
        end
    end
    local state = target and startMovement(actor, shell, target, intent, {
        timeoutMs = leg ~= nil and Programs.settings.roamLegMs
            or behaviorDefaults.movement.patrolTimeoutMs,
        maximumRecoveries = leg ~= nil and 0 or nil,

        pace = type(info) == "table" and info.pursuit == true and "run" or nil,
    }) or nil
    if state ~= nil then
        if leg ~= nil then
            if info.newLeg == true then persistMemory(actor, "travelLeg", leg) end
            state.roamLeg = true
            state.legX, state.legY = target.x, target.y
        end
        return state
    end
    setActivity(actor, "idle", mode == "scavenge" and "scan_supplies" or "hold")
    return {
        kind = "idle",
        intent = mode == "scavenge" and "scan_supplies" or "hold",
        cooldownUntilMs = now + 2000,
    }
end

local function decide(actor, shell, now)
    local state = decideInternal(actor, shell, now)
    if Decisions.traceDecisions and state ~= nil then
        Telemetry.emit("decision_trace", {
            uid = actor.uid,
            kind = state.kind,
            intent = state.intent,
        })
    end
    return state
end

local function interruptForAudible(actor, shell, state, now)
    if state.kind ~= "movement" then return nil end
    if Decisions.noncombat(actor) then return nil end

    local intent = tostring(state.intent or "")
    if intent == "search" or intent == "investigate" then return nil end
    local investigation = ProjectALife.Investigation
    if investigation == nil or #investigation.marks == 0 then return nil end
    local memory = memoryOf(actor)
    if now < (tonumber(memory.nextAudibleCheckMs) or 0) then return nil end
    persistMemory(actor, "nextAudibleCheckMs", now + 1000)
    local heard = investigation.destinationFor(actor, shell, now)

    if heard == nil then return nil end
    if type(investigation.canInterrupt) ~= "function" or not investigation.canInterrupt(state) then return nil end
    heard = Decisions.leashedLead(actor, shell, heard)
    if heard == nil then return nil end
    cancelStateAction(actor, state, "heard_something")
    local replacement = startMovement(actor, shell, heard, "investigate", {
        timeoutMs = 15000,
    })
    if replacement ~= nil then
        investigation.consume(actor, heard)
        setActivity(actor, "moving",
            heard.kind == "shout" and "investigate_shout"
            or heard.kind == "contact" and "join_contact"
            or "investigate_sound")
        return replacement
    end
    return nil
end

function Decisions.legHeadsAway(shell, state, threat, tiles)
    local legX, legY = tonumber(state.legX), tonumber(state.legY)
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(threat)
    if legX == nil or legY == nil or sx == nil or tx == nil then return false end
    local ax, ay = tx - sx, ty - sy
    if ax * ax + ay * ay > tiles * tiles then return false end
    return (legX - sx) * ax + (legY - sy) * ay < 0
end

Decisions.roamHoldTiles = 12
Decisions.roamHoldEveryMs = 20000
function Decisions.holdForUnreachable(actor, shell, state, threat, threatKind, now)
    if state.roamLeg ~= true or threatKind == "zombie" or threatKind == nil then return nil end
    if now < (Decisions.roamHoldAtMs[actor.uid] or -1e12) + Decisions.roamHoldEveryMs then return nil end
    if not Decisions.legHeadsAway(shell, state, threat, Decisions.roamHoldTiles) then return nil end
    Decisions.roamHoldAtMs[actor.uid] = now
    cancelStateAction(actor, state, "threat_near_roam")
    persistMemory(actor, "travelLeg", nil)
    if type(shell.faceThisObject) == "function" then pcall(shell.faceThisObject, shell, threat) end
    setActivity(actor, "idle", "hold_pressure")
    return { kind = "idle", intent = "hold_pressure", cooldownUntilMs = now + 1200 }
end

local function interruptPassiveState(actor, shell, state, now)

    if state.kind ~= "idle" and state.kind ~= "movement"
            and state.kind ~= "scavenging" and state.kind ~= "recovering" then
        return nil
    end

    if state.intent == "radio_call" or state.intent == "panic_cover" or state.intent == "panic_freeze" or state.intent == "cqb_sweep" or state.intent == "cqb_look" then return nil end
    if Decisions.panicHolds[tostring(state.intent)] == true then return nil end

    local gunFear = ProjectALife.ModuleGunFear
    if gunFear ~= nil and type(gunFear.interrupt) == "function" then
        local helpers = Decisions.gunFearHelpers
        if helpers == nil then
            helpers = { startRetreat = startRetreat, persistMemory = persistMemory,
                startMovement = startMovement, setActivity = setActivity }
            Decisions.gunFearHelpers = helpers
        end
        local fled = gunFear.interrupt(actor, shell, state, now, helpers)
        if fled ~= nil then
            cancelStateAction(actor, state, "gun_fear")
            return fled
        end
    end

    local uid = actor.uid

    if not Decisions.passiveScanDue(uid, now) then
        Decisions.metrics.passiveSkipped = (Decisions.metrics.passiveSkipped or 0) + 1
        return nil
    end
    Decisions.passiveScannedAtMs[uid] = now
    if state.intent ~= "fear_flee" and Decisions.noncombat(actor) then return Decisions.elderState(actor, shell, state, now) end
    local mode, factionProgram = programFor(actor)
    local threat, threatKind, threatMode, pursued =
        findThreat(actor, shell, mode, factionProgram, now, true, state.kind == "recovering")
    if threat ~= nil and Decisions.fearOverlooks(actor, shell, threat, threatKind, now) then return nil end
    if threat ~= nil and state.kind ~= "recovering" and state.intent ~= "fear_flee"
            and Decisions.panicAlarm(actor, shell, threat, threatKind, now) then
        cancelStateAction(actor, state, "panic")
        local panicked = Decisions.fearVeto(actor, shell, threat, threatKind, now)
        if panicked ~= nil then return panicked end
    end
    local quiet = ProjectALife.Caution
    if quiet ~= nil then quiet.noticed(actor, shell, threat, threatKind, now) end
    Decisions.passiveQuietAtMs[uid] = threat == nil and now or nil
    mode = threatMode or mode
    if state.kind == "recovering" then
        if threat == nil then return nil end
        local contact = Decisions.recoveryContact(shell, threat)
        if contact or Decisions.recoveryPursuit(shell, threat, threatKind) then
            state.threat, state.threatKind = threat, threatKind
        end
        if not contact then return nil end
        cancelStateAction(actor, state, "recovery_contact")
        local defended = startCombat(actor, shell, threat, threatKind, "recovery_self_defence")
        if defended ~= nil then defended.selfDefence = true; return defended end
        return startRetreat(actor, shell, threat, threatKind, now, "recovery_pressure")
    end
    if threat ~= nil then
        local choice = Decisions.engagement(actor, shell, threat, threatKind, state, now)
        if choice == "watch" or choice == "bypass" then
            local person, personKind = Decisions.personInstead(actor, shell, threat, threatKind, state, now)
            if person == nil then return nil end
            threat, threatKind = person, personKind
        end
    end
    local passiveData = Combat.dataOf(shell)
    if passiveData ~= nil then
        passiveData.ProjectALifeBehaviorTier = Tactics.behaviorTier(actor, shell, threat)
    end

    pcall(Combat.setPosture, actor, shell, threat ~= nil, now)

    if passiveData ~= nil then
        local data = passiveData
        local tx, ty = Combat.xyOf(threat)

        if pursued then tx, ty = nil, nil end
        if tx ~= nil then
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = tx, ty
        elseif threat == nil or pursued then
            local lead = Perception.lastKnownFor(actor, now)
            if lead ~= nil then
                data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = lead.x, lead.y
            else
                data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
            end
        end
    end
    if threat == nil then
        Decisions.relaxAim(actor, shell, state, now)
        return nil
    end
    if state.intent == "idle_sit_down" or state.intent == "idle_sit_ground" then
        Animations.apply(shell, "sit_up")
        return {kind="idle",intent="idle_stand_up",cooldownUntilMs=now+1000}
    end

    local heldPose = passiveData ~= nil and passiveData.ProjectALifeHeldBump ~= nil
    if heldPose or (state.kind == "idle" and string.sub(tostring(state.intent or ""), 1, 5) == "idle_") then
        pcall(Animations.clear, shell)
        setActivity(actor, "idle", "alerted")
        return { kind = "idle", intent = "alerted", cooldownUntilMs = now + 300 }
    end
    local survivalResponse = Survival.evaluate(actor, shell, threat, now)

    if not Combat.canEngage(actor, threat, now, shell)
            and (survivalResponse == nil or survivalResponse == "fight") then
        return Decisions.holdForUnreachable(actor, shell, state, threat, threatKind, now)
    end

    if survivalResponse == nil or survivalResponse == "fight" then
        local startable, refusal = Combat.canBegin(actor, threat, now, shell)
        if not startable then
            Decisions.noteBeginRefused(refusal)
            return nil
        end
    end
    cancelStateAction(actor, state, "threat_detected")
    return respondToThreat(actor, shell, threat, threatKind, now,
        mode == "manhunt" and "manhunt_player"
            or mode == "hunt" and "hunt_nearby" or "engage_threat")
end

function Decisions.tickEndurance(actor, shell, state, now)
    local phaseAt = nowMs()
    Endurance.tick(actor, shell, Endurance.activityMode(state, shell,
        Decisions.recoveryPressure(actor, shell, state, now)), now)
    Decisions.notePhase("endurance", nowMs() - phaseAt)
end

Decisions.idleAlertAtMs = {}
Decisions.sittingPoses = { sit_ground = true, warm_hands = true, play_guitar = true }
function Decisions.sitPoseFor(shell, now)
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.campPose) ~= "function" then return "sit_ground" end
    return life.campPose(shell, now, "sit_ground", true)
end

Decisions.dangerLines = { zombie = "CONTACT_INFECTED", hostile = "CONTACT_PLAYER", player = "CONTACT_PLAYER" }

function Decisions.dropIdlePose(shell, preset)
    if preset ~= nil and Decisions.sittingPoses[preset.id] == true then
        Animations.apply(shell, "sit_up")
        return true
    end
    Animations.clear(shell)
    return false
end

Decisions.guestSoft = { zombie = true, noise = true, light = true, panic = true }

function Decisions.guestSeated(shell, reason)
    if Decisions.guestSoft[reason] ~= true then return false end
    local guest = ProjectALife.ModuleVisitorLife
    if guest == nil or type(guest.holdsPose) ~= "function" or not guest.holdsPose(shell) then return false end
    return Animations.current[shell] == guest.posed[shell]
end

function Decisions.idleBreak(actor, shell, state, now)
    local preset = Animations.presetOf(Animations.current[shell])
    if preset == nil or preset.idle ~= true then return nil end
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.idleDanger) ~= "function" then return nil end
    local reason, dx, dy = caution.idleDanger(actor, shell, now)
    if reason == nil or Decisions.guestSeated(shell, reason) then return nil end
    cancelStateAction(actor, state, "idle_danger")
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory ~= nil and memory.activityId == "fish" then
        persistMemory(actor, "activityEvent", { kind = "done", seq = tonumber(memory.activitySeq) or 0 })
    end
    local stood = Decisions.dropIdlePose(shell, preset)
    pcall(Combat.setPosture, actor, shell, true, now)
    if dx ~= nil and dy ~= nil then
        pcall(function()
            local guard = ProjectALife.AIFence
            if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, dx, dy, now) end
        end)
    end
    local line = Decisions.dangerLines[reason]
    local last = Decisions.idleAlertAtMs[actor.uid]
    if line ~= nil and (last == nil or now - last > 15000) then
        Decisions.idleAlertAtMs[actor.uid] = now
        Voice.play(shell, line, { context = { targetKind = reason == "zombie" and "zombie" or "player" } })
    end
    Decisions.metrics.idleBreaks = (Decisions.metrics.idleBreaks or 0) + 1
    setActivity(actor, "idle", "alerted")
    local delay = stood and 1100 or (250 + ZombRand(450))
    return { kind = "idle", intent = "idle_alert", cooldownUntilMs = now + delay }
end

function Decisions.stopForTalk(actor, shell, state, now)
    cancelStateAction(actor, state or { kind = "idle" }, "talk_hold")
    local preset = Animations.presetOf(Animations.current[shell])
    local guest = ProjectALife.ModuleVisitorLife
    local seated = guest ~= nil and type(guest.holdsPose) == "function" and guest.holdsPose(shell)
    if preset ~= nil and preset.idle == true and not seated then Decisions.dropIdlePose(shell, preset) end
    Decisions.metrics.talkStops = (Decisions.metrics.talkStops or 0) + 1
    return { kind = "idle", intent = "talk_hold", cooldownUntilMs = now + 150 }
end

function Decisions.talkStop(actor, shell, state, now)
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or memory.talkHoldPlayerKey == nil or (tonumber(memory.talkHoldUntilMs) or 0) <= now then return nil end
    if state.intent == "talk_hold" or state.kind == "combat" or state.kind == "retreat" or state.kind == "recovering" then
        return nil
    end
    return Decisions.stopForTalk(actor, shell, state, now)
end

function Decisions.stopNow(uid, now)
    local actor, state = Registry.read(uid), Decisions.states[uid]
    if actor == nil or actor.lifecycle ~= "active" then return false end
    if type(state) == "table" and (state.intent == "talk_hold" or state.kind == "combat"
            or state.kind == "retreat" or state.kind == "recovering") then return false end
    local shell = shellFor(actor)
    if shell == nil then return false end
    local nextState = Decisions.stopForTalk(actor, shell, state, now)
    Decisions.states[uid] = nextState
    stampState(shell, nextState)
    return true
end

local function update(actor, shell, state, now)
    if Animations.blocksLocomotion(shell) then return state end
    local dressing = ProjectALife.ProfileHydrator
    if dressing ~= nil and type(dressing.wardrobeTick) == "function" then
        pcall(dressing.wardrobeTick, actor, shell, state, now)
    end

    if state.kind ~= "recovering" then Decisions.tickEndurance(actor, shell, state, now) end
    if state.intent == "idle_stand_up" and now < (state.cooldownUntilMs or 0) then return state end
    if state.intent == "idle_alert" and now < (state.cooldownUntilMs or 0) then return state end
    local startled = Decisions.idleBreak(actor, shell, state, now)
    if startled ~= nil then return startled end
    local held = Decisions.talkStop(actor, shell, state, now)
    if held ~= nil then return held end
    local panicked = Decisions.panicStep(actor, shell, state, now)
    if panicked ~= nil then return panicked end

    if state.kind == "combat" and Decisions.noncombat(actor) then
        return Decisions.elderState(actor, shell, state, now)
    end

    local phaseAt = nowMs()
    local interrupted = interruptPassiveState(actor, shell, state, now)
    Decisions.notePhase("passive", nowMs() - phaseAt)
    if interrupted == nil then Decisions.restPassive(actor.uid, now) end
    if state.kind == "recovering" then Decisions.tickEndurance(actor, shell, state, now) end
    if interrupted ~= nil then return interrupted end
    phaseAt = nowMs()
    local heard = interruptForAudible(actor, shell, state, now)
    Decisions.notePhase("audible", nowMs() - phaseAt)
    if heard ~= nil then return heard end

    if state.kind == "scavenging" then
        local status = Scavenging.tick(state.plan, shell)
        if status == "moving" then return state end
        setActivity(actor, "idle", status == "complete" and "supplies_secured" or "scan_supplies")
        return {
            kind = "idle",
            intent = status == "complete" and "supplies_secured" or "scan_supplies",
            cooldownUntilMs = now + 1200,
        }
    end

    if state.kind == "movement" then
        if state.lastKnownSearch == true and Perception.lastKnownFor(actor, now) == nil then
            cancelStateAction(actor, state, "search_lead_gone")
        end
        if state.action.status == "running" then
            local caution = ProjectALife.Caution
            local verdict, goal, hold
            if caution ~= nil then verdict, goal, hold = caution.watch(actor, shell, state, now) end
            if ProjectALife.GunDiscipline ~= nil then
                if verdict ~= nil then ProjectALife.GunDiscipline.noteAvoid(actor, now)
                else ProjectALife.GunDiscipline.noteMoving(actor, now) end
            end
            if verdict ~= nil then
                cancelStateAction(actor, state, "avoid_zombies")
                if verdict == "detour" and type(goal) == "table" then
                    local moved = startMovement(actor, shell, goal, state.intent,
                        { pace = "walk", timeoutMs = 12000, cautionSkip = true })
                    if moved ~= nil then return moved end
                end
                setActivity(actor, "idle", "avoid_zombies")
                return { kind = "idle", intent = "avoid_zombies", cooldownUntilMs = now + (tonumber(hold) or 3000) }
            end
            local spread = ProjectALife.GroupSpread
            local gap = spread ~= nil and type(spread.gapHold) == "function"
                and spread.gapHold(actor, shell, state, now) or nil
            if gap ~= nil then
                cancelStateAction(actor, state, "gap_hold")
                setActivity(actor, "idle", "gap_hold")
                return gap
            end
            local following = Decisions.leaderRetarget(actor, shell, state, now)
            if following ~= nil then return following end
            return state
        end

        if state.roamLeg == true then persistMemory(actor, "travelLeg", nil) end
        if state.intent == "patrol" then Tactics.advancePatrol(actor) end
        setActivity(actor, "idle", "hold")
        local pause = state.intent == "patrol" and patrolPause(actor, now) or 800
        return { kind = "idle", intent = "hold", cooldownUntilMs = now + pause }
    end

    if state.kind == "retreat" then

        if state.sprintUntilMs ~= nil and now >= state.sprintUntilMs then
            state.sprintUntilMs = nil
            if state.aimed and state.action ~= nil and type(state.action.setPace) == "function" then
                pcall(state.action.setPace, state.action, "walk")
            end
        end
        if not refreshRetreatAim(actor, shell, state, now) then
            cancelStateAction(actor, state, "retreat_threat_gone")
            return decide(actor, shell, now)
        end
        if state.action.status == "running" then return state end
        if state.intent == "gun_flee" then
            local flown = Decisions.gunFlight(actor, shell, now)
            if flown ~= nil then return flown end
            return decide(actor, shell, now)
        end
        if Decisions.restInSight(actor, shell, state.threat, state.threatKind, now) then
            return decide(actor, shell, now)
        end
        setActivity(actor, "idle", "recover_endurance")
        return {
            kind = "recovering",
            threat = state.threat,
            threatKind = state.threatKind,
            intent = "recover_endurance",
            cooldownUntilMs = now + 500,
        }
    end

    if state.kind == "recovering" then
        if not targetAlive(state.threat) then return decide(actor, shell, now) end
        if type(state.threat.getCurrentSquare) == "function"
                and state.threat:getCurrentSquare() == nil then return decide(actor, shell, now) end

        state.recoverUntilMs = state.recoverUntilMs or (now + 9000)
        if Decisions.restInSight(actor, shell, state.threat, state.threatKind, now) then
            return decide(actor, shell, now)
        end
        if now < (state.cooldownUntilMs or 0) then return state end
        local scared = Decisions.fearVeto(actor, shell, state.threat, state.threatKind, now)
        if scared ~= nil then return scared end
        local pressured, pressureTarget, pressureKind = Decisions.recoveryPressure(actor, shell, state, now)
        if pressured then
            if Decisions.recoveryContact(shell, pressureTarget) then
                local defended = startCombat(actor, shell, pressureTarget, pressureKind or state.threatKind, "recovery_self_defence")
                if defended ~= nil then defended.selfDefence = true; return defended end
            end
            return startRetreat(actor, shell, pressureTarget, pressureKind or state.threatKind, now, "recovery_pressure")
        end
        if Survival.canReengage(actor, shell, now) or now >= state.recoverUntilMs then
            Survival.beginDisengage(actor, shell, state.threat, now, 9000)
            return decide(actor, shell, now)
        end
        return state
    end

    if state.kind == "combat" then
        if state.action ~= nil and state.action.target ~= nil and state.action.target ~= state.threat then
            state.threat = state.action.target
            state.threatKind = state.action.targetKind or state.threatKind
        end
        if state.action ~= nil and state.action.disengage == true then
            if state.action.status == "running" then return state end
            if Decisions.restInSight(actor, shell, state.threat, state.threatKind, now) then
                return decide(actor, shell, now)
            end
            Survival.beginDisengage(actor, shell, state.threat, now, 9000)
            setActivity(actor, "idle", "recover_endurance")
            return { kind = "recovering", threat = state.threat, threatKind = state.threatKind,
                intent = "recover_endurance", cooldownUntilMs = now + 500 }
        end
        if state.selfDefence == true and not Decisions.recoveryContact(shell, state.threat) then
            Ledger.cancelActor(actor.uid, actor.generation, "contact_ended")
            return startRetreat(actor, shell, state.threat, state.threatKind, now, "contact_ended")
        end
        if state.selfDefence ~= true and Decisions.dressReady(shell, state.threat, now, actor) then
            Ledger.cancelActor(actor.uid, actor.generation, "dress_wounds")
            local dressing = Decisions.dressFirst(actor, shell, state.threat, state.threatKind, now)
            if dressing ~= nil then return dressing end
        end
        if ProjectALife.Knowledge ~= nil and ProjectALife.Knowledge.lostTarget(actor, shell, state, now) then
            Ledger.cancelActor(actor.uid, actor.generation, "target_lost")
            return decide(actor, shell, now)
        end
        ProjectALife.ModuleSearch.noteCombat(actor, now, persistMemory)
        local scared = Decisions.fearInCombat(actor, shell, state, now)
        if scared ~= nil then
            Ledger.cancelActor(actor.uid, actor.generation, "fear")
            return scared
        end
        local response, _, reason = Survival.evaluate(actor, shell, state.threat, now)
        if response == "retreat" and state.selfDefence ~= true then
            Ledger.cancelActor(actor.uid, actor.generation, reason)
            return startRetreat(actor, shell, state.threat, state.threatKind, now, reason)
        end
        if state.action.status == "running" then return state end
        ProjectALife.ModuleSearch.arm(actor, now, persistMemory)
        setActivity(actor, "idle", "scan")
        return { kind = "idle", intent = "scan", cooldownUntilMs = now + 400 }
    end

    if now < (state.cooldownUntilMs or 0) then return state end
    if state.intent == "idle_sit_down" then
        Animations.apply(shell, Decisions.sitPoseFor(shell, now))
        return {kind="idle",intent="idle_sit_ground",cooldownUntilMs=now+20000}
    elseif state.intent == "idle_sit_ground" then
        Animations.apply(shell, "sit_up")
        return {kind="idle",intent="idle_stand_up",cooldownUntilMs=now+1000}
    end
    return decide(actor, shell, now)
end

function Decisions.stillBound(actor)
    local binding = Watchdog.bindings[actor.uid]
    return binding ~= nil and binding.generation == actor.generation and Watchdog.matches(binding) == true
end

local function forgetInternal(uid, generation, reason)
    ProjectALife.ModuleSearch.cancel(uid)
    local actor = Registry.read(uid)
    Scavenging.cancelActor(uid, generation, reason or "actor_forgotten")
    if generation ~= nil then Ledger.cancelActor(uid, generation, reason or "actor_forgotten") end
    Endurance.forget(uid, generation)
    Survival.forget(uid, generation)
    Combat.forgetActor(uid)
    pcall(function()
        if type(Perception.forgetActor) == "function" then
            Perception.forgetActor(uid)
        elseif type(Perception.forgetIgnored) == "function" then
            Perception.forgetIgnored(uid)
        end
    end)
    pcall(function()
        if type(Tactics.forget) == "function" then Tactics.forget({ uid = uid }) end
    end)
    pcall(function()
        local withdraw = ProjectALife.ModuleWithdraw
        if withdraw ~= nil then withdraw.forgetActor(uid) end
    end)
    pcall(function()
        local fear = ProjectALife.ModuleFear
        if fear ~= nil then fear.forgetActor(uid) end
    end)
    pcall(function()
        local gunFear = ProjectALife.ModuleGunFear
        if gunFear ~= nil then gunFear.forgetActor(uid) end
    end)
    pcall(function()
        local resistance = ProjectALife.Resistance
        if resistance ~= nil then resistance.forgetActor(uid) end
    end)
    Voice.forget(uid)
    if ProjectALife.Knowledge ~= nil and type(ProjectALife.Knowledge.forget) == "function" then
        ProjectALife.Knowledge.forget(uid)
    end
    if actor ~= nil then Tactics.forget(actor) end
    Decisions.states[uid] = nil
    Decisions.orders[uid] = nil

    Decisions.passiveQuietAtMs[uid] = nil
    Decisions.passiveRestUntilMs[uid] = nil
    Decisions.passiveScannedAtMs[uid] = nil
    Decisions.roamHoldAtMs[uid] = nil
    Decisions.syncMisses[uid] = nil
    if Decisions.lanes ~= nil then
        if Decisions.lanes.costMs ~= nil then Decisions.lanes.costMs[uid] = nil end
        if Decisions.lanes.nearest2 ~= nil then Decisions.lanes.nearest2[uid] = nil end
        if Decisions.lanes.thoughtAtMs ~= nil then Decisions.lanes.thoughtAtMs[uid] = nil end
        if Decisions.lanes.hot ~= nil then Decisions.lanes.hot[uid] = nil end
        if Decisions.lanes.far ~= nil then Decisions.lanes.far[uid] = nil end
    end
end

local function sync(now)
    if now - Decisions.lastSyncAtMs < Decisions.syncIntervalMs then return end
    local order, live = {}, {}

    Registry.each(function(actor)
        if actor.lifecycle ~= "active" then return end
        if shellFor(actor) ~= nil then
            order[#order + 1] = actor.uid
            live[actor.uid] = true
            Decisions.syncMisses[actor.uid] = nil
        elseif Decisions.states[actor.uid] ~= nil and Decisions.stillBound(actor) then

            local misses = (Decisions.syncMisses[actor.uid] or 0) + 1
            Decisions.syncMisses[actor.uid] = misses
            if misses < Decisions.syncMissLimit then
                order[#order + 1] = actor.uid
                live[actor.uid] = true
            end
        end
    end)
    for uid in pairs(Decisions.states) do
        if not live[uid] then forgetInternal(uid, nil, "actor_inactive") end
    end
    Decisions.order = order
    Decisions.cursor = math.min(Decisions.cursor, #order)
    Decisions.hotCursor = math.min(Decisions.hotCursor, #order)
    Decisions.lastSyncAtMs = now
end

function Decisions.configure(adapters)
    Decisions.adapters = adapters or {}
    Decisions.traceDecisions = Decisions.adapters.traceDecisions == true
    Movement.configure(Decisions.adapters.movement)
    Scavenging.configure(Decisions.adapters.scavenging)
    if ProjectALife.ScavengeRun ~= nil then
        ProjectALife.ScavengeRun.configure(Decisions.adapters.scavengeRun)
    end
    Perception.configure(Decisions.adapters.perception)
    Endurance.configure(Decisions.adapters.endurance)
    Tactics.configure(Decisions.adapters.tactics)
    Combat.configure(Decisions.adapters.combat)
    Voice.configure(Decisions.adapters.voice)
    EncounterPolicy.configure(Decisions.adapters.encounter)
    Survival.configure(Decisions.adapters.survival)
    Programs.configure(Decisions.adapters.programs)
    pcall(function()
        local rest = ProjectALife.ModulePatrolRest
        if rest ~= nil then rest.configure(Decisions.adapters.patrolRest) end
    end)
    pcall(function()
        local fear = ProjectALife.ModuleFear
        if fear ~= nil then fear.configure(Decisions.adapters.fear) end
    end)
    pcall(function()
        local first = ProjectALife.FirstDays
        if first ~= nil then first.configure(Decisions.adapters.firstDays) end
    end)
    pcall(function()
        local gunFear = ProjectALife.ModuleGunFear
        if gunFear ~= nil then gunFear.configure(Decisions.adapters.gunFear) end
    end)
    pcall(function()
        local resistance = ProjectALife.Resistance
        if resistance ~= nil then resistance.configure(Decisions.adapters.resistance) end
    end)
end

function Decisions.reset()
    pcall(function()
        local fear = ProjectALife.ModuleFear
        if fear ~= nil then fear.reset() end
    end)
    pcall(function()
        local first = ProjectALife.FirstDays
        if first ~= nil then first.reset() end
    end)
    pcall(function()
        local gunFear = ProjectALife.ModuleGunFear
        if gunFear ~= nil then gunFear.reset() end
    end)
    pcall(function()
        local resistance = ProjectALife.Resistance
        if resistance ~= nil then resistance.reset() end
    end)
    Decisions.gunFearHelpers = nil
    Decisions.metrics = { magdumpsCut = 0, beginRefused = {}, leadsLeashed = 0, dressedUnderFire = 0 }
    Decisions.states = {}
    Decisions.order = {}
    Decisions.cursor = 0
    Decisions.hotCursor = 0
    Decisions.lastSyncAtMs = -math.huge
    Decisions.orders = {}
    Decisions.passiveQuietAtMs = {}
    Decisions.passiveRestUntilMs = {}
    Decisions.passiveScannedAtMs = {}
    Decisions.roamHoldAtMs = {}
    Decisions.syncMisses = {}
    if Decisions.lanes ~= nil then
        Decisions.lanes.hot, Decisions.lanes.far = {}, {}
        Decisions.lanes.thoughtAtMs, Decisions.lanes.nearest2 = {}, {}
        Decisions.lanes.costMs, Decisions.lanes.roundDebt = {}, 0
        Decisions.lanes.stretch, Decisions.lanes.loadMs, Decisions.lanes.meanCostMs = 1, 0, nil
        Decisions.lanes.refreshedAtMs = -math.huge
    end
    Decisions.shed(1)
    Scavenging.reset()
    Endurance.reset()
    Survival.disengagements = {}
    Tactics.reset()
    Voice.reset()
    pcall(function()
        local life = ProjectALife.GroupLife
        if life ~= nil and type(life.reset) == "function" then life.reset() end
    end)
end

function Decisions.refreshDirective(uid)
    local state, actor = Decisions.states[uid], Registry.read(uid)
    if actor == nil or state == nil or (state.kind ~= "movement" and state.kind ~= "scavenging"
            and state.kind ~= "idle") then return false end
    cancelStateAction(actor, state, "directive_changed")
    local shell = shellFor(actor)
    if shell ~= nil then Movement.stop(shell) end
    Decisions.states[uid] = { kind = "idle", intent = "directive_changed", cooldownUntilMs = nowMs() }
    Decisions.passiveQuietAtMs[uid] = nil
    return true
end

function Decisions.sameLeaderHold(previous, generation, order, now)
    if type(previous) ~= "table" or type(order) ~= "table"
            or previous.source ~= "leader" or order.source ~= "leader"
            or previous.kind ~= "hold" or order.kind ~= "hold"
            or previous.generation ~= generation then return false end
    if previous.untilMs ~= nil and now >= (tonumber(previous.untilMs) or 0) then return false end
    if type(previous.anchor) ~= "table" or type(order.anchor) ~= "table"
            or type(order.anchor.x) ~= "number" or type(order.anchor.y) ~= "number"
            or type(order.anchor.z) ~= "number" then return false end
    return previous.anchor.x == order.anchor.x
        and previous.anchor.y == order.anchor.y and previous.anchor.z == order.anchor.z
end

Decisions.leaderRetargetTiles = 4
Decisions.leaderRetargetMs = 3000

function Decisions.followsLeaderHold(uid, previous, generation, order, now)
    if type(previous) ~= "table" or type(order) ~= "table"
            or previous.source ~= "leader" or order.source ~= "leader"
            or previous.kind ~= "hold" or order.kind ~= "hold"
            or previous.generation ~= generation then return false end
    if previous.untilMs ~= nil and now >= (tonumber(previous.untilMs) or 0) then return false end
    local state = Decisions.states[uid]
    if type(state) ~= "table" or state.kind ~= "movement" or state.intent ~= "hold" then return false end
    local anchor = order.anchor
    return type(anchor) == "table" and type(anchor.x) == "number" and type(anchor.y) == "number"
        and type(anchor.z) == "number"
end

function Decisions.leaderRetarget(actor, shell, state, now)
    local order = Decisions.orders[actor.uid]
    if type(order) ~= "table" or order.source ~= "leader" or order.kind ~= "hold" or state.intent ~= "hold"
            or order.generation ~= actor.generation or type(order.anchor) ~= "table" then return nil end
    local target = type(state.action) == "table" and state.action.target or nil
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then return nil end
    if now - (tonumber(state.retargetAtMs) or tonumber(state.startedAtMs) or now) < Decisions.leaderRetargetMs then
        return nil
    end
    local dx, dy = order.anchor.x - target.x, order.anchor.y - target.y
    local reach = Decisions.leaderRetargetTiles
    if dx * dx + dy * dy < reach * reach then return nil end
    cancelStateAction(actor, state, "leader_moved")
    local moved = startMovement(actor, shell, order.anchor, "hold")
    if moved == nil then return nil end
    moved.retargetAtMs = now
    Decisions.metrics.leaderRetargets = (Decisions.metrics.leaderRetargets or 0) + 1
    return moved
end

function Decisions.setOrder(uid, generation, order)
    local actor = Registry.read(uid)
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= generation then
        return false, "order_actor_stale"
    end
    if type(order) ~= "table" or not ({ follow = true, hold = true, patrol = true })[order.kind] then
        return false, "order_invalid"
    end
    if order.kind == "follow" and order.player == nil then return false, "order_player_missing" end
    if order.kind ~= "follow" and type(order.anchor) ~= "table" then
        return false, "order_anchor_missing"
    end

    if order.source == "leader" and Decisions.states[uid] and Decisions.states[uid].kind == "combat" then
        return false, "order_member_engaged"
    end
    local previous = Decisions.orders[uid]
    if Decisions.sameLeaderHold(previous, generation, order, nowMs()) then
        previous.untilMs = tonumber(order.untilMs)
        return true
    end
    if Decisions.followsLeaderHold(uid, previous, generation, order, nowMs()) then
        previous.anchor, previous.untilMs = order.anchor, tonumber(order.untilMs)
        return true
    end
    Scavenging.cancelActor(uid, generation, "player_order_changed")
    Ledger.cancelActor(uid, generation, "player_order_changed")
    Decisions.states[uid] = { kind = "idle", intent = "order_changed", cooldownUntilMs = 0 }
    Decisions.orders[uid] = {
        kind = order.kind,
        player = order.player,
        anchor = order.anchor,
        generation = generation,
        untilMs = tonumber(order.untilMs),
        source = order.source == "leader" and "leader" or "player",
    }
    local shell = shellFor(actor)

    if order.quiet ~= true then
        Animations.apply(shell, ({ follow = "follow", hold = "stop", patrol = "salute" })[order.kind])
        Voice.play(shell, "ORDER_ACK")
    end
    return true
end

function Decisions.clearLeaderOrder(uid, generation)
    local order = Decisions.orders[uid]
    if not order or order.generation ~= generation or order.source ~= "leader" then return false end
    Decisions.orders[uid] = nil
    if not Decisions.states[uid] or Decisions.states[uid].kind ~= "combat" then
        Ledger.cancelActor(uid, generation, "formation_released")
        Decisions.states[uid] = { kind = "idle", intent = "formation_released", cooldownUntilMs = 0 }
    end
    return true
end

function Decisions.forget(uid, generation, reason)
    forgetInternal(uid, generation, reason)
    if type(Decisions.passiveQuietAtMs) == "table" then Decisions.passiveQuietAtMs[uid] = nil end
    return true
end

Decisions.lanes = {
    hotRadius = 45, hotIntervalMs = 150,
    farRadius = 110, farIntervalMs = 1500,
    refreshMs = 1000, refreshedAtMs = -math.huge,
    hot = {}, far = {}, thoughtAtMs = {},

    budgetMs = 12,

    roundMinimum = 2,

    passiveHotMs = 250, passiveFarMs = 2500, passiveMidMs = 1000,

    passiveCloseRadius = 12,
    nearest2 = {},

    costMs = {}, roundDebt = 0, roundDebtLimit = 2,
    gapMs = 100, stretch = 1, stretchMax = 4, stretchLoadMs = 9, loadMs = 0, loadAlpha = 0.15,
}
Decisions.passiveQuietAtMs = {}
Decisions.passiveRestUntilMs = {}
Decisions.passiveScannedAtMs = {}
Decisions.urgentKinds = { combat = true, retreat = true, recovering = true }

function Decisions.passiveScanIntervalFor(uid)
    local lanes = Decisions.lanes
    if lanes.hot[uid] then return lanes.passiveHotMs end
    if lanes.far[uid] then return lanes.passiveFarMs end
    return lanes.passiveMidMs
end

function Decisions.passiveScanDue(uid, now)
    local rest = Decisions.passiveRestUntilMs[uid]
    if rest ~= nil and now < rest and Perception.retaliationTarget(uid, now) == nil then return false end
    local quietSince = Decisions.passiveQuietAtMs[uid]
    if quietSince == nil or now < quietSince then return true end

    if Perception.retaliationTarget(uid, now) ~= nil then return true end
    local close = (Decisions.lanes.nearest2[uid] or math.huge)
        <= Decisions.lanes.passiveCloseRadius * Decisions.lanes.passiveCloseRadius
    local interval = Decisions.passiveScanIntervalFor(uid)
    if close then interval = math.min(250, interval) end
    return now - quietSince >= interval
end

Decisions.profile = { window = {}, total = {}, windowStartMs = nil, reportMs = 30000, slowTickMs = 8,
    windowTicks = 0, windowDecisionMs = 0 }

function Decisions.profileAddTo(bucket, name, ms)
    local row = bucket[name]
    if row == nil then row = { ms = 0, calls = 0 }; bucket[name] = row end
    row.ms = row.ms + ms
    row.calls = row.calls + 1
end

function Decisions.profileAdd(name, ms)
    local p = Decisions.profile
    ms = tonumber(ms) or 0
    Decisions.profileAddTo(p.window, name, ms)
    Decisions.profileAddTo(p.total, name, ms)
end

function Decisions.profileTop(bucket, count)
    local rows = {}
    for name, row in pairs(bucket or {}) do rows[#rows + 1] = { name = name, ms = row.ms, calls = row.calls } end
    table.sort(rows, function(a, b) if a.ms ~= b.ms then return a.ms > b.ms end return a.name < b.name end)
    local parts = {}
    for index = 1, math.min(count or 8, #rows) do
        parts[#parts + 1] = rows[index].name .. "=" .. tostring(rows[index].ms) .. "ms(" .. tostring(rows[index].calls) .. ")"
    end
    return table.concat(parts, " ")
end

function Decisions.profileTick(now, spentMs)
    local p = Decisions.profile
    p.windowStartMs = p.windowStartMs or now
    p.windowTicks = p.windowTicks + 1
    p.windowDecisionMs = p.windowDecisionMs + (tonumber(spentMs) or 0)
    if now - p.windowStartMs < p.reportMs then return nil end
    local average = p.windowDecisionMs / math.max(1, p.windowTicks)
    local line
    if average >= p.slowTickMs then
        line = string.format("[ALIFE-PERF] decisions %ds avg=%.1fms/tick ticks=%d actors=%d top: %s",
            math.floor((now - p.windowStartMs) / 1000), average, p.windowTicks, #Decisions.order,
            Decisions.profileTop(p.window, 10))
        pcall(print, line)
    end
    p.window, p.windowStartMs, p.windowTicks, p.windowDecisionMs = {}, now, 0, 0
    return line
end

function Decisions.refreshLanes(now)
    local lanes = Decisions.lanes
    if now - lanes.refreshedAtMs < lanes.refreshMs then return end
    lanes.refreshedAtMs = now
    local points = {}
    pcall(function()
        local players = type(Decisions.adapters.players) == "function" and Decisions.adapters.players()
            or (ProjectALife.PlayerLocator ~= nil and ProjectALife.PlayerLocator.list() or {})
        for _, player in ipairs(players or {}) do
            local x, y
            if type(player) == "table" then x, y = player.x, player.y
            else pcall(function() x, y = player:getX(), player:getY() end) end
            if tonumber(x) ~= nil and tonumber(y) ~= nil then points[#points + 1] = { x = x, y = y } end
        end
    end)
    local hot, far = {}, {}
    if #points > 0 then
        local hot2, far2 = lanes.hotRadius * lanes.hotRadius, lanes.farRadius * lanes.farRadius
        for _, uid in ipairs(Decisions.order) do
            local state = Decisions.states[uid]
            local fighting = type(state) == "table" and (state.kind == "combat")
            local nearest = math.huge
            pcall(function()
                local actor = (Registry.peek or Registry.read)(uid)
                local shell = actor and shellFor(actor)
                if shell == nil then return end
                local sx, sy = shell:getX(), shell:getY()
                for _, p in ipairs(points) do
                    local dx, dy = sx - p.x, sy - p.y
                    local d = dx * dx + dy * dy
                    if d < nearest then nearest = d end
                end
            end)
            lanes.nearest2[uid] = nearest
            if fighting or nearest <= hot2 then hot[uid] = true
            elseif nearest > far2 and nearest < math.huge then far[uid] = true end
        end
    end
    lanes.hot, lanes.far = hot, far
end

Decisions.stateProfileKeys = {}

function Decisions.think(uid, now)
    Decisions.lanes.thoughtAtMs[uid] = now
    local started = nowMs()

    local actor, state = Registry.read(uid), Decisions.states[uid]
    Decisions.profileAdd("read", nowMs() - started)
    if actor and actor.lifecycle == "active" then
        local shell = shellFor(actor)
        if shell ~= nil then
            local nextState = update(actor, shell,
                state or { kind = "idle", intent = "scan", cooldownUntilMs = 0 }, now)
            Decisions.states[uid] = nextState
            stampState(shell, nextState)
        end
    end
    local spent = nowMs() - started
    Decisions.profileAdd("think", spent)

    local kind = tostring(type(state) == "table" and state.kind or "none")
    local key = Decisions.stateProfileKeys[kind]
    if key == nil then
        key = "state:" .. kind
        Decisions.stateProfileKeys[kind] = key
    end
    Decisions.profileAdd(key, spent)
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then runtime.noteDetail(key, spent) end
    end
end

Decisions.tickStartedMs = nil
Decisions.tickThinkMs = 0
function Decisions.budgetSpent()
    return nowMs() - (Decisions.tickStartedMs or nowMs())
        >= (tonumber(Decisions.lanes.budgetMs) or math.huge)
end

Decisions.phaseDetailKeys = {
    perception = "decide:perception", response = "decide:response", passive = "decide:passive",
    endurance = "decide:endurance", audible = "decide:audible",
}

function Decisions.notePhase(name, spent)
    spent = tonumber(spent) or 0
    Decisions.profileAdd(name, spent)
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail(Decisions.phaseDetailKeys[name] or name, spent)
        end
    end
end

function Decisions.restPassive(uid, now)
    local lanes = Decisions.lanes
    local stretch = tonumber(lanes.stretch) or 1
    if stretch <= 1 or Decisions.passiveScannedAtMs[uid] ~= now or Decisions.passiveQuietAtMs[uid] ~= nil then return end
    local rest = math.min(tonumber(lanes.passiveMidMs) or 1000, (tonumber(lanes.passiveHotMs) or 250) * stretch)
    Decisions.passiveRestUntilMs[uid] = now + rest
    Decisions.metrics.passiveRested = (Decisions.metrics.passiveRested or 0) + 1
end

function Decisions.noteCost(uid, spent)
    local lanes = Decisions.lanes
    local costs = lanes.costMs
    if costs == nil then
        costs = {}
        lanes.costMs = costs
    end
    local before = costs[uid]
    if before == nil or spent >= before then costs[uid] = spent
    else costs[uid] = before * 0.75 + spent * 0.25 end
    if lanes.meanCostMs == nil then lanes.meanCostMs = spent
    else lanes.meanCostMs = lanes.meanCostMs * 0.9 + spent * 0.1 end
    Decisions.tickThinkMs = (Decisions.tickThinkMs or 0) + spent
    local metrics = Decisions.metrics
    if spent > (metrics.worstMs or 0) then metrics.worstMs = spent end
end

function Decisions.thinkTimed(uid, now)
    local before = nowMs()
    Decisions.think(uid, now)
    Decisions.noteCost(uid, nowMs() - before)
end

function Decisions.fits(uid, processed)
    if processed < 1 then return true end
    local lanes = Decisions.lanes
    local budget = tonumber(lanes.budgetMs) or math.huge
    local used = nowMs() - (Decisions.tickStartedMs or nowMs())
    if used >= budget then return false end
    local costs = lanes.costMs
    local cost = costs ~= nil and costs[uid] or nil
    if cost == nil then cost = lanes.meanCostMs end
    return cost == nil or used + cost <= budget
end

function Decisions.carriedCount(now)
    local lanes = Decisions.lanes
    local carried = 0
    for _, uid in ipairs(Decisions.order) do
        local last = lanes.thoughtAtMs[uid] or -math.huge
        if last ~= now and not (lanes.far[uid] and now - last < lanes.farIntervalMs) then carried = carried + 1 end
    end
    return carried
end

function Decisions.shed(level)
    local base = Decisions.shedBase
    if level <= 1 then
        if base ~= nil then
            if Perception.maximumZombieCandidates == base.setCandidates then
                Perception.maximumZombieCandidates = base.candidates
            end
            if Perception.sightChecksPerPass == base.setQueries then
                Perception.sightChecksPerPass = base.queries
            end
            Decisions.shedBase = nil
        end
        return
    end
    if base == nil then
        base = { candidates = Perception.maximumZombieCandidates, queries = Perception.sightChecksPerPass }
        Decisions.shedBase = base
    end
    if type(base.candidates) ~= "number" or type(base.queries) ~= "number" then return end
    base.setCandidates = math.max(8, math.floor(base.candidates / level))
    base.setQueries = math.max(12, math.floor(base.queries / level))
    Perception.maximumZombieCandidates = base.setCandidates
    Perception.sightChecksPerPass = base.setQueries
end

function Decisions.settleLoad()
    local lanes = Decisions.lanes
    local alpha = tonumber(lanes.loadAlpha) or 0.15
    local load = (tonumber(lanes.loadMs) or 0) * (1 - alpha) + (Decisions.tickThinkMs or 0) * alpha
    lanes.loadMs = load
    local threshold = tonumber(lanes.stretchLoadMs) or 9
    local level = 1
    if load > threshold then level = math.min(tonumber(lanes.stretchMax) or 4, math.ceil(load / threshold)) end
    lanes.stretch = level
    Decisions.shed(level)
    local metrics = Decisions.metrics
    if level > 1 then metrics.stretchTicks = (metrics.stretchTicks or 0) + 1 end
    if (Decisions.tickThinkMs or 0) > (metrics.tickWorstMs or 0) then metrics.tickWorstMs = Decisions.tickThinkMs end
end

function Decisions.hotPhase(now, run)
    local lanes = Decisions.lanes
    local order = Decisions.order
    local count = #order
    local spent = Decisions.budgetSpent
    local fits = Decisions.fits
    local thoughtAt = lanes.thoughtAtMs
    for _ = 1, count do
        if run.processed >= run.maximum - run.reserve then break end
        local index = (Decisions.hotCursor % count) + 1
        local uid = order[index]
        if lanes.hot[uid] and now - (thoughtAt[uid] or -math.huge) >= lanes.hotIntervalMs then
            if run.processed > 0 and (spent() or not fits(uid, run.processed)) then
                run.sliced = true
                break
            end
            Decisions.hotCursor = index
            Decisions.thinkTimed(uid, now)
            run.processed = run.processed + 1
        else
            Decisions.hotCursor = index
        end
    end
end

function Decisions.roundPhase(now, run)
    local lanes = Decisions.lanes
    local order = Decisions.order
    local count = #order
    local fits = Decisions.fits
    local thoughtAt = lanes.thoughtAtMs
    local visited = 0
    local stretch = tonumber(lanes.stretch) or 1
    local gap = (tonumber(lanes.gapMs) or 100) * stretch
    local states, urgent = Decisions.states, Decisions.urgentKinds
    while run.processed < run.maximum and visited < count do
        local index = (Decisions.cursor % count) + 1
        local uid = order[index]
        local last = thoughtAt[uid] or -math.huge
        local skip = last == now
            or (lanes.far[uid] and now - last < lanes.farIntervalMs)
        if not skip and stretch > 1 and now - last < gap then
            local held = states[uid]
            if not (type(held) == "table" and urgent[held.kind] == true) then skip = true end
        end
        if skip then
            Decisions.cursor = index
            visited = visited + 1
        else
            if not fits(uid, run.processed) then
                run.sliced, run.blocked = true, true
                break
            end
            Decisions.cursor = index
            visited = visited + 1
            Decisions.thinkTimed(uid, now)
            run.processed = run.processed + 1
            run.roundProcessed = run.roundProcessed + 1
        end
    end
end

function Decisions.tick(budget)
    local now = nowMs()
    Decisions.tickStartedMs = now
    Decisions.tickThinkMs = 0
    sync(now)
    Decisions.refreshLanes(now)
    Decisions.profileAdd("prepare", nowMs() - now)
    local lanes = Decisions.lanes
    local maximum = math.min(#Decisions.order, math.max(1, math.floor(tonumber(budget) or 1)))
    local run = { processed = 0, maximum = maximum, roundProcessed = 0, sliced = false, blocked = false,
        reserve = math.min(tonumber(lanes.roundMinimum) or 0, math.max(0, maximum - 1)) }
    local metrics = Decisions.metrics
    if (tonumber(lanes.roundDebt) or 0) >= (tonumber(lanes.roundDebtLimit) or 2) then
        metrics.roundFirst = (metrics.roundFirst or 0) + 1
        run.reserve = 0
        Decisions.roundPhase(now, run)
        Decisions.hotPhase(now, run)
    else
        Decisions.hotPhase(now, run)
        Decisions.roundPhase(now, run)
    end
    if run.roundProcessed > 0 then lanes.roundDebt = 0
    elseif run.blocked then lanes.roundDebt = (tonumber(lanes.roundDebt) or 0) + 1 end
    if run.sliced then
        metrics.thinkSliced = (metrics.thinkSliced or 0) + 1
        metrics.thinkCarried = (metrics.thinkCarried or 0) + Decisions.carriedCount(now)
    end
    Decisions.settleLoad()
    Decisions.profileTick(nowMs(), nowMs() - now)
    return run.processed
end

return Decisions
