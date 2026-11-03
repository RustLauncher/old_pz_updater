require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Shells/ALifeNPCHitRelay"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Combat/ALifeLineOfFire"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Movement/ALifeMovement"
require "ProjectALife/Movement/ALifeObstacleTraversal"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Shells/ALifeGait"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Audio/ALifeVoice"
require "ProjectALife/Audio/ALifeHumanReactions"
require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Ledger = ProjectALife.ActionLedger
local Weapons = ProjectALife.Weapons
local Magazines = ProjectALife.MagazineState
local LineOfFire = ProjectALife.LineOfFire
local Animations = ProjectALife.Animations
local TargetPolicy = ProjectALife.TargetPolicy
local Traversal = ProjectALife.ObstacleTraversal
local defaults = ProjectALife.BehaviorSettings.combat
local Combat = {
    adapters = {}, sequence = 0, settings = {},
    metrics = { worldNoise = 0, unstuck = 0, noiseRefused = 0, climbHolds = 0,
        edgeQueueHolds = 0, edgeHolds = 0, edgeDetours = 0, edgeGiveUps = 0,
        clipDeferred = 0, rebuildsDeferred = 0, approachArcs = 0, approachStraight = 0,
        entranceLegs = 0, leashHolds = 0, fenceHolds = 0, friendlyRefused = 0,
        zombiesLetGo = 0, alarmsAnswered = 0, edgeLockWaits = 0, pathUnstarted = 0,
        meleeHeld = 0, meleeBackSteps = 0, critKnockdowns = 0,
        meleeStepIns = 0, meleeStepsDone = 0, meleeStepsCut = 0,
        crewSideSteps = 0, crewRetreats = 0, crewReturns = 0,

        attackTries = 0, attackRefusedBy = {}, shots = 0, swings = 0, shoves = 0, misses = 0,
        zombieStrikes = 0, zombieStruck = 0, actorHits = 0, playerHits = 0, playerHitFailures = 0,
        retaliationHandOffs = 0, bitersKept = 0, sortieTicks = 0,
        leashReturns = 0, leashRefused = 0,
        offersLeashed = 0, climbsCut = 0, watchesLifted = 0,
        stepOffs = 0, pathGiveUps = 0, leashGiveUps = 0, leashHoldsExtended = 0 },
    pathRequests = setmetatable({}, { __mode = "k" }),
    suppressions = {},

    leashRefusals = {},

    aimState = setmetatable({}, { __mode = "k" }),
    closingRunWindows = setmetatable({}, { __mode = "k" }),
}
ProjectALife.Combat = Combat

local function nowMs()
    if type(Combat.adapters.nowMs) == "function" then return Combat.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Combat.dataOf(body)
    local kind = type(body)
    if (kind ~= "table" and kind ~= "userdata") or type(body.getModData) ~= "function" then return nil end
    local data = body:getModData()
    if type(data) ~= "table" then return nil end
    return data
end

function Combat.peekData(body)
    local kind = type(body)
    if (kind ~= "table" and kind ~= "userdata") or body.getModData == nil then return nil end
    if body.hasModData ~= nil and body:hasModData() ~= true then return nil end
    return Combat.dataOf(body)
end

function Combat.xyOf(body)
    local kind = type(body)
    if (kind ~= "table" and kind ~= "userdata") or body.getX == nil or body.getY == nil then
        return nil
    end
    return body:getX(), body:getY()
end

function Combat.xyzOf(body)
    local kind = type(body)
    if (kind ~= "table" and kind ~= "userdata") or body.getX == nil or body.getY == nil
            or body.getZ == nil then
        return nil
    end
    return body:getX(), body:getY(), body:getZ()
end

local function stablePercent(value)
    local text, result = tostring(value or ""), 0
    for index = 1, #text do
        result = (result * 33 + string.byte(text, index)) % 2147483647
    end
    return result % 100
end

