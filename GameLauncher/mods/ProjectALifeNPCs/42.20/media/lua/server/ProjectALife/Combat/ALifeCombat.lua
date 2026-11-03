require "ProjectALife/Behaviours/ALifeFireManeuver"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Shells/ALifeNPCHitRelay"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Combat/ALifeLineOfFire"
require "ProjectALife/Combat/ALifeFireControl"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Movement/ALifeMovement"
require "ProjectALife/Movement/ALifeUpperPosts"
require "ProjectALife/Movement/ALifeObstacleTraversal"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Shells/ALifeGait"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Audio/ALifeVoice"
require "ProjectALife/Audio/ALifeHumanReactions"
require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Combat/ALifeCombatApproach"
require "ProjectALife/Combat/ALifeCombatFire"
require "ProjectALife/Combat/ALifeCombatStrike"

ProjectALife = ProjectALife or {}

local Ledger = ProjectALife.ActionLedger
local Weapons = ProjectALife.Weapons
local Magazines = ProjectALife.MagazineState
local Jamming = ProjectALife.WeaponJamming
local Animations = ProjectALife.Animations
local TargetPolicy = ProjectALife.TargetPolicy
local Movement = ProjectALife.Movement
local Traversal = ProjectALife.ObstacleTraversal
local Endurance = ProjectALife.Endurance
local Tactics = ProjectALife.SquadTactics
local Voice = ProjectALife.Voice
local Combat = ProjectALife.Combat

function Combat.startDraw(shell, weapon, aim, now)
    local reachPreset, reachMs, takePreset, takeMs = Animations.drawSequenceFor(shell, weapon)

    Combat.cancelPath(shell)
    Combat.pathRequests[shell] = nil
    if shell.setMoving ~= nil then shell:setMoving(false) end
    pcall(Animations.setCombatHold, shell, true, true)
    if reachPreset ~= nil and Animations.apply(shell, reachPreset) == true then
        aim.drawPlayedAtMs = now
        return "draw_reach", now + reachMs, takePreset, takeMs
    elseif takePreset ~= nil and Animations.apply(shell, takePreset) == true then
        aim.drawPlayedAtMs = now
        return "draw", now + takeMs, takePreset, takeMs
    end
    pcall(Animations.setCombatHold, shell, true)
    return "approach", now, takePreset, takeMs
end

function Combat.currentEngagementFacts(actor, shell, target, now)
    local facts = type(actor.memory) == "table" and actor.memory.engagementFacts or nil
    if type(facts) ~= "table" then return nil end
    local kind = Combat.kindOf(target)
    facts.targetKind = kind == "actor" and "npc" or kind
    local perception = ProjectALife.Perception
    local held = perception ~= nil and type(perception.attackers) == "table"
        and perception.attackers[actor.uid] or nil
    facts.targetAttacking = type(held) == "table" and held.attacker == target
        and now < (tonumber(held.untilMs) or -1e12)
    local withdraw = ProjectALife.ModuleWithdraw
    local plan = withdraw ~= nil and type(withdraw.plans) == "table"
        and withdraw.plans[actor.uid] or nil
    facts.outnumbered = type(plan) == "table" and plan.reason == "withdraw_outnumbered"
        and now >= (tonumber(plan.startedAtMs) or now)
        and now < (tonumber(plan.untilMs) or -1e12)
    if kind == "zombie" then
        facts.immediateDanger = Combat.selfDefence(shell, target)
    else
        facts.immediateDanger = facts.targetAttacking
    end
    return facts
end