local function closingRunAllowed(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local movement = ProjectALife.BehaviorSettings.movement or {}
    local activeMs = math.max(250, math.floor(tonumber(movement.runActiveMs) or 650))
    local cycleMs = math.max(activeMs, math.floor(tonumber(movement.runCycleMs) or 14000))
    local state = Combat.closingRunWindows[shell]
    if state == nil or now - state.startedAtMs >= cycleMs then
        local cycle = state == nil and 0 or (state.cycle + 1)
        local percent = math.max(0, math.min(100,
            tonumber(Combat.settings.closingRunChancePercent) or 80))
        state = {
            cycle = cycle,
            startedAtMs = now,
            allowed = stablePercent(tostring(actor and actor.uid or "actor")
                .. ":closing:" .. tostring(cycle)) < percent,
        }
        Combat.closingRunWindows[shell] = state
    end
    return state.allowed == true and now - state.startedAtMs < activeMs
end

local function refreshReadyWindow(state, suppliedNow)
    if state == nil then return 0 end
    local minimum = math.max(0, tonumber(Combat.settings.combatReadyMinimumMs) or 8000)
    local maximum = math.max(minimum,
        tonumber(Combat.settings.combatReadyMaximumMs) or 10000)
    local duration = minimum
    if maximum > minimum then
        if type(Combat.adapters.rollReadyMs) == "function" then
            duration = tonumber(Combat.adapters.rollReadyMs(minimum, maximum)) or minimum
        elseif type(ZombRand) == "function" then
            duration = minimum + ZombRand(math.floor(maximum - minimum + 1))
        else
            duration = (minimum + maximum) * 0.5
        end
    end
    state.warmUntilMs = (tonumber(suppliedNow) or nowMs()) + duration
    return state.warmUntilMs
end

local function setVariable(shell, name, value)
    if shell == nil then return end
    if shell.SetVariable ~= nil then
        shell:SetVariable(name, tostring(value))
    elseif shell.setVariable ~= nil then
        shell:setVariable(name, tostring(value))
    end
end

local function setAimWalk(shell, enabled, reason)
    local data = Combat.dataOf(shell)
    enabled = enabled == true
    if data ~= nil and data.ProjectALifeAimWalk == enabled then return end
    setVariable(shell, "ALifeAimWalk", enabled)
    if data ~= nil then data.ProjectALifeAimWalk = enabled end
end

Combat.postureUntilMs = setmetatable({}, { __mode = "k" })
Combat.postureDecayMs = 4000

Combat.aimHoldUntilMs = setmetatable({}, { __mode = "k" })

function Combat.setPosture(actor, shell, threatened, suppliedNow)
    if shell == nil then return false end
    local now = tonumber(suppliedNow) or nowMs()
    local data = Combat.dataOf(shell)
    local phase = data ~= nil and tostring(data.ProjectALifeCombatPhase or "idle") or "idle"
    local combatOwnsAim = phase ~= "idle" and phase ~= "" and phase ~= "aborted"
    if threatened then
        Combat.postureUntilMs[shell] = now + Combat.postureDecayMs
        Combat.aimHoldUntilMs[shell] = now
            + (Combat.settings.aimHoldMs or 6000)
        if not combatOwnsAim then setAimWalk(shell, true, "target_seen") end
        if data ~= nil then data.ProjectALifeDangerPosture = "threat" end

        return true
    end
    local until_ = Combat.postureUntilMs[shell]
    if until_ == nil then return false end
    if now < until_ then

        local aimHold = Combat.aimHoldUntilMs[shell]
        if aimHold ~= nil and now >= aimHold then
            Combat.aimHoldUntilMs[shell] = nil
            if not combatOwnsAim then setAimWalk(shell, false, "alert") end
        end
        if data ~= nil then data.ProjectALifeDangerPosture = "alert" end
        return true
    end
    Combat.postureUntilMs[shell] = nil
    Combat.aimHoldUntilMs[shell] = nil
    if data ~= nil then data.ProjectALifeDangerPosture = "relaxed" end
    if not combatOwnsAim then
        setAimWalk(shell, false, "relaxed")
        pcall(function()
            local current = shell:getModData()
            current.ProjectALifeAimAtX, current.ProjectALifeAimAtY = nil, nil
            if shell:isAiming() then shell:setIsAiming(false) end
        end)
        pcall(Animations.setCombatHold, shell, false)
    end
    return false
end

local function variable(shell, name)
    local data = Combat.dataOf(shell)
    if data ~= nil then
        local value = data["Project" .. name]
        if value ~= nil then return value end
    end
    if shell == nil or shell.GetVariable == nil then return nil end
    return shell:GetVariable(name)
end

local function setPhase(shell, phase, tactic, distance)
    setVariable(shell, "ALifeCombatPhase", phase)
    setVariable(shell, "ALifeTactic", tactic or "direct")
    local data = Combat.dataOf(shell)
    if data ~= nil then
        data.ProjectALifeCombatPhase = phase
        data.ProjectALifeTacticalRole = tactic or "direct"
        data.ProjectALifeTargetDistance = distance
    end
end

local function targetAlive(target)
    if type(Combat.adapters.targetAlive) == "function" then
        if TargetPolicy.grappledCorpse(target) then return false end
        return Combat.adapters.targetAlive(target) == true
    end

    local kind = type(target)
    if (kind ~= "table" and kind ~= "userdata") or type(target.isDead) ~= "function"
            or target:isDead() == true then return false end
    local healthOk = type(target.getHealth) == "function"
    local health = healthOk and target:getHealth() or nil
    if healthOk and tonumber(health) ~= nil and health <= 0 then return false end
    local data = Combat.dataOf(target)
    if TargetPolicy.grappledCorpse(target, data, true) then return false end
    local owned = data ~= nil and (data.ProjectALifeOwned == true
        or data.ProjectALifeActor == true)
    if type(target.isOnKillDone) == "function" and target:isOnKillDone() == true
            and not (owned and healthOk and (tonumber(health) or 0) > 0) then return false end

    if type(target.getCurrentSquare) == "function" and target:getCurrentSquare() == nil then

        if type(target.getSquare) ~= "function" then return true end
        if target:getSquare() == nil then return false end
    end
    return true
end

Combat.targetValid = targetAlive

local function position(value)
    local x, y, z = Combat.xyzOf(value)
    if x == nil then return nil end
    return { x = x, y = y, z = z }
end

local function suppressionMoved(suppression, target)
    local current = position(target)
    if current == nil or suppression.position == nil then return false end
    local dx, dy, dz = current.x - suppression.position.x,
        current.y - suppression.position.y, current.z - suppression.position.z
    local distance = tonumber(Combat.settings.suppressionResetDistance) or 4
    return dx * dx + dy * dy + dz * dz >= distance * distance
end

function Combat.watchInReach(watch, target)
    if type(watch) ~= "table" then return false end
    local tx, ty, tz = Combat.xyzOf(target)
    local reach = tonumber(watch.reach)
    if tx == nil or reach == nil or tonumber(watch.x) == nil or tonumber(watch.y) == nil then return false end
    local dz = tz - (tonumber(watch.z) or tz)
    if watch.melee == true and math.abs(dz) >= 0.4 then return false end
    local dx, dy = tx - watch.x, ty - watch.y
    return dx * dx + dy * dy + dz * dz <= reach * reach
end

function Combat.pathGoalMatches(shell, request)
    if type(request) ~= "table" or shell.getPathFindBehavior2 == nil then return true end
    local behavior = shell:getPathFindBehavior2()
    if behavior == nil or behavior.getTargetX == nil or behavior.getTargetY == nil then return true end
    local rx, ry = tonumber(request.x), tonumber(request.y)
    if rx == nil or ry == nil then return true end
    local dx, dy = behavior:getTargetX() - rx, behavior:getTargetY() - ry
    return dx * dx + dy * dy <= 1
end

function Combat.finishDeferredCancel(shell, state)
    if Combat.inClip(shell) then return false end
    local leftover = state.cancelAfterClip
    state.cancelAfterClip = nil
    if Combat.pathRequests[shell] ~= nil then return false end
    local data = Combat.dataOf(shell)
    local phase = data ~= nil and tostring(data.ProjectALifeCombatPhase or "idle") or "idle"
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return false end
    local ok, same = pcall(Combat.pathGoalMatches, shell, leftover)
    if ok and same == false then return false end
    Combat.cancelPath(shell)
    Combat.metrics.clipCancelsFinished = (Combat.metrics.clipCancelsFinished or 0) + 1
    return true
end

function Combat.relax(shell, suppliedNow)
    if shell == nil then return false end
    local state = Combat.aimState[shell]
    if state == nil then return false end
    if state.cancelAfterClip ~= nil then Combat.finishDeferredCancel(shell, state) end
    local now = tonumber(suppliedNow) or nowMs()
    if now < (state.warmUntilMs or 0) then return false end

    local phase = "idle"
    local data = Combat.dataOf(shell)
    if data ~= nil then phase = tostring(data.ProjectALifeCombatPhase or "idle") end
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return false end

    state.readyAtMs = nil
    state.warmUntilMs = 0
    if Animations.combatHold[shell] ~= true then return false end
    setAimWalk(shell, false, "relaxed")
    pcall(Animations.setCombatHold, shell, false)
    Animations.clear(shell)
    return true
end

function Combat.canEngage(actor, target, suppliedNow, suppliedShell)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or target == nil then
        return false, "combat_target_missing"
    end

    if type(Combat.postTargetRefused) == "function"
            and Combat.postTargetRefused(actor, suppliedShell, target, tonumber(suppliedNow) or nowMs()) then
        return false, "combat_target_off_leash"
    end
    if Combat.leashRefusals ~= nil and Combat.leashRefusals[actor.uid] ~= nil
            and Combat.offLeashRefused ~= nil then
        local refused, refusedUntilMs = Combat.offLeashRefused(actor, target, tonumber(suppliedNow) or nowMs())
        if refused then return false, "combat_target_off_leash", refusedUntilMs end
    end
    local suppression = Combat.suppressions[actor.uid]
    if suppression == nil or suppression.target ~= target then return true end
    local now = tonumber(suppliedNow) or nowMs()
    if now >= suppression.untilMs or suppressionMoved(suppression, target) then
        Combat.suppressions[actor.uid] = nil
        return true
    end
    if suppression.watch ~= nil and Combat.watchInReach(suppression.watch, target) then
        Combat.suppressions[actor.uid] = nil
        Combat.metrics.watchesLifted = (Combat.metrics.watchesLifted or 0) + 1
        return true
    end
    return false, suppression.reason or "combat_target_unreachable", suppression.untilMs
end

function Combat.canBegin(actor, target, suppliedNow, suppliedShell)
    if not Combat.targetAlive(target) then return false, "combat_target_dead" end
    if type(Combat.offLimits) == "function" and Combat.offLimits(actor, target) then
        return false, "combat_hostile_off"
    end
    local engageable, reason, untilMs = Combat.canEngage(actor, target, suppliedNow, suppliedShell)
    if not engageable then return false, reason, untilMs end
    local allowed, policyReason = TargetPolicy.canAttack(target, nil, actor)
    if not allowed then return false, policyReason end
    return true
end

function Combat.retaliating(actor, target, now)
    local perception = ProjectALife.Perception
    local grudge = perception ~= nil and type(perception.attackers) == "table"
        and perception.attackers[actor.uid] or nil
    return type(grudge) == "table" and grudge.attacker == target
        and (tonumber(now) or nowMs()) < (tonumber(grudge.untilMs) or 0)
end

local function suppress(actor, target, reason, now)

    local watch = Combat.pendingWatch
    Combat.pendingWatch = nil
    if type(watch) ~= "table" or watch.uid ~= actor.uid or watch.target ~= target then watch = nil end
    local previous = Combat.suppressions[actor.uid]
    local strikes = 1
    if previous ~= nil and previous.target == target then
        strikes = (previous.strikes or 1) + 1
    end

    local cooldown = math.min(20000,
        Combat.settings.unreachableCooldownMs * (2 ^ (strikes - 1)))
    if watch ~= nil then
        cooldown = math.max(cooldown, tonumber(Combat.settings.watchCooldownMs) or 8000)
    end
    Combat.suppressions[actor.uid] = {
        target = target,

        reason = watch ~= nil and "combat_leash_watch" or reason or "combat_target_unreachable",
        position = position(target),
        untilMs = now + cooldown,
        strikes = strikes,
        watch = watch,
    }
    if watch ~= nil then return end

    if strikes >= 3 and reason ~= "combat_fence_standoff"
            and not Combat.retaliating(actor, target, now) then
        pcall(function()
            local perception = ProjectALife.Perception
            if perception ~= nil and type(perception.ignore) == "function" then
                perception.ignore(actor.uid, target, 15000)
            end
        end)
    end
end

local function weaponFor(shell)
    return Weapons.current(shell)
end

local function shoveReady(shell, now)
    local data = Combat.dataOf(shell)
    if data == nil then return true end
    local ready = now >= (tonumber(data.ProjectALifeNextShoveAtMs) or 0)
    if ready then

        local tempo = type(Combat.tiredTempo) == "function" and Combat.tiredTempo(shell) or 1
        data.ProjectALifeNextShoveAtMs = now + math.floor(2500 * tempo)
    end
    return ready
end

local function aimStateFor(shell)
    local state = Combat.aimState[shell]
    if state == nil then

        state = { racked = true, readyAtMs = nil, warmUntilMs = 0 }
        Combat.aimState[shell] = state
    end
    return state
end

local function traverseFraction(shell, target)
    local cosine
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(target)
    local forward = sx ~= nil and tx ~= nil and shell.getForwardDirection ~= nil
        and shell:getForwardDirection() or nil
    if forward ~= nil then
        local fx, fy = forward:getX(), forward:getY()
        local dx, dy = tx - sx, ty - sy
        local reach = math.sqrt(dx * dx + dy * dy)
        local facing = math.sqrt(fx * fx + fy * fy)
        if reach > 0.01 and facing > 0.01 then
            cosine = (fx * dx + fy * dy) / (reach * facing)
        end
    end
    if cosine == nil then return 0 end
    return (1 - math.max(-1, math.min(1, cosine))) * 0.5
end

function Combat.muzzleOnTarget(shell, target, tolerance)
    local limit = tonumber(tolerance)
        or (Combat.settings and Combat.settings.facingTraverseMaximum)
        or 0.18
    return traverseFraction(shell, target) <= limit
end

local function targetIsHuman(target)
    local kind = type(target)
    if kind ~= "table" and kind ~= "userdata" then return true end
    if target.isZombie == nil or target:isZombie() ~= true then return true end
    local data = Combat.dataOf(target)
    return data ~= nil and (data.ProjectALifeOwned == true
        or data.ProjectALifeActor == true)
end

local function targetIsDown(target)
    local kind = type(target)
    if kind ~= "table" and kind ~= "userdata" then return false end
    if target.isProne ~= nil and target:isProne() == true then return true end
    if target.isOnFloor ~= nil and target:isOnFloor() == true then return true end
    if target.isKnockedDown ~= nil and target:isKnockedDown() == true then return true end
    if target.isCrawling ~= nil and target:isCrawling() == true then return true end
    if target.getVariableBoolean ~= nil and target:getVariableBoolean("bOnFloor") == true then
        return true
    end
    if target.getActionStateName == nil then return false end
    local value = string.lower(tostring(target:getActionStateName() or ""))
    return value == "onground" or value == "sitonground"
        or value == "falldown" or value == "knockeddown" or value == "getup"
end

Combat.aimBodyHalfWidth = 0.3

function Combat.reactionDelayMs(milliseconds)
    return math.floor(math.max(0, tonumber(milliseconds) or 0)
        * ProjectALife.FeatureGate.number("Combat_ReactionDelayPercent", 75, 25, 200) / 100)
end

function Combat.aimSettleMs(shell, target, weapon, distance, warm, actor)
    local s = Combat.settings or {}
    local raise = warm and (tonumber(s.aimWarmMs) or 120) or (tonumber(s.aimBaseMs) or 300)
    local swing = traverseFraction(shell, target) * (tonumber(s.aimTraverseMs) or 380)
    local subtended = math.atan(Combat.aimBodyHalfWidth / math.max(0.5, tonumber(distance) or 0))

    local halvings = math.max(0, math.log(0.12 / subtended) / math.log(2))
    local settle = halvings * (tonumber(s.aimPrecisionMs) or 90)
    local rating = 5
    local data = Combat.dataOf(shell)
    if data ~= nil then rating = tonumber(data.ProjectALifeAiming) or rating end
    settle = settle * math.max(0.6, math.min(1.4, 1.4 - rating * 0.08))
    if weapon ~= nil and weapon.getAimingTime ~= nil then
        local aimingTime = tonumber(weapon:getAimingTime())
        if aimingTime ~= nil and aimingTime > 0 then
            settle = settle * math.max(0.7, math.min(1.4, aimingTime / 25))
        end
    end
    local cap = tonumber(s.aimMaximumMs) or 750
    local gunner = data ~= nil and (data.ProjectALifeConduct == "gunner"
        or data.ProjectALifeConductSecondaryGunner == true)
    if gunner then

        raise = math.min(raise, tonumber(s.aimWarmMs) or 120)
        settle = settle * 0.5
        cap = 600
    end

    local place = 0
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) == "table" then place = math.floor(tonumber(memory.groupIndex) or 0) % 4 end
    return Combat.reactionDelayMs(math.max(0, math.min(cap, raise + swing + settle + place * 55)))