function Combat.begin(actor, shell, target, options)
    options = options or {}
    if type(actor) ~= "table" or type(actor.uid) ~= "string"
            or type(actor.generation) ~= "number" or shell == nil or target == nil then
        return nil, "combat_specification_invalid"
    end
    local startable, refusal = Combat.canBegin(actor, target, nil, shell)
    if not startable then return nil, refusal end

    if ProjectALife.ObstacleTraversal and not Combat.inClip(shell) then
        ProjectALife.ObstacleTraversal.cancel(shell, "combat_begin")
    end
    local interruptedWork = Animations.cancelForCombat(shell)

    pcall(function()
        local audioGuard = ProjectALife.AIFence
        if audioGuard ~= nil and type(audioGuard.silenceNativeVoice) == "function" then
            audioGuard.silenceNativeVoice(shell, true)
        end
    end)

    pcall(function()
        shell:getModData().ProjectALifeGuardUntilMs = Combat.nowMs() + 4000
    end)
    Combat.sequence = Combat.sequence + 1
    local startedAt = Combat.nowMs()
    local phase = "approach"
    local phaseDeadlineAtMs = startedAt
    local tactic = "direct"

    local nextRepositionAtMs = startedAt + 1000
    local blockedSinceAtMs
    local lastBreachTryAtMs = 0
    local failedAttacks = 0
    local action

    local aim = Combat.aimStateFor(shell)
    aim.targetIdentity = TargetPolicy.identity(target)
    aim.readyAtMs = nil

    aim.grudgeAtBegin = Combat.currentGrudge(actor)
    aim.edgeHoldSinceMs, aim.fenceEdge = nil, nil
    aim.leashHoldSinceMs = nil
    aim.edgeHoldSamples, aim.climbHoldSamples, aim.leashHoldSamples = 0, 0, 0
    aim.pathGiveUpAtMs = nil
    aim.leashAnchor, aim.leashRange = nil, nil
    Combat.clearUnstarted(aim)

    aim.noClimb = Movement.noClimb(actor)
    Combat.cutClimb(shell)
    if interruptedWork then aim.warmUntilMs = 0 end
    pcall(function()
        local gunner = ProjectALife.ModuleGunner
        if gunner ~= nil then gunner.stop(shell:getModData()) end
    end)
    if ProjectALife.GunDiscipline ~= nil then ProjectALife.GunDiscipline.beginCombat(actor, shell, target) end
    local initialWeapon = Combat.weaponFor(shell)
    local drawTakePreset, drawTakeMs

    local coldDraw = initialWeapon ~= nil
        and not Animations.weaponIsHeld(shell)
    aim.cancelAfterClip = nil
    if coldDraw and Combat.inClip(shell) then

        phase = "land"
    elseif coldDraw then
        phase, phaseDeadlineAtMs, drawTakePreset, drawTakeMs =
            Combat.startDraw(shell, initialWeapon, aim, startedAt)
    else
        pcall(Animations.setCombatHold, shell, true)
    end
    Combat.setPhase(shell, phase, tactic, nil)

    local downedStandoff

    local function beginApproach(now, force, breach)
        local weapon = Combat.weaponFor(shell)
        if weapon == nil then return false end

        downedStandoff = Combat.targetIsDown(target) and 0.7 or nil

        if math.sqrt(Combat.distanceSquared(shell, target)) > Combat.desiredRange(weapon, shell) + 3 then
            aim.readyAtMs = nil
        end
        local closingDistance = math.sqrt(Combat.distanceSquared(shell, target))
        local closingThreshold = math.max(
            tonumber(Combat.settings.closingRunMinimumDistance) or 7.5,
            (downedStandoff or Combat.desiredRange(weapon, shell)) + 3.5)

        if not Combat.isRanged(weapon) and Combat.targetIsHuman(target) then
            Combat.meleePressing(aim, shell, target, now)
        end

        if weapon ~= nil and not Combat.isRanged(weapon) and target ~= nil
                and closingDistance <= Combat.meleeReachFor(weapon, target)
                and not Combat.pressClosing(aim, weapon, target, closingDistance) then
            if aim.inReachSinceMs == nil then aim.inReachSinceMs = now end
            if now - aim.inReachSinceMs <= (tonumber(Combat.settings.holdInReachMs) or 2000) then
                Combat.cancelPath(shell)
                Combat.pathRequests[shell] = nil
                pcall(function() shell:faceThisObject(target) end)
                return true
            end
        else
            aim.inReachSinceMs = nil
        end

        ProjectALife.Gait.grantBurst(actor, shell, target, now, closingDistance,
            Combat.burstFloor(weapon, target, math.max(1.6, Combat.desiredRange(weapon, shell) + 0.5)))
        local sprinting = false
        pcall(function()
            sprinting = now < (tonumber(shell:getModData().ProjectALifeSprintUntilMs) or 0)
        end)

        local canRun = sprinting or (closingDistance > closingThreshold
            and ProjectALife.Gait.worthBurst(target)
            and Endurance.canSprint(actor, shell, now)

            and (Weapons.firesPellets(weapon) or Combat.closingRunAllowed(actor, shell, now)))
        local melee = weapon ~= nil and not Combat.isRanged(weapon)
        local guardRange = melee and Combat.guardBand(weapon, target)
            or (Combat.settings.readyGuardRange or 4)
        if melee then
            if aim.guardTarget ~= target then
                aim.guardTarget, aim.inGuardBand = target, false
            end
        else
            aim.guardTarget, aim.inGuardBand = nil, nil
        end
        local wasInBand = melee and aim.inGuardBand == true
        local inBand = melee and closingDistance <= guardRange + (wasInBand and 0.65 or 0)
        if melee then aim.inGuardBand = inBand end
        local pressing = inBand and Combat.targetIsHuman(target)
            and Combat.meleePressing(aim, shell, target, now)
        local destination, pace, nextTactic

        local stack = ProjectALife.ModuleBreach and ProjectALife.ModuleBreach.approachOverride(actor, shell, now) or nil
        if stack ~= nil then
            destination, pace, nextTactic = stack.destination, stack.pace, stack.tactic
        elseif breach then
            pcall(function() ProjectALife.ModuleBreach.propose(actor, shell, target, now) end)
            destination = Combat.breachDestination(actor, shell, target)
            pace, nextTactic = canRun and "run" or "walk", "breach"
        else
            destination, pace, nextTactic = Tactics.combatDestination(
                actor, shell, target, downedStandoff or Combat.desiredRange(weapon, shell),
                canRun, now, Combat.isRanged(weapon), Combat.holdReach(weapon, shell, target))
            if pressing and downedStandoff == nil and Combat.pressWalker(aim, target) then
                destination, nextTactic = Combat.pressLeadPoint(aim, target,
                    closingDistance <= Combat.meleeReachFor(weapon, target)) or destination, "press"
                Combat.metrics.pressLegs = (Combat.metrics.pressLegs or 0) + 1
            end
        end

        if aim.vehicleSinceMs ~= nil and ProjectALife.FireControl ~= nil and stack == nil and not breach
                and Combat.isRanged(weapon) then
            local lane = ProjectALife.FireControl.lane(shell, target, now)
            if lane ~= nil then destination, pace, nextTactic = lane, canRun and "run" or "walk", "arc" end
        end

        local heldSince = aim.leashHoldSinceMs
        aim.leashHoldSinceMs = nil
        local unleashed = destination
        local leashAnchor, leashRange = Combat.combatLeash(actor, shell, target)
        if leashAnchor ~= nil then
            destination = Combat.leashedPoint(leashAnchor, destination, leashRange)
            if destination ~= unleashed
                    and Combat.leashEdgeHold(shell, leashAnchor, destination, leashRange, target) then
                destination = nil
                Combat.holdStill(shell)
                Combat.metrics.leashHolds = (Combat.metrics.leashHolds or 0) + 1
                aim.leashHoldSinceMs = heldSince or now
                aim.leashHoldSamples = (aim.leashHoldSamples or 0) + 1
            end

            destination = destination or Combat.leashReturnPoint(shell, leashAnchor, leashRange)

            if aim.noClimb == true and destination ~= nil
                    and Combat.homeNeedsClimb(shell, leashAnchor, leashRange, destination, now) then
                destination = Combat.holdOnLeash(shell, aim, heldSince, now)
            end
        end

        aim.leashAnchor, aim.leashRange = leashAnchor, leashRange

        if melee and Combat.targetIsHuman(target) and nextTactic ~= "intimidate" and (pressing or (not inBand
                and closingDistance > math.max(1.6, Combat.meleeReach(weapon) + 0.8))) then
            local lungs = Endurance.value(actor, shell, now)
            local floor = tonumber((ProjectALife.BehaviorSettings.endurance or {}).jogMinimum) or 15
            if lungs == nil or lungs > floor then pace = "run" end
        end
        if inBand then
            if not pressing or pace ~= "run" then pace = "guard" end
            Combat.endBurst(shell)
            pcall(function()
                shell:getModData().ProjectALifeGuardUntilMs = Combat.nowMs() + 4000
            end)
        end

        tactic = nextTactic or "direct"

        phase = "approach"
        phaseDeadlineAtMs = now
        local distance = math.sqrt(Combat.distanceSquared(shell, target))

        local highDanger = Combat.approachAimWalk(weapon, distance,
            math.min(guardRange, math.max(1.6, Combat.desiredRange(weapon, shell) + 0.5)), aim, target)
        Combat.setAimWalk(shell, highDanger,
            Combat.isRanged(weapon) and "ranged_contact"
                or (highDanger and "melee_guard" or "melee_closing"))
        Combat.setPhase(shell, phase, tactic, distance)
        if action ~= nil then
            action.phase, action.tactic, action.pace = phase, tactic, pace
        end
        if destination == nil and not Combat.isRanged(weapon) and not breach
                and distance <= Combat.meleeReach(weapon) + 1.5 then

            destination = Combat.breachDestination(actor, shell, target)
            tactic = "close"
            if leashAnchor ~= nil and destination ~= nil then
                local step = Combat.leashedPoint(leashAnchor, destination, leashRange)
                if step ~= destination
                        and Combat.leashEdgeHold(shell, leashAnchor, step, leashRange, target) then
                    step = nil
                    Combat.holdStill(shell)
                    Combat.metrics.leashHolds = (Combat.metrics.leashHolds or 0) + 1
                    aim.leashHoldSinceMs = aim.leashHoldSinceMs or heldSince or now
                    aim.leashHoldSamples = (aim.leashHoldSamples or 0) + 1
                end
                destination = step
            end
        end

        if destination ~= nil and stack == nil and leashAnchor == nil then
            local routed = Combat.entranceLeg(actor, shell, target, destination, now, distance)
            if routed == destination and tactic ~= "breach" and tactic ~= "cross_floor"
                    and tactic ~= "arc" and tactic ~= "fall_back" and tactic ~= "press" then
                routed = Combat.approachWaypoint(actor, shell, target, destination, now)
            end
            destination = routed
        end
        if destination == nil then

            if Combat.pathRequests[shell] ~= nil or Combat.pathLive(shell) then
                Combat.cancelPath(shell)
            end
            Combat.pathRequests[shell] = nil
            return true
        end
        return Combat.pathToward(shell, destination, pace, force)
    end

    local beginWindupInner

    local function beginWindup(now, weapon, distance)

        if Combat.pathRequests[shell] ~= nil then
            Combat.cancelPath(shell)
            Combat.pathRequests[shell] = nil
        end
        Combat.setAimWalk(shell, true, "weapon_ready")

        local warm = now < (aim.warmUntilMs or 0)
        local aimMs = Combat.aimSettleMs(shell, target, weapon, distance, warm, actor)

        if not Combat.isRanged(weapon) then
            if aim.readyAtMs == nil then

                aim.readyAtMs = now + ((warm or Combat.pressWalker(aim, target)) and 0
                    or (Combat.settings.meleeReadyMs or 220))
                    + math.floor(Combat.traverseFraction(shell, target)
                        * (Combat.settings.aimTraverseMs or 420) * 0.5)
                if Animations.current[shell] ~= "hit_react" then
                    pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
                end
            end
            Combat.refreshReadyWindow(aim, now)
            if now < aim.readyAtMs then
                pcall(function() shell:faceThisObject(target) end)
                return false
            end
        elseif aimMs > 0 then
            if aim.readyAtMs == nil then

                pcall(function()
                    local bring = weapon:getBringToBearSound()
                    if bring ~= nil then ProjectALife.AudioPolicy.playFrom(shell, bring) end
                end)
                aim.readyAtMs = now + aimMs
                if Animations.current[shell] ~= "hit_react" then
                    pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
                end
            end
            Combat.refreshReadyWindow(aim, now)
            if now < aim.readyAtMs then
                pcall(function() shell:faceThisObject(target) end)
                return false
            end
        end
        if Combat.strikeHeld(actor, shell, target, now) then
            Combat.faceTarget(shell, target)
            return false
        end
        return beginWindupInner(now, weapon, distance)
    end

    beginWindupInner = function(now, weapon, distance)

        if Combat.attackIncapacitated(shell) then return false end

        if not Combat.clearAttackLine(shell, target, weapon) then return false end
        if not Combat.isRanged(weapon) and not Combat.meleeReady(shell, now) then
            Combat.metrics.meleeHeld = (Combat.metrics.meleeHeld or 0) + 1
            Combat.faceTarget(shell, target)
            return false
        end
        Combat.cancelPath(shell)
        Combat.pathRequests[shell] = nil
        Combat.faceTarget(shell, target)
        local ranged = Combat.isRanged(weapon)
        local animated
        local shoveRange = Combat.settings.shoveDistance or 1.15
        if ranged and distance ~= nil and distance < shoveRange
                and not Combat.targetIsDown(target) then

            animated = Animations.apply(shell, Combat.readyPresetFor(shell, weapon, target))
        elseif ranged then

            animated = Animations.apply(shell, Combat.readyPresetFor(shell, weapon, target))
        elseif distance ~= nil and distance < 0.55 and not Combat.targetIsDown(target)
                and Combat.canShove(target) and Combat.shoveReady(shell, now) then

            action.shove = true
            animated = Animations.apply(shell, Combat.shovePreset(shell, weapon))
        elseif Combat.targetIsDown(target) then

            local class = Combat.meleeClass(weapon)
            local floorPreset = "combat_floor"
            if class == "knife" then
                floorPreset = "combat_floor_knife"
            elseif class == "twoHanded" then
                floorPreset = Combat.isHeavyMelee(weapon) and "combat_stomp" or "combat_floor_2h"
            elseif class == "spear" then

                floorPreset = "combat_floor_spear"
            end
            if action ~= nil then action.floorAttack = true end
            animated = Animations.apply(shell, floorPreset)
            if action ~= nil then
                action.reaction = "Floor"
                action.swingClass = Combat.FLOOR_SWING_CLASS[floorPreset]
            end
        elseif type(ZombRand) == "function" and ZombRand(5) == 0
                and Combat.canShove(target) and Combat.shoveReady(shell, now) then

            action.shove = true
            action.shoveFloor = true
            animated = Animations.apply(shell, Combat.shovePreset(shell, weapon))
        else
            local preset, reaction, swingClass = Combat.meleeSwing(weapon)
            animated = Animations.apply(shell, preset)
            if action ~= nil then
                action.reaction = reaction
                action.swingClass = swingClass
            end
        end

        if animated and not ranged then
            Combat.meleeAudio("swing", shell, nil, weapon,
                action ~= nil and action.swingClass or nil)
        end
        if animated ~= true then
            Animations.clear(shell)
            phase = "approach"
            phaseDeadlineAtMs = now
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        end
        if not ranged then
            local kind = "swing"
            if action ~= nil and action.shove == true then
                kind = "shove"
            elseif action ~= nil and action.floorAttack == true then
                kind = "floor"
            end
            Combat.noteMeleeStart(shell, weapon, now, kind)
        end
        phase = ranged and "aim" or "windup"

        if action ~= nil and action.floorAttack == true then
            phaseDeadlineAtMs = now + 700
        else
            phaseDeadlineAtMs = now + (ranged and Combat.reactionDelayMs(Combat.settings.rangedWindupMs)
                or math.floor(Combat.settings.meleeWindupMs * Combat.meleeTempo(shell, weapon)))
        end
        if ranged then

            aim.readyAtMs = phaseDeadlineAtMs
        end
        Combat.setPhase(shell, phase, tactic, distance)
        if action ~= nil then action.phase, action.pace = phase, "walk" end
        return true
    end

    local function abortUnreachable(now, reason, distance)
        reason = reason or "combat_target_unreachable"

        if reason == "combat_line_blocked" then
            pcall(function()
                local gunner = ProjectALife.ModuleGunner
                if gunner ~= nil then gunner.order(actor, shell, target, now) end
            end)
        end
        Combat.suppress(actor, target, reason, now)

        if (reason == "combat_line_blocked"
                or reason == "combat_target_other_floor")
                and not Combat.retaliating(actor, target, now) then
            pcall(function()
                local perception = ProjectALife.Perception
                if perception ~= nil and type(perception.ignore) == "function" then
                    perception.ignore(actor.uid, target, 10000)
                end
            end)
        end

        if reason == "combat_line_blocked" then
            local warmState = Combat.aimState[shell]
            if warmState ~= nil then
                warmState.warmUntilMs = math.max(
                    tonumber(warmState.warmUntilMs) or 0,
                    Combat.nowMs() + Combat.settings.combatReadyMinimumMs)
            end
        end
        Combat.disengage(shell)
        pcall(function()
            local data = shell:getModData()
            data.ProjectALifeCombatAbortReason = reason
            data.ProjectALifeCombatAbortUntilMs = now + Combat.settings.unreachableCooldownMs
        end)
        if action ~= nil then
            action.phase = "aborted"
            action.abortReason = reason
            action.targetDistance = distance
        end
        return true
    end

    local function inspect()
        if (not Combat.targetAlive(target) or not TargetPolicy.canAttack(target, aim.targetIdentity, actor)
                or Combat.comradeTarget(actor, target, shell))
                and phase ~= "reload" and phase ~= "reload_rack" then

            local state = Combat.aimState[shell]
            if state ~= nil then
                state.warmUntilMs = math.max(tonumber(state.warmUntilMs) or 0,
                    Combat.nowMs() + Combat.settings.combatReadyMinimumMs)
            end
            Combat.disengage(shell)
            return true
        end
        if Combat.offLimits(actor, target) then
            Combat.disengage(shell)
            return true
        end
        Combat.stampAim(shell, target)
        Combat.noteSighting(actor, shell, target)

        if aim.noClimb == true and Combat.cutClimb(shell) then return false end
        local pulse = Combat.dataOf(shell)
        if pulse ~= nil and shell.getX ~= nil and shell.getY ~= nil then
            local data = pulse
            data.ProjectALifeCombatPulseMs = Combat.nowMs()

            local sampleAt = tonumber(data.ProjectALifeStuckSampleAtMs) or 0

            local walking = phase == "approach" or phase == "reposition"
            if not walking then
                data.ProjectALifeStuckSinceMs = nil
                data.ProjectALifeStuckSampleAtMs = Combat.nowMs() + 1000
                data.ProjectALifeStuckX, data.ProjectALifeStuckY = shell:getX(), shell:getY()
            elseif Combat.nowMs() >= sampleAt then
                local x, y = shell:getX(), shell:getY()
                local lastX = tonumber(data.ProjectALifeStuckX)
                local lastY = tonumber(data.ProjectALifeStuckY)
                local moved = lastX == nil
                    or (x - lastX) ^ 2 + (y - lastY) ^ 2 > 0.09
                data.ProjectALifeStuckSampleAtMs = Combat.nowMs() + 1000
                data.ProjectALifeStuckX, data.ProjectALifeStuckY = x, y
                if moved then
                    data.ProjectALifeStuckSinceMs = nil
                else
                    data.ProjectALifeStuckSinceMs =
                        tonumber(data.ProjectALifeStuckSinceMs) or Combat.nowMs()
                end
            end
        end

        local weaponNow = Combat.weaponFor(shell)
        if pulse ~= nil and weaponNow ~= nil and Combat.isRanged(weaponNow) then
            local reach = Combat.maximumRange(weaponNow, shell)
            if Combat.distanceSquared(shell, target) <= reach * reach then
                pulse.ProjectALifeInRangeAtMs = Combat.nowMs()
            end
        end

        Movement.refreshPace(shell)

        local retaliation, retaliationKind
        local perception = ProjectALife.Perception
        if perception ~= nil and type(perception.retaliationTarget) == "function" then
            retaliation, retaliationKind = perception.retaliationTarget(actor.uid)
        end
        if retaliation ~= nil and retaliation ~= target and Combat.targetAlive(retaliation)

                and retaliation ~= aim.grudgeAtBegin

                and not Combat.inClip(shell)
                and phase ~= "reload" and phase ~= "reload_rack"

                and not Combat.keepsTarget(aim, phase, shell, target, weaponNow, retaliation, retaliationKind)
                and not Combat.breakingOut(aim, phase, Combat.nowMs())

                and Combat.retaliationSeen(shell, retaliation) then
            Combat.metrics.retaliationHandOffs = (Combat.metrics.retaliationHandOffs or 0) + 1
            if Traversal.isBusy(shell) then pcall(Traversal.cancel, shell, "combat_retaliation") end

            local state = Combat.aimState[shell]
            if state ~= nil then
                state.warmUntilMs = math.max(tonumber(state.warmUntilMs) or 0,
                    Combat.nowMs() + Combat.settings.combatReadyMinimumMs)
            end
            Combat.disengage(shell)
            return true
        end

        if Combat.nowMs() >= (aim.nextRetargetAtMs or 0)
                and not Combat.breakingOut(aim, phase, Combat.nowMs()) then
            aim.nextRetargetAtMs = Combat.nowMs() + (Combat.isRanged(weaponNow)
                and Combat.reactionDelayMs(400) or 400)
            local challenger, challengerKind, answered

            local finder = ProjectALife.Perception
            if finder ~= nil and type(finder.findThreat) == "function" then
                local found, picked, _, pickedKind = pcall(finder.findThreat,
                    actor, shell, options.mode or "assault")
                if found then challenger, challengerKind, answered = picked, pickedKind, true end
            end

            if answered and challenger == nil and phase ~= "reload" and phase ~= "reload_rack"
                    and not Combat.inClip(shell) then
                local release = Combat.zombieRelease(actor, shell, target,
                    options.targetKind, Combat.nowMs())
                if release ~= nil then return Combat.letZombieGo(actor, shell, target, release) end
            end
            if challenger ~= nil and challenger ~= target
                    and not Combat.meleeFocus(shell, target, weaponNow, challenger)
                    and Combat.targetAlive(challenger)
                    and Combat.canEngage(actor, challenger, Combat.nowMs(), shell) then

                if not Combat.inClip(shell) then
                    if Traversal.isBusy(shell) then pcall(Traversal.cancel, shell, "combat_retarget") end
                    Combat.cancelPath(shell)
                end
                Combat.pathRequests[shell] = nil
                target = challenger
                aim.targetIdentity = TargetPolicy.identity(target)
                options.targetKind = challengerKind or Combat.kindOf(challenger)
                failedAttacks = 0
                blockedSinceAtMs = nil
                if phase == "approach" or phase == "reposition"
                        or phase == "kite" or phase == "cover" or phase == "aim" then
                    phase = "aim"
                    phaseDeadlineAtMs = Combat.nowMs() + 100
                    Combat.setPhase(shell, phase, tactic,
                        math.sqrt(Combat.distanceSquared(shell, target)))
                end
                if action ~= nil then
                    action.target = target
                    action.targetKind = options.targetKind
                    action.phase = phase
                    action.retargetedAtMs = Combat.nowMs()
                end
                Combat.stampAim(shell, target)
                Combat.faceTarget(shell, target)
            end
        end

        if Traversal.isBusy(shell) then
            local contact
            local watcher = ProjectALife.Perception
            if watcher ~= nil and type(watcher.contactThreat) == "function" then
                contact = watcher.contactThreat(shell)
            end
            if contact ~= nil and contact ~= target
                    and not Combat.breakingOut(aim, phase, Combat.nowMs())
                    and not Combat.inClip(shell) then
                pcall(Traversal.cancel, shell, "combat_contact")
                Combat.disengage(shell)
                return true
            end
            return false
        end
        if shell.getActionStateName ~= nil then
            local state = tostring(shell:getActionStateName() or "")
            if state == "climbfence" or state == "climbwindow" then return false end
        end
        local now = Combat.nowMs()
        if Combat.attackIncapacitated(shell) then
            Combat.cancelPath(shell)
            Combat.pathRequests[shell] = nil
            if shell.setMoving ~= nil then shell:setMoving(false) end
            return false
        end

        local weapon = weaponNow
        if weapon == nil then
            Combat.disengage(shell)
            return true
        end
        aim.maneuverPin = Tactics.maneuvers[shell:getModData().ProjectALifeManeuverPin]
        if aim.maneuverPin ~= nil and aim.maneuverPin.pin~=shell then aim.maneuverPin=nil end
        if aim.maneuverPin ~= nil then
            if target ~= aim.maneuverPin.target or not Tactics.maneuverValid(aim.maneuverPin,now) then
                Tactics.clearManeuver(shell,"combat_changed")
            else
                Combat.cancelPath(shell)
                Combat.faceTarget(shell,target)
                return false
            end
        end
        aim.maneuverResult = ProjectALife.FireManeuver.step(actor,shell,target,weapon,now,aim,phase)
        if aim.maneuverResult == "hold" then
            Combat.setPhase(shell,"cover",tactic,nil)
            if action then action.phase,action.pace="cover","walk" end
            return false
        elseif aim.maneuverResult ~= nil then
            phase = aim.maneuverResult == "aim" and "aim" or "approach"
            phaseDeadlineAtMs = now
            if action then action.phase=phase end
        end
        if phase == "land" then

            if Combat.inClip(shell) then return false end
            if Animations.weaponIsHeld(shell) then
                pcall(Animations.setCombatHold, shell, true)
                phase = "approach"
            else
                phase, phaseDeadlineAtMs, drawTakePreset, drawTakeMs =
                    Combat.startDraw(shell, weapon, aim, now)
            end
            Combat.setPhase(shell, phase, tactic, nil)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            if phase == "approach" then beginApproach(now, true) end
            return false
        end
        if phase == "draw_reach" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            pcall(function()
                local sound = weapon:getEquipSound()
                if sound ~= nil and sound ~= "" then ProjectALife.AudioPolicy.playFrom(shell, sound) end
            end)
            if drawTakePreset ~= nil
                    and Animations.apply(shell, drawTakePreset) == true then
                phase = "draw"
                phaseDeadlineAtMs = now + (drawTakeMs or 750)
                Combat.setPhase(shell, phase, tactic, nil)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            pcall(Animations.setCombatHold, shell, true)
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, nil)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            beginApproach(now, true)
            return false
        elseif phase == "draw" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            aim.racked = true
            pcall(Animations.setCombatHold, shell, true)
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, nil)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            beginApproach(now, true)
            return false
        end
        local inPosition, distance, positionReason = Combat.attackPosition(shell, target, weapon)

        if inPosition or phase ~= "approach" then aim.edgeHoldSinceMs = nil end
        if inPosition or phase ~= "approach" then aim.leashHoldSinceMs = nil end

        if positionReason == "ready" or positionReason == "out_of_range" then
            Tactics.reportThreat(actor, target, options.targetKind, now)
        end

        if phase ~= "cover" and phase ~= "kite"
                and ((phase ~= "approach" and phase ~= "reposition")
                or distance <= (Combat.targetIsGunman(target)
                    and (Combat.settings.readyGuardRangeVersusGun or 1.6)
                    or (Combat.settings.readyGuardRange or 4))) then
            Combat.faceTarget(shell, target)
        end

        if distance < 0.85 and phase ~= "cover" and not (phase == "kite" and aim.footworkKind ~= nil) then
            Combat.cancelPath(shell)
            Combat.pathRequests[shell] = nil
        end

        local committed = phase == "aim" or phase == "windup" or phase == "recovery"
        if committed and not inPosition then
            if positionReason == "out_of_range" then
                local hold = Combat.isRanged(weapon) and Combat.engagementReach(weapon, shell, target)
                    or Combat.meleeReachFor(weapon, target)
                if distance <= hold then inPosition, positionReason = true, "ready" end
            end
        end
        local blockedRange = Combat.isRanged(weapon) and Combat.maximumRange(weapon, shell) or 3
        local blocked = (positionReason == "blocked"
                or positionReason == "boundary"
                or positionReason == "not_visible")
            and distance <= blockedRange

        if positionReason == "vehicle" and ProjectALife.FireControl ~= nil then
            aim.vehicleSinceMs = aim.vehicleSinceMs or now
            if now - aim.vehicleSinceMs >= ProjectALife.FireControl.settings.giveUpMs then
                aim.vehicleSinceMs = nil
                ProjectALife.FireControl.noteGiveUp()
                return abortUnreachable(now, "combat_line_blocked", distance)
            end
        else
            aim.vehicleSinceMs = nil
        end

        local differentLevel = positionReason == "different_level"
        local _, _, hereZ = Combat.xyzOf(shell)
        local _, _, thereZ = Combat.xyzOf(target)
        if hereZ ~= nil and thereZ ~= nil and math.abs(hereZ - thereZ) >= 0.4 then
            blocked = false
            differentLevel = true
        end

        if differentLevel then

            local answerable = Combat.isRanged(weapon)
                and (Combat.clearAttackLine(shell, target, weapon)
                    or (distance ~= nil
                        and distance <= (Combat.settings.stairShotDistance or 3.5)))
            if answerable then
                aim.crossFloorSinceMs = nil
            else

                aim.crossFloorSinceMs = aim.crossFloorSinceMs or now
                if now - aim.crossFloorSinceMs >= Combat.settings.crossFloorTimeoutMs then
                    if Combat.recoverUpper(actor, shell, target, aim, now) then return false end
                    return abortUnreachable(now, "combat_target_other_floor", distance)
                end
            end
        else
            aim.crossFloorSinceMs = nil
            aim.upperRecoveryAttempted, aim.upperRecoveryUntilMs, aim.upperPoint, aim.upperNextScanMs = nil, nil, nil, nil
        end

        if blocked and not Combat.isRanged(weapon)
                and positionReason ~= "boundary"
                and distance <= Combat.meleeReach(weapon) + 0.5 then
            blocked = false
        end
        if blocked then

            if blockedSinceAtMs == nil then
                aim.fenceEdge = nil
                aim.fenceDetourAsked, aim.fenceDetour = nil, nil

                if positionReason == "boundary" and not Combat.isRanged(weapon)
                        and distance ~= nil and distance * distance <= 4 then
                    aim.fenceEdge = Combat.lowFenceBetween(shell, target)
                end
            end
            if aim.fenceEdge ~= nil and blockedSinceAtMs ~= nil then
                if now - blockedSinceAtMs >= math.max(Combat.blockedLineTimeout(shell),
                        (tonumber(Combat.settings.breachGraceMs) or 4000) + 1500) then
                    return abortUnreachable(now, "combat_fence_standoff", distance)
                end
                if now - blockedSinceAtMs >= (tonumber(Combat.settings.fenceStandoffMs) or 1000) then
                    Combat.fenceStandoff(shell, target, aim)
                    return false
                end
            end

            local legGoal = Combat.legGoal(shell)
            local traversalResult = Traversal.consumeResult(shell)
            if traversalResult ~= nil and traversalResult.success then

                blockedSinceAtMs = now
            end
            blockedSinceAtMs = blockedSinceAtMs or now

            local sameFloor = hereZ == nil or thereZ == nil or math.abs(hereZ - thereZ) < 0.4
            if sameFloor and now - blockedSinceAtMs >= (tonumber(Combat.settings.breachGraceMs) or 4000)
                    and now - lastBreachTryAtMs >= 1500 and not Traversal.isBusy(shell)
                    and phase ~= "kite" and phase ~= "cover" then
                lastBreachTryAtMs = now
                local goal = legGoal or Combat.position(target)
                if goal ~= nil then
                    Traversal.consumeResult(shell)

                    local tried, crossed, refusal = pcall(Traversal.try, shell, goal, aim.noClimb == true)

                    if tried and crossed ~= true
                            and (refusal == "climb_landing_occupied" or refusal == "breach_claimed") then

                        Combat.faceTarget(shell, target)

                        blockedSinceAtMs = math.max(blockedSinceAtMs or now,
                            now - Combat.blockedLineTimeout(shell) + 1500)
                    end
                end
            end
            if Traversal.isBusy(shell) then return false end

            if now - blockedSinceAtMs >= math.max(Combat.blockedLineTimeout(shell),
                    (tonumber(Combat.settings.breachGraceMs) or 4000) + 1500) then
                return abortUnreachable(now, "combat_line_blocked", distance)
            end
        else
            blockedSinceAtMs = nil
            aim.fenceEdge = nil

            local swinging = Traversal.active[shell]
            if swinging ~= nil and swinging.mode == "breach" then Traversal.cancel(shell, "combat_line_clear") end
        end

        if phase == "aim" and Combat.isRanged(weapon)
                and not Magazines.isInfinite(shell)
                and Combat.currentAmmo(weapon) <= 0 then
            phase = "approach"
            phaseDeadlineAtMs = now
            if action ~= nil then
                action.phase = phase
                action.burstRemaining, action.rangedVolleyShot = nil, nil
            end
            Combat.setPhase(shell, phase, tactic, distance)
        end

        if phase == "aim" then
            if not Combat.isRanged(weapon) then
                phase = "approach"
                phaseDeadlineAtMs = now
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            if not inPosition then
                Animations.clear(shell)

                beginApproach(now, blocked == true, blocked and not Combat.isRanged(weapon))
                return false
            end
            if ProjectALife.GunDiscipline ~= nil and now >= (aim.weaponSwitchAtMs or 0)
                    and ProjectALife.GunDiscipline.disarm(actor, shell, target, aim, now) then
                phase = "switch"
                phaseDeadlineAtMs = now + (Combat.settings.weaponSwitchMs or 650)
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            if Combat.isRanged(weapon) and now >= (aim.nextLaneCheckMs or 0) then
                aim.nextLaneCheckMs = now + 250

            local ahead = Combat.nearestEnemyInLane(actor, shell, target)
                if ahead ~= nil and ahead ~= target

                        and (Combat.kindOf(target) ~= "player"
                            or Combat.distanceSquared(shell, ahead) <= 2.25)

                        and (Combat.kindOf(ahead) ~= "zombie"
                            or Combat.kindOf(target) == "zombie")
                        and Combat.canEngage(actor, ahead, now, shell) then
                    target = ahead
                    aim.targetIdentity = TargetPolicy.identity(target)
                    failedAttacks = 0
                    if action ~= nil then action.target, action.targetKind = ahead, Combat.kindOf(ahead) end
                    pcall(function()
                        local perception = ProjectALife.Perception
                        if perception ~= nil then
                            perception.engagements[actor.uid] = {
                                target = ahead, kind = Combat.kindOf(ahead),
                                x = ahead:getX(), y = ahead:getY(), z = ahead:getZ(), atMs = now }
                            if type(perception.logTarget) == "function" then
                                perception.logTarget(actor, ahead,
                                    perception.engagements[actor.uid].kind, "lane", now)
                            end
                        end
                    end)
                    Combat.faceTarget(shell, target)
                end
            end

            local kiteAt = Combat.settings.kiteTriggerDistance
            if Combat.isRanged(weapon) then
                local band = ProjectALife.SquadTactics
                    and ProjectALife.SquadTactics.bands or nil
                kiteAt = math.max(kiteAt,
                    Combat.desiredRange(weapon, shell) * ((band and band.holdFloor) or 0.85))
            end
            if Combat.isRanged(weapon) and distance ~= nil
                    and distance < kiteAt

                    and not Combat.closeQuarters(shell, target, distance)
                    and not Combat.targetIsDown(target)

                    and now >= phaseDeadlineAtMs

                    and (aim.hasFired == true or distance < kiteAt * 0.45
                        or Combat.limping(shell) == true)
                    and now >= (aim.nextKiteAtMs or 0)
                    and distance >= (Combat.settings.shoveDistance or 1.15) then

                local retreat = Combat.leashOffer(actor, Combat.kitePoint(shell, target,
                    Combat.limping(shell) and Combat.settings.kiteStepDistance * 0.45
                        or Combat.settings.kiteStepDistance))
                if retreat ~= nil then
                    aim.nextKiteAtMs = now + Combat.settings.kiteCooldownMs
                    aim.kiteSettleDistance = kiteAt + 1.5
                    aim.kitePoint = retreat
                    phase = "kite"
                    phaseDeadlineAtMs = now + Combat.settings.kiteLegMs
                    Combat.setPhase(shell, phase, tactic, distance)
                    Combat.setAimWalk(shell, false, "break_contact")
                    if action ~= nil then action.phase, action.pace = phase, "run" end
                    Combat.pathToward(shell, retreat, "run", true)
                    return false
                end
            end
            if now < phaseDeadlineAtMs then return false end
            if Combat.strikeHeld(actor, shell, target, now) then
                Combat.faceTarget(shell, target)
                phaseDeadlineAtMs = now + 150
                return false
            end

            if Animations.fallback[shell] == nil
                    and Animations.apply(shell,
                        Combat.readyPresetFor(shell, weapon, target)) == true
                    and Animations.fallback[shell] ~= nil then
                Combat.faceTarget(shell, target)
                aim.readyAtMs = now + Combat.reactionDelayMs(now < (aim.warmUntilMs or 0)
                    and (Combat.settings.aimWarmMs or 90)
                    or (Combat.settings.aimBaseMs or 350))
                phaseDeadlineAtMs = aim.readyAtMs
                Combat.setPhase(shell, phase, tactic, distance)
                return false
            end

            local shoveRange = Combat.settings.shoveDistance or 1.15
            if distance ~= nil and distance < shoveRange
                    and not Combat.targetIsDown(target)
                    and (ProjectALife.GunDiscipline == nil or ProjectALife.GunDiscipline.switchOn(actor))
                    and Combat.canShove(target)
                    and Combat.shoveReady(shell, now) then
                Combat.faceTarget(shell, target)
                Animations.apply(shell, Combat.shovePreset(shell, weapon))
                Combat.resolveAttack(actor, shell, target, true)
                if action ~= nil then action.rangedShove = true end
                phase = "recovery"
                phaseDeadlineAtMs = now + math.floor(800 * Combat.tiredTempo(shell))
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end

            local dumpData = Combat.dataOf(shell)
            local dumping = type(dumpData) == "table" and dumpData.ProjectALifeSuppressTracking == true
                and (tonumber(dumpData.ProjectALifeSuppressUntilMs) or 0) > now
            if dumping then
                Combat.faceTarget(shell, target)
                if action ~= nil then
                    action.burstRemaining = nil
                    action.rangedVolleyShot = nil
                end
                phaseDeadlineAtMs = now + 200
                return false
            end

            Combat.faceTarget(shell, target)

            if not Combat.muzzleOnTarget(shell, target) then
                aim.muzzleWaitAtMs = aim.muzzleWaitAtMs or now
                if now - aim.muzzleWaitAtMs < (Combat.settings.aimMaximumMs or 750) then
                    phaseDeadlineAtMs = now + 100
                    return false
                end
            end
            aim.muzzleWaitAtMs = nil

            if action ~= nil and action.burstRemaining == nil then
                local rounds = Combat.burstLength(shell, weapon, distance, target)
                if not Magazines.isInfinite(shell) then
                    rounds = math.min(rounds, Combat.currentAmmo(weapon))
                end
                action.burstRemaining = math.max(0, rounds - 1)
                action.rangedVolleyShot = 1
            elseif action ~= nil then
                action.rangedVolleyShot = (action.rangedVolleyShot or 1) + 1
            end
            local jammed = Jamming ~= nil and (Jamming.isJammed(weapon)
                or Jamming.try(shell, weapon, Combat.settings.jammingEnabled,
                    Combat.settings.jamChancePercent))
            if jammed then
                if action ~= nil then
                    action.burstRemaining = nil
                    action.rangedVolleyShot = nil
                    action.jammedWeapon = weapon
                end
                pcall(function()
                    local click = weapon:getClickSound()
                    if click ~= nil and click ~= "" then ProjectALife.AudioPolicy.playFrom(shell, click) end
                end)
                pcall(Animations.apply, shell, Combat.jamPresetFor(shell))
                Voice.play(shell, "WEAPON_JAM", { urgent = true })
                phase = "jammed"
                phaseDeadlineAtMs = now + (Combat.settings.jamReactionMs or 500)
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end

            pcall(function()
                shell:getModData().ProjectALifeBurstIndex = action ~= nil
                    and (action.rangedVolleyShot or 1) or 1
            end)
            local shotsBefore = Combat.metrics.shots or 0
            local hit = Combat.resolveAttack(actor, shell, target, false, "Shot")
            if hit and action ~= nil and action.killReported ~= true then
                local deadOk, dead = pcall(function() return target:isDead() end)
                if deadOk and dead == true then
                    action.killReported = true
                    Voice.play(shell, "KILL_CONFIRMED")
                end
            end
            local fired = (Combat.metrics.shots or 0) > shotsBefore
            if fired then
                if action == nil or (action.rangedVolleyShot or 1) == 1 then
                    pcall(Animations.apply, shell, Combat.shotPresetFor(shell))
                end
                aim.hasFired = true
                aim.maneuverShotTarget,aim.maneuverShotAt,aim.maneuverShotIdentity=target,now,TargetPolicy.identity(target)
            else
                if action ~= nil then
                    action.burstRemaining, action.rangedVolleyShot = 0, nil
                end
            end
            if hit then
                failedAttacks = 0
            elseif positionReason ~= "ready"
                    and not (not Combat.isRanged(weapon) and distance ~= nil
                        and distance <= Combat.meleeReachFor(weapon, target) + 0.6) then

                failedAttacks = failedAttacks + 1
            end
            if failedAttacks >= Combat.settings.maximumFailedAttacks then
                return abortUnreachable(now, "combat_attack_unresolved", distance)
            end
            if action ~= nil and action.burstRemaining > 0
                    and (Magazines.isInfinite(shell) or Combat.currentAmmo(weapon) > 0) then
                action.burstRemaining = action.burstRemaining - 1
                Combat.faceTarget(shell, target)
                phaseDeadlineAtMs = now + math.max(
                    Combat.settings.burstCadenceMs or 320,
                    Weapons.fireIntervalMs(weapon))
                Combat.refreshReadyWindow(aim, now)
                return false
            end
            if action ~= nil then
                action.burstRemaining = nil
                action.rangedVolleyShot = nil
            end
            pcall(function() shell:getModData().ProjectALifeBurstIndex = nil end)

            if fired and Weapons.racksAfterShot(weapon) then
                local rackPreset = Combat.rackPresetFor(shell, weapon, "cycle")
                if rackPreset ~= nil then
                    pcall(Animations.apply, shell, rackPreset)
                    pcall(function()
                        local rack = weapon:getRackSound()
                        if rack ~= nil and rack ~= "" then ProjectALife.AudioPolicy.playFrom(shell, rack) end
                    end)
                    if action ~= nil then action.cycleWeapon = weapon end
                    phase = "cycle_action"
                    phaseDeadlineAtMs = now + math.max(
                        Combat.settings.reloadRackMs or 900,
                        Weapons.fireIntervalMs(weapon))
                    Combat.setPhase(shell, phase, tactic, distance)
                    if action ~= nil then action.phase, action.pace = phase, "walk" end
                    return false
                end
            end
            phase = "recovery"
            local volleyJitterMs = 0
            pcall(function()
                local data = shell:getModData()

                if tostring(data.ProjectALifeConduct or "") ~= "gunner"
                        and data.ProjectALifeConductSecondaryGunner ~= true
                        and type(ZombRand) == "function" then
                    volleyJitterMs = ZombRand(0,
                        (Combat.settings.rangedRecoveryJitterMs or 400) + 1)
                end
            end)
            phaseDeadlineAtMs = now + volleyJitterMs + math.max(
                Combat.settings.rangedRecoveryMs,
                Combat.settings.rangedIntervalMs or Combat.settings.attackIntervalMs,
                Weapons.fireIntervalMs(weapon))

            Combat.setPhase(shell, phase, tactic, distance)
            Combat.refreshReadyWindow(aim, now)

            if action ~= nil then
                action.phase, action.pace, action.lastAttackHit = phase, "walk", hit
            end
            return false
        elseif phase == "windup" then
            if not inPosition then
                Animations.clear(shell)
                beginApproach(now, blocked == true, blocked and not Combat.isRanged(weapon))
                return false
            end
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            local hit = Combat.resolveAttack(actor, shell, target,
                action ~= nil and action.shove == true,
                action ~= nil and action.reaction or nil,
                action ~= nil and action.shoveFloor == true)
            local impactKind = "swing"
            if action ~= nil and action.shove == true then
                impactKind = "shove"
            elseif action ~= nil and action.floorAttack == true then
                impactKind = "floor"
            end
            Combat.noteMeleeImpact(shell, weapon, now, impactKind)
            if hit and action ~= nil and action.killReported ~= true then
                local deadOk, dead = pcall(function() return target:isDead() end)
                if deadOk and dead == true then
                    action.killReported = true
                    Voice.play(shell, "KILL_CONFIRMED")
                end
            end
            if action ~= nil then
                action.shove, action.reaction = nil, nil
                action.swingClass, action.shoveFloor = nil, nil
            end

            if hit then
                failedAttacks = 0
            elseif positionReason ~= "ready" then
                failedAttacks = failedAttacks + 1
            end
            if failedAttacks >= Combat.settings.maximumFailedAttacks then
                return abortUnreachable(now, "combat_attack_unresolved", distance)
            end
            phase = "recovery"

            local tired = Combat.tiredTempo(shell)
            local scale = Combat.meleeSwingScale(weapon) * tired
            local recoveryMs = math.floor(Combat.settings.meleeRecoveryMs * scale)
            local intervalMs = math.floor(Combat.settings.attackIntervalMs * scale)
            if action ~= nil and action.floorAttack == true then

                recoveryMs, intervalMs = math.floor(900 * tired), math.floor(1500 * tired)
                action.floorAttack = nil
            end
            phaseDeadlineAtMs = now + math.max(recoveryMs, intervalMs)

            Combat.setPhase(shell, phase, tactic, distance)
            Combat.refreshReadyWindow(aim, now)
            if action ~= nil then
                action.phase, action.pace, action.lastAttackHit = phase, "walk", hit
            end
            return false
        end

        if phase == "switch" then
            if now < phaseDeadlineAtMs then
                Combat.faceTarget(shell, target)
                return false
            end

            local selected = Combat.weaponFor(shell)
            local drawPreset, drawMs = Animations.drawPresetFor(shell, selected)
            pcall(Animations.setCombatHold, shell, true, true)
            if drawPreset ~= nil and Animations.apply(shell, drawPreset) == true then
                phase = "draw"
                phaseDeadlineAtMs = now + drawMs
            else
                pcall(Animations.setCombatHold, shell, true)
                phase = "approach"
            end
            aim.racked = true
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        end

        if phase == "cycle_action" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            if action ~= nil then action.cycleWeapon = nil end
            aim.racked = true

            aim.readyAtMs = now
            pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        end

        if phase == "recovery" then
            if now < phaseDeadlineAtMs then

                Combat.faceTarget(shell, target)

                if not Combat.isRanged(weapon)
                        and Animations.current[shell] == nil then
                    pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
                end
                return false
            end
            if action ~= nil and action.rangedShove == true
                    and Animations.active[shell] ~= nil then
                Combat.faceTarget(shell, target)
                return false
            end
            if action ~= nil then action.rangedShove = nil end

            if not Combat.isRanged(weapon) and Animations.active[shell] ~= nil then
                Combat.faceTarget(shell, target)
                return false
            end
            if Combat.isRanged(weapon) and inPosition then

                Combat.faceTarget(shell, target)
                phase = "approach"
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            local backStep = not Combat.isRanged(weapon)
                and Combat.meleeBackStep(actor, shell, target, aim, now, weapon) or nil
            if backStep ~= nil then
                aim.kitePoint = backStep
                phase = "kite"
                phaseDeadlineAtMs = math.max(now + (aim.footworkKind == "crewBackpedals"
                    and (tonumber(Combat.settings.meleeBackpedalMinMs) or 600) or 600), Combat.meleeReadyAtMs(shell) or now)
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                Combat.pathToward(shell, backStep, Combat.footworkPace(aim), true)
                return false
            end
            if not Combat.isRanged(weapon) and inPosition then
                pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
            else
                Animations.clear(shell)
            end
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end

            return false
        elseif phase == "reload" then

            if action == nil or action.reloadTransaction == nil then
                pcall(Animations.clear, shell)
                phase = "approach"
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            if action ~= nil and action.reloadAnimationLoopsRemaining ~= nil
                    and action.reloadAnimationLoopsRemaining > 0
                    and now >= (action.reloadAnimationNextAtMs or math.huge) then
                action.reloadAnimationLoopsRemaining =
                    action.reloadAnimationLoopsRemaining - 1

                if action.reloadLooping ~= true then
                    pcall(Animations.apply, shell, Combat.reloadPresetFor(shell, weapon))
                end
                pcall(function()
                    local insert = weapon:getInsertAmmoSound()
                    if insert ~= nil and insert ~= "" then ProjectALife.AudioPolicy.playFrom(shell, insert) end
                end)
                action.reloadAnimationNextAtMs = action.reloadAnimationNextAtMs
                    + (Combat.settings.internalReloadPerRoundMs or 950)
            end
            if action ~= nil and action.reloadInsertAtMs ~= nil
                    and now >= action.reloadInsertAtMs then
                action.reloadInsertAtMs = nil
                local committed = action.reloadTransaction ~= nil
                    and Magazines.commitReload(action.reloadTransaction)
                action.reloadCommitted = committed == true
                if committed == true then ProjectALife.NPCHitRelay.reload(shell, weapon, true) end
                pcall(function()
                    local insert = weapon:getInsertAmmoSound()
                    if insert ~= nil then ProjectALife.AudioPolicy.playFrom(shell, insert) end
                end)
            end
            if now < phaseDeadlineAtMs then return false end
            if action ~= nil and action.reloadCommitted == true then
                local rackPreset = Weapons.racksAfterReload(weapon)
                    and Combat.rackPresetFor(shell, weapon, "reload") or nil
                if rackPreset ~= nil then
                    pcall(Animations.apply, shell, rackPreset)
                    pcall(function()
                        local rack = weapon:getRackSound()
                        if rack ~= nil and rack ~= "" then ProjectALife.AudioPolicy.playFrom(shell, rack) end
                    end)
                    phase = "reload_rack"
                    phaseDeadlineAtMs = now + (Combat.settings.reloadRackMs or 900)
                    Combat.setPhase(shell, phase, tactic, distance)
                    action.phase, action.pace = phase, "walk"
                    return false
                end

                aim.racked = true
                aim.readyAtMs = nil
            end
            if action ~= nil then
                if action.reloadLooping == true then
                    pcall(Animations.clear, shell)
                end
                action.reloadLooping = nil
                action.reloadTransaction = nil
                action.reloadCommitted = nil
                action.reloadAnimationNextAtMs = nil
                action.reloadAnimationLoopsRemaining = nil
            end
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        elseif phase == "reload_rack" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            aim.racked = action ~= nil and action.reloadCommitted == true
            aim.readyAtMs = nil
            if action ~= nil then
                action.reloadLooping = nil
                action.reloadTransaction = nil
                action.reloadCommitted = nil
                action.reloadAnimationNextAtMs = nil
                action.reloadAnimationLoopsRemaining = nil
            end
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        elseif phase == "jammed" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            local jammedWeapon = action ~= nil and action.jammedWeapon or weapon
            local jamRack = Combat.rackPresetFor(shell, jammedWeapon, "reload")
            if jamRack ~= nil then
                pcall(Animations.apply, shell, jamRack)
                pcall(function()
                    local rack = jammedWeapon:getRackSound()
                    if rack ~= nil and rack ~= "" then ProjectALife.AudioPolicy.playFrom(shell, rack) end
                end)
            end
            phase = "unjam"
            phaseDeadlineAtMs = now + (Combat.settings.jamRackMs or 700)
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        elseif phase == "unjam" then
            Combat.faceTarget(shell, target)
            if now < phaseDeadlineAtMs then return false end
            local jammedWeapon = action ~= nil and action.jammedWeapon or weapon
            if Jamming ~= nil then Jamming.clear(shell, jammedWeapon) end
            if action ~= nil then action.jammedWeapon = nil end
            aim.racked = true
            aim.readyAtMs = nil
            phase = "approach"
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        elseif phase == "cover" then
            local point = aim.coverPoint
            local arrived = false
            local hx, hy = Combat.xyOf(shell)
            if point ~= nil and hx ~= nil and tonumber(point.x) ~= nil and tonumber(point.y) ~= nil then
                local dx, dy = hx - point.x, hy - point.y
                arrived = dx * dx + dy * dy <= 1.44
            end
            if arrived or now >= phaseDeadlineAtMs then
                Combat.cancelPath(shell)
                Combat.pathRequests[shell] = nil
                Combat.faceTarget(shell, target)
                Combat.setAimWalk(shell, true, "cover_arrived")
                if action ~= nil and action.disengage == true then
                    Combat.disengage(shell)
                    return true
                end

                if Combat.currentAmmo(weapon) > 0 then
                    pcall(Animations.apply, shell,
                        Combat.readyPresetFor(shell, weapon, target))
                end
                phase = Combat.currentAmmo(weapon) <= 0 and "approach" or "aim"
                phaseDeadlineAtMs = now + 150
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase = phase end

                aim.nextPositionAskMs = aim.coverUntilMs
            elseif point ~= nil then

                Combat.pathToward(shell, point, point.pace or "run", false)
            end
            return false
        elseif phase == "kite" then

            Combat.setAimWalk(shell, true, "break_contact")
            if not Combat.isRanged(weapon) then
                if now >= phaseDeadlineAtMs then
                    if aim.kitePoint ~= nil then
                        Combat.metrics.meleeStepsCut = (Combat.metrics.meleeStepsCut or 0) + 1
                    end
                    Combat.cancelPath(shell)
                    Combat.pathRequests[shell] = nil
                    Combat.faceTarget(shell, target)
                    Combat.footworkEnd(shell, aim, target)
                    aim.kiteSettleDistance, aim.kitePoint = nil, nil
                    phase = "approach"
                    phaseDeadlineAtMs = now
                    Combat.setPhase(shell, phase, tactic, distance)
                    if action ~= nil then action.phase, action.pace = phase, "walk" end
                elseif aim.kitePoint ~= nil and not Combat.repositionArrived(shell, aim.kitePoint,
                        Combat.settings.meleeStepArrive) then
                    Combat.pathToward(shell, aim.kitePoint, Combat.footworkPace(aim), false)
                else
                    if aim.kitePoint ~= nil then
                        Combat.metrics.meleeStepsDone = (Combat.metrics.meleeStepsDone or 0) + 1
                        aim.kitePoint = nil
                    end
                    Combat.cancelPath(shell)
                    Combat.pathRequests[shell] = nil
                    Combat.faceTarget(shell, target)
                    Combat.footworkEnd(shell, aim, target)
                end
                return false
            end

            local settled = now >= phaseDeadlineAtMs
                or (distance ~= nil and distance >= (tonumber(aim.kiteSettleDistance)
                    or Combat.settings.kiteTriggerDistance + 1))
            if settled then
                Combat.cancelPath(shell)
                Combat.pathRequests[shell] = nil
                Combat.faceTarget(shell, target)
                Combat.setAimWalk(shell, true, "break_contact_complete")

                pcall(Animations.apply, shell, Combat.readyPresetFor(shell, weapon, target))
                phase = "aim"
                phaseDeadlineAtMs = now + 150
                aim.kiteSettleDistance = nil
                aim.kitePoint = nil
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase = phase end
            elseif aim.kitePoint ~= nil then
                local held = Combat.weaponFor(shell)
                if held ~= nil and Combat.isRanged(held) and now >= (tonumber(aim.readyAtMs) or 0)
                        and not Combat.strikeHeld(actor, shell, target, now)
                        and Combat.muzzleOnTarget(shell, target) then
                    Combat.resolveAttack(actor, shell, target, false, "Shot")
                end

                Combat.pathToward(shell, aim.kitePoint, "run", false)
            end
            return false
        elseif phase == "reposition" and now < phaseDeadlineAtMs
                and not Combat.repositionArrived(shell, aim.repositionPoint) then
            return false
        end

        weapon = Combat.weaponFor(shell)
        if weapon == nil then return true end

        local wanted = Combat.preferredWeapon(shell, weapon, target, distance,
            Combat.currentEngagementFacts(actor, shell, target, now), actor)
        if wanted ~= nil and wanted ~= weapon
                and (now >= (aim.weaponSwitchAtMs or 0)
                or Combat.drawsOnHuman(weapon, wanted, target)) then
            aim.weaponSwitchAtMs = now + 10000

            Combat.noteSwap(shell, now)
            Weapons.select(shell, wanted, Weapons.slot(wanted)
                or (Combat.isRanged(wanted) and "primary" or "melee"))
            aim.racked = true
            aim.readyAtMs = nil
            pcall(function()
                local audioGuard = ProjectALife.AIFence
                if audioGuard ~= nil and type(audioGuard.silenceNativeVoice) == "function" then
                    audioGuard.silenceNativeVoice(shell, true)
                end
            end)
            Animations.clear(shell)
            pcall(Animations.setCombatHold, shell, false)
            phase = "switch"
            phaseDeadlineAtMs = now + (Combat.settings.weaponSwitchMs or 650)
            Combat.setPhase(shell, phase, tactic, distance)
            if action ~= nil then action.phase, action.pace = phase, "walk" end
            return false
        end

        if now >= (aim.nextPositionAskMs or 0) then
            aim.nextPositionAskMs = now + 600
            local registry = ProjectALife.ModuleRegistry
            local hurt = false

            pcall(function()
                local maximum = ProjectALife.ShellSimulation.maximumFor(shell)
                hurt = ProjectALife.ShellSimulation.trueHealth(shell) < maximum * Combat.settings.coverHurtFraction
            end)
            local offer = registry ~= nil and Combat.isRanged(weapon)
                and (aim.hasFired == true or hurt or Combat.currentAmmo(weapon) <= 0 or not inPosition)
                and registry.evaluate("positioning", actor, shell, {
                now = now, target = target, weapon = weapon, ranged = true,
                distance = distance, ammo = Combat.currentAmmo(weapon),

                reloading = Combat.currentAmmo(weapon) <= 0
                    and Magazines.canReload(shell, weapon) == true,
                hurt = hurt,
                threatIsGunman = Combat.targetIsGunman(target),
                coverUntilMs = aim.coverUntilMs,
                acceptOffer = Combat.positionOfferAllowed,
                range = Combat.holdReach(weapon, shell, target)
                    or Combat.maximumRange(weapon, shell) * Combat.settings.rangedReachFactor,
            }) or nil
            if not Combat.isRanged(weapon) then
                offer = Combat.meleeBreakOffer(actor, shell, target, distance, now)
            end

            if offer ~= nil and offer.x ~= nil and Combat.isRanged(weapon) then
                local tooNear = false
                pcall(function()
                    local dx, dy = offer.x - target:getX(), offer.y - target:getY()
                    local floor = Combat.desiredRange(weapon, shell) * 0.85
                    tooNear = (dx * dx + dy * dy) < floor * floor
                end)
                if tooNear then offer = nil end
            end

            if offer ~= nil and offer.reason == "cover_pin_wait" then return false end
            offer = Combat.leashOffer(actor, offer)
            if offer ~= nil and offer.x ~= nil then
                Combat.setAimWalk(shell, false, "cover_travel")
                if offer.maneuver then ProjectALife.FireManeuver.start(actor,shell,target,offer,now) end
                aim.coverPoint = offer
                aim.coverUntilMs = now + (tonumber(offer.holdMs) or 5000)
                aim.breakUntilMs = (offer.disengage == true or offer.reason == "withdraw_outnumbered_break")
                    and now + (tonumber(offer.legMs) or Combat.settings.coverLegMs) or nil
                phase = "cover"

                phaseDeadlineAtMs = now
                    + (tonumber(offer.legMs) or Combat.settings.coverLegMs)
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then
                    action.phase, action.pace = phase, offer.pace or "walk"
                    action.disengage = offer.disengage == true
                end

                if offer.pace == "run" then
                    pcall(function()
                        shell:getModData().ProjectALifeSprintUntilMs = phaseDeadlineAtMs
                    end)
                end
                Combat.pathToward(shell, offer, offer.pace or "walk", true)
                return false
            end
        end
        if Combat.isRanged(weapon) and Combat.currentAmmo(weapon) <= 0 then
            if not ProjectALife.NPCHitRelay.ready(shell) then return false end
            local previousWeapon = weapon
            local transaction = Weapons.beginReload(shell, weapon)
            if transaction ~= nil then
                ProjectALife.NPCHitRelay.reload(shell, weapon, false)

                Combat.cancelPath(shell)
                Combat.pathRequests[shell] = nil
                pcall(function() shell:setMoving(false) end)
                Combat.setAimWalk(shell, true, "reload")
                pcall(Animations.setCombatHold, shell, true)
                phase = "reload"
                local duration = transaction.internal
                    and (Combat.settings.internalReloadMs or 650)
                    or Combat.settings.reloadMs
                if transaction.internal then
                    duration = duration + math.max(0, transaction.rounds - 1)
                        * (Combat.settings.internalReloadPerRoundMs or 950)
                end
                phaseDeadlineAtMs = now + duration

                pcall(function()
                    local eject = weapon:getEjectAmmoSound()
                    if eject ~= nil then ProjectALife.AudioPolicy.playFrom(shell, eject) end
                end)
                local loopPreset = transaction.internal and transaction.rounds > 1
                    and Combat.loopReloadPresetFor(shell, weapon) or nil
                pcall(Animations.apply, shell, loopPreset or Combat.reloadPresetFor(shell, weapon))
                action.reloadLooping = loopPreset ~= nil
                Voice.play(shell, "RELOAD")
                action.reloadTransaction = transaction
                action.reloadInsertAtMs = now + math.floor(duration
                    * (transaction.internal and 0.82 or 0.55))
                if transaction.internal and transaction.rounds > 1 then

                    action.reloadAnimationLoopsRemaining = transaction.rounds - 1
                    action.reloadAnimationNextAtMs = now
                        + (Combat.settings.internalReloadPerRoundMs or 950)
                else
                    action.reloadLooping = nil
                    action.reloadAnimationLoopsRemaining = nil
                    action.reloadAnimationNextAtMs = nil
                end
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.pace = phase, "walk" end
                return false
            end
            Voice.play(shell, "OUT_OF_AMMO", { urgent = true })
            local ready = Weapons.ensureReady(shell)
            weapon = Combat.weaponFor(shell)

            pcall(function()
                if weapon == nil or weapon:isAimedFirearm() == true
                        or tostring(weapon:getFullType()) == "Base.BareHands" then
                    shell:getModData().ProjectALifeDryUntilMs = now + 60000
                end
            end)
            if weapon ~= previousWeapon then

                aim.racked = false
                aim.readyAtMs = nil
                pcall(Animations.setCombatHold, shell, true)
            end
            if not ready or weapon == nil then
                Combat.disengage(shell)
                return true
            end
        end

        inPosition, distance = Combat.attackPosition(shell, target, weapon)

        if not inPosition and phase == "approach" then
            local stuckData = Combat.dataOf(shell)
            local stuckSince = stuckData ~= nil and tonumber(stuckData.ProjectALifeStuckSinceMs) or nil
            local stuckLimit = 12000
            if aim.leashAnchor ~= nil and Combat.leashOutside(shell, aim.leashAnchor, aim.leashRange) ~= nil then
                stuckLimit = tonumber(Combat.settings.leashStuckGiveUpMs) or 4000
            end
            if stuckSince ~= nil and now - stuckSince > stuckLimit then
                stuckData.ProjectALifeStuckSinceMs = nil
                Combat.leashGiveUp(actor, shell, target, weapon, now)
                pcall(Combat.faceTarget, shell, target)
                return abortUnreachable(now, "combat_approach_stuck", distance)
            end

            local unstartedAt = aim.pathGiveUpAtMs
            if unstartedAt ~= nil then
                aim.pathGiveUpAtMs = nil
                if now >= unstartedAt and now - unstartedAt < 3000 then
                    Combat.leashGiveUp(actor, shell, target, weapon, now)
                    return abortUnreachable(now, "combat_path_unstarted", distance)
                end
            end

            if aim.edgeHoldSinceMs ~= nil and now >= aim.edgeHoldSinceMs
                    and now - aim.edgeHoldSinceMs >= (tonumber(Combat.settings.edgeGiveUpMs) or 2500) then
                Combat.noteHoldLimit(shell, aim, "edge", now - aim.edgeHoldSinceMs)
                aim.edgeHoldSinceMs = nil
                Combat.metrics.edgeGiveUps = (Combat.metrics.edgeGiveUps or 0) + 1
                Combat.leashGiveUp(actor, shell, target, weapon, now)
                return abortUnreachable(now, "combat_target_unreachable", distance)
            end

            if aim.leashHoldSinceMs == nil then
                aim.leashHoldDistance = nil
            elseif aim.leashHoldDistance == nil then
                aim.leashHoldDistance = distance
            end
            if aim.leashHoldSinceMs ~= nil and blockedSinceAtMs == nil and now >= aim.leashHoldSinceMs
                    and now - aim.leashHoldSinceMs >= (tonumber(Combat.settings.leashGiveUpMs) or 3000)
                    and Combat.leashTargetClosing(aim, distance) then
                aim.leashHoldSinceMs, aim.leashHoldDistance = now, distance
                Combat.metrics.leashHoldsExtended = (Combat.metrics.leashHoldsExtended or 0) + 1
            end
            if aim.leashHoldSinceMs ~= nil and blockedSinceAtMs == nil and now >= aim.leashHoldSinceMs
                    and now - aim.leashHoldSinceMs >= (tonumber(Combat.settings.leashGiveUpMs) or 3000) then
                Combat.noteHoldLimit(shell, aim, "leash", now - aim.leashHoldSinceMs)
                aim.leashHoldSinceMs = nil
                Combat.refuseOffLeash(actor, shell, now)
                Combat.watchFromPost(actor, shell, target, weapon)
                pcall(Combat.faceTarget, shell, target)
                Combat.metrics.leashGiveUps = (Combat.metrics.leashGiveUps or 0) + 1
                return abortUnreachable(now, "combat_target_unreachable", distance)
            end
        end

        local settledIndoors = Combat.closeQuarters(shell, target, distance)
            and Combat.clearAttackLine(shell, target, weapon)

        if inPosition and now >= nextRepositionAtMs
                and Combat.isRanged(weapon)
                and not settledIndoors
                and distance > (Combat.settings.shoveDistance or 1.15)
                and not Combat.targetIsDown(target) then
            local preferredDistance = Combat.desiredRange(weapon, shell)
            local destination, pace, nextTactic = Tactics.combatDestination(
                actor, shell, target, preferredDistance,
                Endurance.canSprint(actor, shell, now), now, Combat.isRanged(weapon),
                Combat.holdReach(weapon, shell, target))

            local postAnchor, postLeash = Combat.leashFor(actor)
            if postAnchor ~= nil and destination ~= nil then
                destination = Combat.leashedPoint(postAnchor, destination, postLeash)
            end
            local tooClose = Combat.isRanged(weapon) and distance ~= nil
                and distance < preferredDistance - 0.75
            if destination ~= nil and (nextTactic ~= "direct" or tooClose) then
                tactic = nextTactic
                phase = "reposition"
                aim.repositionPoint = destination
                phaseDeadlineAtMs = now + Combat.repositionDuration(shell, destination, pace)
                Combat.setPhase(shell, phase, tactic, distance)
                if action ~= nil then action.phase, action.tactic = phase, tactic end
                Combat.pathToward(shell, destination, pace, true)
                nextRepositionAtMs = phaseDeadlineAtMs + Combat.settings.flankPhaseMs
                return false
            end
        end
        if not inPosition and not Combat.isRanged(weapon)
                and positionReason == "out_of_range"
                and not Combat.targetIsDown(target)
                and distance ~= nil
                and distance <= Combat.meleeReachFor(weapon, target) then

            inPosition = true
        end
        if inPosition and not Combat.isRanged(weapon)
                and Combat.pressClosing(aim, weapon, target, distance) then
            inPosition = false
        end
        if inPosition then
            beginWindup(now, weapon, distance)
        else
            beginApproach(now, false, blocked and not Combat.isRanged(weapon))
        end
        return false
    end

    action = Ledger.begin({
        operationId = options.operationId
            or ("combat:" .. actor.uid .. ":" .. actor.generation .. ":" .. Combat.sequence),
        uid = actor.uid,
        generation = actor.generation,
        kind = "combat",
        fingerprint = options.fingerprint
            or (actor.uid .. ":" .. actor.generation .. ":" .. tostring(target)),
        startedAtMs = startedAt,
        deadlineAtMs = startedAt + math.max(10000, math.floor(options.timeoutMs or 60000)),
        maximumRecoveries = math.max(0, math.floor(options.maximumRecoveries or 20)),
        retryDelayMs = math.max(250, math.floor(options.retryDelayMs or 1000)),
        fallback = "safe_idle",
        isComplete = inspect,
        cancel = function() return Combat.disengage(shell) end,
        recover = function()
            if not Combat.targetAlive(target) then return true end

            if Combat.inClip(shell) then return true end
            return beginApproach(Combat.nowMs(), true)
        end,
    })
    if action == nil then
        Combat.disengage(shell)
        return nil, "combat_action_rejected"
    end
    action.target = target
    action.targetKind = options.targetKind or Combat.kindOf(target)
    action.phase = phase
    action.tactic = tactic
    action.pace = "walk"
    action.startedAtMs = startedAt
    if phase ~= "draw" and phase ~= "draw_reach" and phase ~= "land"
            and not beginApproach(startedAt, true) then
        Ledger.cancelActor(actor.uid, actor.generation, "combat_engage_failed")
        return nil, "combat_engage_failed"
    end
    return action
end

return Combat