end

local function isUnarmed(weapon)
    if weapon == nil then return true end
    if weapon.getFullType == nil then return false end
    return tostring(weapon:getFullType()) == "Base.BareHands"
end

local function distanceSquared(shell, target)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(target)
    if sx == nil or tx == nil then return math.huge end
    local dx, dy, dz = sx - tx, sy - ty, sz - tz
    return dx * dx + dy * dy + dz * dz
end

local function isRanged(weapon)
    if weapon == nil then return false end
    if weapon.isAimedFirearm ~= nil then return weapon:isAimedFirearm() == true end
    if weapon.isRanged ~= nil then return weapon:isRanged() == true end
    return false
end

function Combat.unstick(shell, reason)
    if shell == nil then return false end
    pcall(function() Animations.clear(shell) end)
    Combat.aimState[shell] = nil
    Combat.pathRequests[shell] = nil
    Combat.closingRunWindows[shell] = nil

    if not (type(Combat.inClip) == "function" and Combat.inClip(shell)) then
        pcall(function()
            local movement = ProjectALife.Movement
            if movement ~= nil and type(movement.stop) == "function" then movement.stop(shell) end
        end)
        pcall(function()
            if Traversal ~= nil and type(Traversal.cancel) == "function" then Traversal.cancel(shell, "combat_unstick") end
        end)
    end
    local uid
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        uid = data.ProjectALifeUID
        data.ProjectALifeCombatPhase = nil
        data.ProjectALifeCombatTactic = nil
        data.ProjectALifeAimWalk = nil
        data.ProjectALifeGuardUntilMs = nil
        data.ProjectALifeSprintUntilMs = nil
        data.ProjectALifeNextStrikeAtMs = nil
    end)
    if uid ~= nil and tostring(uid) ~= "" then
        pcall(function()
            local registry = ProjectALife.ActorRegistry
            local actor = registry ~= nil and registry.read(tostring(uid)) or nil
            if type(actor) == "table" and Ledger ~= nil then
                Ledger.cancelActor(actor.uid, actor.generation,
                    "combat_freeze:" .. tostring(reason or "unknown"))
            end
        end)
    end
    Combat.metrics = Combat.metrics or {}
    Combat.metrics.unstuck = (Combat.metrics.unstuck or 0) + 1
    pcall(function()
        local blackBox = ProjectALife.BlackBox
        if blackBox ~= nil then blackBox.note(shell, "unstick", tostring(reason or "freeze")) end
    end)
    return true
end

function Combat.approachAimWalk(weapon, distance, guardRange, aim, target)
    local range
    if isRanged(weapon) then
        range = Combat.settings.aimWalkRangedRange or 14
    else
        range = math.max(0, tonumber(guardRange) or 0)
    end
    distance = tonumber(distance) or math.huge
    if aim == nil then return distance <= range end
    if aim.aimWalkTarget ~= target then
        aim.aimWalkTarget, aim.inAimWalkBand = target, false
    end
    local inBand = distance <= range + (aim.inAimWalkBand == true and 0.5 or 0)
    aim.inAimWalkBand = inBand
    return inBand
end

function Combat.stampAim(shell, target)
    if shell == nil then return end
    local data = Combat.dataOf(shell)
    local ax, ay = Combat.xyOf(target)
    if data ~= nil and ax ~= nil then
        data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = ax, ay

        data.ProjectALifeDangerPosture = "threat"
    end
    local now = nowMs()
    Combat.postureUntilMs[shell] = now + Combat.postureDecayMs
    Combat.aimHoldUntilMs[shell] = now + (Combat.settings.aimHoldMs or 6000)
end

function Combat.downedBonus(target)
    local kind = type(target)
    if (kind == "table" or kind == "userdata") and target.isOnFloor ~= nil
            and target:isOnFloor() == true then
        return 1.5
    end
    return 1
end

function Combat.closeQuarters(shell, target, distance)
    if shell == nil then return false end
    local settings = Combat.settings
    if distance ~= nil and distance > (settings.closeQuartersRange or 9) then
        return false
    end
    local square = shell.getSquare ~= nil and shell:getSquare() or nil
    if square ~= nil and square.getBuilding ~= nil and square:getBuilding() ~= nil then return true end
    if target == nil or distance == nil or distance > 4 or target.getSquare == nil then return false end
    square = target:getSquare()
    return square ~= nil and square.getBuilding ~= nil and square:getBuilding() ~= nil
end

function Combat.limping(shell)
    local data = Combat.dataOf(shell)
    return data ~= nil and data.ProjectALifeWoundLeg == true
end

function Combat.kindOf(body)

    if body == nil or type(instanceof) ~= "function" then return "zombie" end
    if instanceof(body, "IsoPlayer") then return "player" end
    local data = Combat.dataOf(body)
    if data ~= nil and data.ProjectALifeOwned == true then return "actor" end
    return "zombie"
end

function Combat.peekKind(body)
    if body == nil or type(instanceof) ~= "function" then return "zombie" end
    if instanceof(body, "IsoPlayer") then return "player" end
    local data = Combat.peekData(body)
    if data ~= nil and data.ProjectALifeOwned == true then return "actor" end
    return "zombie"
end

function Combat.targetIsGunman(target)
    local kind = type(target)
    if (kind ~= "table" and kind ~= "userdata") or target.getModData == nil then return false end
    local data = target:getModData()
    if type(data) == "table" and data.ProjectALifeOwned == true then
        local carry = data.ProjectALifeWeaponClass
        return carry == "rifle" or carry == "handgun"
    end
    if type(instanceof) ~= "function" or not instanceof(target, "IsoPlayer") then return false end

    local item = target.getPrimaryHandItem ~= nil and target:getPrimaryHandItem() or nil
    if item == nil then return false end
    if item.isAimedFirearm ~= nil and item:isAimedFirearm() == true then return true end
    item = target.getSecondaryHandItem ~= nil and target:getSecondaryHandItem() or nil
    return item ~= nil and item.isAimedFirearm ~= nil and item:isAimedFirearm() == true
end

local function maximumRange(weapon, shell)
    local range = 12
    if weapon ~= nil and weapon.getMaxRange ~= nil then
        range = math.max(2, math.min(40, tonumber(weapon:getMaxRange()) or 12))
    end

    local data = Combat.dataOf(shell)
    if data ~= nil and data.ProjectALifeConduct == "sniper" then
        range = range * 1.5
    end
    return range
end

local function meleeReach(weapon)
    if weapon == nil then return Combat.settings.meleeRange end
    local value = weapon.getMaxRange ~= nil and tonumber(weapon:getMaxRange()) or nil
    if value == nil or value <= 0 or value > 3 then
        return Combat.settings.meleeRange
    end

    return math.max(0.7, value)
end

function Combat.meleeBodyRadius(target)
    local radius = 0.24
    if target ~= nil and target.getWidth ~= nil then
        local ok, measured = pcall(function() return tonumber(target:getWidth()) end)
        if ok and measured ~= nil and measured > 0 and measured <= 0.5 then
            radius = measured
        end
    end
    return radius
end

local function meleeReachFor(weapon, target)
    return meleeReach(weapon) + Combat.meleeBodyRadius(target)
end

local function desiredRange(weapon, shell)

    if not isRanged(weapon) then

        local reach = meleeReach(weapon)
        return math.max(0.62, math.min(reach * 0.85, reach - 0.1))
    end
    if Weapons.firesPellets(weapon) then
        return math.max(2.75, math.min(4.5, maximumRange(weapon, shell) * 0.5))
    end

    if Combat.closeQuarters(shell) then
        return math.max(1.2, math.min(Combat.settings.closeQuartersStandoff or 2.4,
            maximumRange(weapon, shell) * 0.5))
    end
    return math.max(Combat.settings.rangedStandoffMinimum,
        math.min(Combat.settings.rangedStandoffMaximum, maximumRange(weapon, shell) * 0.62))
end

function Combat.holdReach(weapon, shell, target)
    if weapon == nil or not isRanged(weapon) then return nil end
    if Weapons.firesPellets(weapon) then return nil end
    return Combat.capForPlayer(maximumRange(weapon, shell)
        * (tonumber(Combat.settings.rangedReachFactor) or 1), shell, target)
end

function Combat.engagementReach(weapon, shell, target)
    local reach = maximumRange(weapon, shell) * Combat.settings.rangedReachFactor
    if Weapons.firesPellets(weapon) then
        local bands = ProjectALife.SquadTactics.bands
        reach = math.min(reach, desiredRange(weapon, shell) * bands.holdCeiling)
    end
    return Combat.capForPlayer(reach, shell, target)
end

function Combat.playerFireReach(shell, target)
    if target == nil or Combat.kindOf(target) ~= "player" then return nil end
    local data = Combat.dataOf(shell)
    local sniper = data ~= nil and data.ProjectALifeConduct == "sniper"
    local s = Combat.settings
    if sniper then return tonumber(s.marksmanPlayerFireReach) or 34 end
    return tonumber(s.playerFireReach) or 22
end

function Combat.capForPlayer(reach, shell, target)
    local cap = Combat.playerFireReach(shell, target)
    if cap ~= nil and cap < reach then return cap end
    return reach
end

local function canSee(shell, target)
    if shell == nil or target == nil or shell.CanSee == nil then return false end

    local watcher = ProjectALife.Perception
    if watcher ~= nil and type(watcher.engineCanSee) == "function" then
        return watcher.engineCanSee(shell, target) == true
    end
    local ok, result = pcall(shell.CanSee, shell, target)
    return ok and result == true
end

function Combat.plainRangedLine(shell, target)
    if not LineOfFire.hasClearBoundary(shell, target) then
        return false, "blocked"
    end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.visible) == "function"
            and perception.visible(shell, target) ~= true then
        return false, "not_visible"
    end
    return true, "clear"
end

local function clearAttackLine(shell, target, weapon, forceMelee, knownSquared)

    local squared = tonumber(knownSquared) or distanceSquared(shell, target)
    local closeContact = squared <= 2.25

    if weapon ~= nil and isRanged(weapon) and forceMelee ~= true then
        local control = ProjectALife.FireControl
        if control ~= nil then return control.rangedLine(shell, target) end
        return Combat.plainRangedLine(shell, target)
    end
    if type(LineOfFire.hasClearBoundary) ~= "function" then return false, "boundary" end
    local checked, clear = pcall(LineOfFire.hasClearBoundary, shell, target, "melee")
    if not checked or clear ~= true then return false, "boundary" end
    local shellSquare = shell ~= nil and shell.getCurrentSquare ~= nil
        and shell:getCurrentSquare() or nil
    local targetSquare = target ~= nil and target.getCurrentSquare ~= nil
        and target:getCurrentSquare() or nil
    if squared <= 4
            and shellSquare ~= nil and targetSquare ~= nil then
        local adjacentOk, hardCover = pcall(function()
            local wall = shellSquare:isWallTo(targetSquare)
                or targetSquare:isWallTo(shellSquare)
            local lowFence = shellSquare:isHoppableTo(targetSquare) == true
                or targetSquare:isHoppableTo(shellSquare) == true

            if wall or (lowFence and (forceMelee == true or (weapon ~= nil and not isRanged(weapon)))) then
                return true
            end

            if forceMelee == true or (weapon ~= nil and not isRanged(weapon)) then
                local window = shellSquare:getWindowTo(targetSquare)
                    or targetSquare:getWindowTo(shellSquare)
                if window ~= nil and window.isBarricaded ~= nil and window:isBarricaded() == true then return true end
                if window ~= nil and window:IsOpen() ~= true
                        and window:isSmashed() ~= true then return true end
                local door
                pcall(function()
                    door = shellSquare:getDoorTo(targetSquare)
                        or targetSquare:getDoorTo(shellSquare)
                end)
                if door ~= nil and door:IsOpen() ~= true then return true end
            end
            return false
        end)
        if adjacentOk and hardCover == true then

            return false, "boundary"
        end
    end

    if type(Combat.adapters.lineClear) == "function" then
        local ok, result = pcall(Combat.adapters.lineClear, shell, target)
        return ok and result == true, ok and "blocked" or "line_check_failed"
    end

    if canSee(shell, target) then return true, "visible" end
    if closeContact then return true, "contact" end

    local rayClear = LineOfFire.tileRayClear(shell, target)
    if rayClear == false then return false, "blocked" end
    if rayClear ~= true then return false, "not_visible" end
    return true, "clear"
end

local function faceTarget(shell, target)

    Combat.stampAim(shell, target)
    return true
end

local function currentAmmo(weapon)
    return Magazines.current(weapon)
end

local function consumeRound(shell, weapon)
    return Magazines.consumeRound(shell, weapon)
end

function Combat.downedNow(untilMs)
    local now = nowMs()
    local health = ProjectALife.Health
    if health ~= nil and type(health.downedHolds) == "function" then
        return health.downedHolds(untilMs, now) == true
    end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.downedHolds) == "function" then
        return fence.downedHolds(untilMs, now) == true
    end
    local limit = tonumber(untilMs)
    return limit ~= nil and now < limit
end

local function attackIncapacitated(shell)

    if shell == nil then return false end
    if shell.isDead ~= nil and shell:isDead() == true then return true end

    local data = Combat.dataOf(shell)
    if data ~= nil and nowMs() < (tonumber(data.ProjectALifeStaggerUntilMs) or 0) then
        return true
    end

    if data ~= nil and data.ProjectALifeDownedUntilMs ~= nil
            and Combat.downedNow(data.ProjectALifeDownedUntilMs) then
        return true
    end
    local unable = false
    if shell.getActionStateName ~= nil and shell.isProne ~= nil and shell.isCrawling ~= nil then
        local state = tostring(shell:getActionStateName() or "")
        unable = shell:isProne() == true or shell:isCrawling() == true
            or state == "onground" or state == "sitonground"
            or state == "staggerback" or state == "getup"
            or state == "knockeddown" or state == "falldown"
    end
    if not unable then
        local current = Animations.current[shell]
        unable = current == "hit_react" or current == "get_up_front"
            or current == "get_up_back"
    end
    return unable
end

function Combat.hostileToActor(actor, body, shell)

    if shell ~= nil and Combat.comradeBody(shell, body) then return false end
    local hostile = true
    pcall(function()
        local data = Combat.dataOf(body)
        if data == nil then return end
        local uid = data.ProjectALifeUID
        if data.ProjectALifeOwned ~= true and data.ProjectALifeActor ~= true
                and type(uid) ~= "string" then return end
        hostile = false
        local registry = ProjectALife.ActorRegistry
        local relations = ProjectALife.Relations
        if registry == nil or relations == nil or type(uid) ~= "string" then return end
        local other = (registry.peek or registry.read)(uid)
        if other == nil then return end
        hostile = relations.hostile(actor, other) == true
    end)
    return hostile
end

function Combat.comradeBody(shell, body)
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.isComrade) ~= "function" or body == nil then return false end
    return perception.isComrade(shell, body) == true
end

function Combat.friendlyBody(actor, shell, body)
    if body == nil then return false end
    if Combat.comradeBody(shell, body) then return true, "comrade" end
    local data = Combat.peekData(body)
    if data == nil or (data.ProjectALifeOwned ~= true and data.ProjectALifeActor ~= true) then
        return false
    end
    local uid = data.ProjectALifeUID
    local registry = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or registry == nil or type(actor) ~= "table" then return true, "norecord" end
    local other = (registry.peek or registry.read)(uid)
    if other == nil then return true, "norecord" end
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.hostile) ~= "function" then return false end
    if relations.hostile(actor, other) == true then return false end
    local perception = ProjectALife.Perception
    local grudge = perception ~= nil and type(perception.attackers) == "table"
        and perception.attackers[actor.uid] or nil
    if type(grudge) == "table" and grudge.attacker == body
            and nowMs() < (tonumber(grudge.untilMs) or 0) then return false end
    return true, "friendly"
end

function Combat.comradeTarget(actor, target, shell)
    if shell ~= nil then
        local friendly, why = Combat.friendlyBody(actor, shell, target)
        if friendly and why == "norecord" and type(actor) == "table" and type(actor.uid) == "string" then
            Combat.suppress(actor, target, "combat_target_unreachable", nowMs())
        end
        if friendly and why ~= "friendly" then return true end
    end
    local data = Combat.peekData(target)
    if data == nil or (data.ProjectALifeOwned ~= true and data.ProjectALifeActor ~= true) then
        return false
    end
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.comrade) ~= "function"
            or perception.comrade(actor, target) ~= true then return false end
    if type(perception.logTarget) == "function" then
        pcall(perception.logTarget, actor, target, "actor", "drop")
    end
    return true
end

function Combat.zombieRelease(actor, shell, target, kind, now)
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.zombieReach) ~= "function"
            or type(actor) ~= "table" or type(actor.uid) ~= "string" then return nil end
    if (kind ~= nil and kind ~= "zombie") or Combat.peekKind(target) ~= "zombie" then return nil end
    if type(perception.grudgeHolds) == "function" then
        if perception.grudgeHolds(actor.uid, target, now) then return nil end
    elseif type(Combat.currentGrudge) == "function" and Combat.currentGrudge(actor) == target then
        return nil
    end
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(target)
    if sx == nil or tx == nil then return nil end
    local flat = (sx - tx) ^ 2 + (sy - ty) ^ 2
    local hold = (tonumber(perception.zombieReach(shell)) or math.huge)
        * (tonumber(perception.zombieHoldFactor) or 1.4)
    if flat > hold * hold then return "far" end
    if flat > (tonumber(perception.dangerRingSquared) or 64)
            and type(perception.lastKnownFor) == "function" then
        local lead = perception.lastKnownFor(actor, now)
        if type(lead) == "table" and lead.shared == true
                and (lead.kind == "player" or lead.kind == "actor") then
            return "alarm"
        end
    end
    return nil
end

function Combat.letZombieGo(actor, shell, target, why)
    local perception = ProjectALife.Perception
    local uid = type(actor) == "table" and actor.uid or nil
    if perception ~= nil and uid ~= nil then
        local held = type(perception.engagements) == "table" and perception.engagements[uid] or nil
        if type(held) == "table" and held.target == target then perception.engagements[uid] = nil end
        local lead = type(perception.lastKnown) == "table" and perception.lastKnown[uid] or nil
        if type(lead) == "table" and lead.target == target and lead.shared ~= true then
            perception.lastKnown[uid] = nil
        end
    end
    if why == "alarm" then
        Combat.metrics.alarmsAnswered = (Combat.metrics.alarmsAnswered or 0) + 1
    else
        Combat.metrics.zombiesLetGo = (Combat.metrics.zombiesLetGo or 0) + 1
    end
    local state = Combat.aimState[shell]
    if state ~= nil then
        state.warmUntilMs = math.max(tonumber(state.warmUntilMs) or 0,
            nowMs() + (tonumber(Combat.settings.combatReadyMinimumMs) or 0))
    end

    if not Combat.inClip(shell) and Traversal ~= nil and type(Traversal.isBusy) == "function"
            and type(Traversal.cancel) == "function" and Traversal.isBusy(shell) then
        pcall(Traversal.cancel, shell, "combat_release")
    end
    Combat.disengage(shell)
    if why == "alarm" then
        local data = Combat.dataOf(shell)
        if data ~= nil then data.ProjectALifeCombatLullUntilMs = nil end
    end
    return true
end

local function attackPosition(shell, target, weapon)

    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(target)
    local levelOk = sx ~= nil and tx ~= nil
    local squared = math.huge
    if levelOk then
        local dx, dy, dz = sx - tx, sy - ty, sz - tz
        squared = dx * dx + dy * dy + dz * dz
    end
    local distance = math.sqrt(squared)
    local ranged = isRanged(weapon)

    local levelGap = levelOk and math.abs(sz - tz) or nil

    local crossStorey = levelOk and isRanged(weapon)
        and (tonumber(levelGap) or 0) <= LineOfFire.settings.maximumStoreys + 0.4
    if levelOk and (tonumber(levelGap) or 0) >= 0.4 and not crossStorey then
        local fx, fy = sx - tx, sy - ty
        return false, math.sqrt(fx * fx + fy * fy), "different_level"
    end

    if levelOk and not ranged then
        local fx, fy = sx - tx, sy - ty
        local flat = math.sqrt(fx * fx + fy * fy)
        if levelGap >= 0.4 then

            return false, flat, "different_level"
        end
        distance = flat
    end
    local clear, lineReason = clearAttackLine(shell, target, weapon, nil, squared)
    local lineData = Combat.dataOf(shell)
    if lineData ~= nil then
        lineData.ProjectALifeLastLineClear = clear == true
        lineData.ProjectALifeLastLineReason = tostring(lineReason or "unknown")
    end
    if not clear then return false, distance, lineReason end

    if not ranged and targetIsDown(target) then
        local close = distance <= meleeReachFor(weapon, target)
        return close, distance, close and "ready" or "out_of_range"
    end
    if ranged then

        if distance > Combat.engagementReach(weapon, shell, target) then
            return false, distance, "out_of_range"
        end
        return true, distance, "ready"
    end
    local reach = meleeReachFor(weapon, target)
    return distance <= reach, distance, distance <= reach and "ready" or "out_of_range"
end

function Combat.configure(adapters)
    Combat.adapters = adapters or {}
    Combat.pathRequests = setmetatable({}, { __mode = "k" })
    Combat.closingRunWindows = setmetatable({}, { __mode = "k" })
    Combat.suppressions = {}
    Combat.leashRefusals = {}
    Combat.metrics = { worldNoise = 0, unstuck = 0, noiseRefused = 0, climbHolds = 0,
        edgeQueueHolds = 0, edgeHolds = 0, edgeDetours = 0, edgeGiveUps = 0,
        clipDeferred = 0, rebuildsDeferred = 0, approachArcs = 0, approachStraight = 0,
        entranceLegs = 0, leashHolds = 0, fenceHolds = 0, friendlyRefused = 0,
        zombiesLetGo = 0, alarmsAnswered = 0, edgeLockWaits = 0, pathUnstarted = 0,
        meleeHeld = 0, meleeBackSteps = 0, critKnockdowns = 0,
        meleeStepIns = 0, meleeStepsDone = 0, meleeStepsCut = 0,
        crewSideSteps = 0, crewRetreats = 0, crewReturns = 0,

        attackTries = 0, attackRefusedBy = {}, shots = 0, swings = 0, shoves = 0, misses = 0,
        zombieStrikes = 0, zombieStruck = 0, actorHits = 0, playerHits = 0, playerHitFailures = 0,
        retaliationHandOffs = 0, bitersKept = 0, sortieTicks = 0,
        leashReturns = 0, leashRefused = 0,
        offersLeashed = 0, climbsCut = 0, watchesLifted = 0,
        stepOffs = 0, pathGiveUps = 0, leashGiveUps = 0, leashHoldsExtended = 0 }
    Combat.footBlockedBy = {}
    Combat.pendingWatch = nil
    Combat.settings = {}
    for name, value in pairs(defaults) do
        if type(value) == "boolean" then
            local supplied = Combat.adapters[name]
            Combat.settings[name] = supplied == nil and value
                or supplied == true or tostring(supplied) == "true"
        elseif type(value) == "string" then
            local supplied = Combat.adapters[name]
            Combat.settings[name] = supplied == nil and value or tostring(supplied)
        else
            Combat.settings[name] = tonumber(Combat.adapters[name]) or value
        end
    end
    Weapons.configure(Combat.adapters.weapons)
    TargetPolicy.configure(Combat.adapters.targetPolicy)
end

function Combat.forgetActor(uid)
    if type(uid) ~= "string" then return false end
    Combat.suppressions[uid] = nil
    Combat.leashRefusals[uid] = nil
    return true
end

Combat.aimStateFor = aimStateFor
Combat.attackIncapacitated = attackIncapacitated
Combat.attackPosition = attackPosition
Combat.clearAttackLine = clearAttackLine
Combat.closingRunAllowed = closingRunAllowed
Combat.consumeRound = consumeRound
Combat.currentAmmo = currentAmmo
Combat.desiredRange = desiredRange
Combat.distanceSquared = distanceSquared
Combat.faceTarget = faceTarget
Combat.isRanged = isRanged
Combat.isUnarmed = isUnarmed
Combat.maximumRange = maximumRange
Combat.meleeReach = meleeReach
Combat.meleeReachFor = meleeReachFor
Combat.nowMs = nowMs
Combat.position = position
Combat.refreshReadyWindow = refreshReadyWindow
Combat.setAimWalk = setAimWalk
Combat.setPhase = setPhase
Combat.shoveReady = shoveReady
Combat.suppress = suppress
Combat.targetAlive = targetAlive
Combat.targetIsDown = targetIsDown
Combat.targetIsHuman = targetIsHuman
Combat.traverseFraction = traverseFraction
Combat.variable = variable
Combat.weaponFor = weaponFor

return Combat
