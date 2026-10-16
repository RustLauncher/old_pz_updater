require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Senses/ALifeInvestigation"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Tactics = ProjectALife.SquadTactics
local Endurance = ProjectALife.Endurance

Registry.register({
    id = "orders",
    label = "Follow orders",
    summary = "Obeys hold/move orders issued by an admin or the director.",
    kind = "orders",
    evaluate = function(actor, shell, context)
        local order = context.orders and context.orders[actor.uid] or nil
        local explicit = order ~= nil and order.generation == actor.generation and order.source ~= "leader"
            and (order.untilMs == nil or context.now < order.untilMs)
        local stance = actor.memory and actor.memory.stance
        local stances = ProjectALife.ModuleStances
        if not explicit and stances ~= nil and type(stances.visitHold) == "function" then
            local held = stances.visitHold(actor, shell, context)
            if held ~= nil then return held end
        end
        if not explicit and stance == "visit" then
            local visitStance = Registry.get("stance")
            local held = visitStance ~= nil and visitStance.evaluate(actor, shell, context) or nil
            if held ~= nil then return held end
        end
        if order == nil or order.generation ~= actor.generation then return nil end
        if order.source == "leader" and (stance == "blockade" or stance == "garrison" or stance == "holdout" or stance == "occupy_high" or stance == "shelter") then

            context.orders[actor.uid] = nil
            return nil
        end

        if order.untilMs ~= nil and context.now >= order.untilMs then
            context.orders[actor.uid] = nil
            return nil
        end
        if order.kind == "hold" then
            if order.source == "leader" and type(order.anchor) == "table"
                    and type(order.anchor.x) == "number" and type(order.anchor.y) == "number"
                    and type(order.anchor.z) == "number"
                    and type(shell.getX) == "function" and type(shell.getY) == "function"
                    and type(shell.getZ) == "function" then
                local dx, dy = shell:getX() - order.anchor.x, shell:getY() - order.anchor.y
                if dx * dx + dy * dy > 1 or math.floor(shell:getZ()) ~= math.floor(order.anchor.z) then
                    local state = context.startMovement(actor, shell, order.anchor, "hold")
                    if state ~= nil then return state end
                end
            end
            local life = ProjectALife.ModuleIdleLife
            if life ~= nil and type(life.postBeat) == "function" then
                local rest = life.postBeat(actor, shell, context)
                if rest ~= nil then return rest end
            end
            context.setActivity(actor, "idle", "hold_position")
            return { kind = "idle", intent = "hold_position",
                cooldownUntilMs = context.now + 1000 }
        end
        local target = context.orderedTarget(order, shell)
        if target == nil then return nil end

        if target.close == true then
            context.setActivity(actor, "idle", "follow_close")
            return { kind = "idle", intent = "follow_close",
                cooldownUntilMs = context.now + 500 }
        end
        return context.startMovement(actor, shell, target, order.kind)
    end,
})

Registry.register({
    id = "investigate",
    label = "Investigate noises",
    summary = "Walks toward gunfire and other sounds it did not make.",
    kind = "upkeep",
    evaluate = function(actor, shell, context)

        if actor.memory and actor.memory.lootPhase and (context.mode == "scavenge"
                or (ProjectALife.GroupPlan ~= nil and ProjectALife.GroupPlan.working(actor))) then return nil end
        local investigation = ProjectALife.Investigation
        if investigation == nil then return nil end
        local heard = investigation.destinationFor(actor, shell, context.now)
        if heard == nil then return nil end
        local state = context.startMovement(actor, shell, heard, "investigate", {
            timeoutMs = 15000,
        })
        if state ~= nil then
            investigation.consume(actor, heard)
            context.setActivity(actor, "moving", "investigate_sound")
        end
        return state
    end,
})

Registry.register({
    id = "regroup",
    label = "Regroup",
    summary = "Closes back up with the rest of the group when it drifts apart.",
    kind = "upkeep",
    evaluate = function(actor, shell, context)
        if actor.memory and actor.memory.lootPhase and (context.mode == "scavenge"
                or (ProjectALife.GroupPlan ~= nil and ProjectALife.GroupPlan.working(actor))) then return nil end
        local destination = Tactics.regroupDestination(actor, shell, 14)
        if destination == nil then return nil end
        return context.startMovement(actor, shell, destination, "regroup", {
            pace = Endurance.canSprint(actor, shell, context.now) and "run" or "walk",
            timeoutMs = 12000,
        })
    end,
})

local March = { spanTiles = 6, minimumSpacing = 1.2, maximumSpacing = 2.5, legTiles = 22 }
ProjectALife.GroupMarch = March

function March.spacing(size)
    local members = math.max(1, math.floor(tonumber(size) or 1))
    return math.max(March.minimumSpacing, math.min(March.maximumSpacing, March.spanTiles / members))
end

function March.laneOffset(actor, size)
    local flanking = ProjectALife.ModuleFlanking
    if flanking == nil or type(flanking.laneIndex) ~= "function" or type(flanking.lanes) ~= "table" then return 0 end
    local lanes = flanking.lanes
    local lane = lanes[(flanking.laneIndex(actor) % #lanes) + 1] or 0
    return lane * March.spacing(size)
end

Registry.register({
    id = "groupMarch",
    label = "Group march",
    summary = "Shares one travel heading with the rest of the group.",
    kind = "upkeep",
    evaluate = function(actor, shell, context)
        local memory = actor.memory or {}
        if type(memory.groupId) ~= "string" then return nil end
        if not Tactics.groupHasLeader(memory.groupId) then return nil end
        local slot = math.floor(context.now / 45000)
        local ok, sx, sy, sz = pcall(function()
            return shell:getX(), shell:getY(), shell:getZ()
        end)
        if not ok then return nil end

        local march = memory.groupMarch
        local arrived = type(march) == "table" and march.x ~= nil
            and ((march.x - sx) ^ 2 + (march.y - sy) ^ 2) <= 4
        if type(march) ~= "table" or march.slot ~= slot or arrived then
            local seed = 0
            for index = 1, #memory.groupId do
                seed = (seed * 31 + string.byte(memory.groupId, index)) % 2147483647
            end
            local heading = ((seed + slot * 137) % 360) * math.pi / 180
            local spread = ProjectALife.GroupSpread
            local shaped = spread ~= nil and type(spread.marchTarget) == "function"
                and spread.marchTarget(actor, shell, heading, March.legTiles, context.now) or nil
            if shaped ~= nil and shaped.wait ~= nil then
                return { kind = "idle", intent = "march_stagger", cooldownUntilMs = context.now + shaped.wait }
            end
            if shaped ~= nil then
                march = { slot = slot, x = shaped.x, y = shaped.y, z = shaped.z, shaped = true }
            else
                local lane = March.laneOffset(actor, memory.groupSize)
                march = {
                    slot = slot,
                    x = sx + math.cos(heading) * March.legTiles - math.sin(heading) * lane,
                    y = sy + math.sin(heading) * March.legTiles + math.cos(heading) * lane,
                    z = sz,
                }
            end

            if type(context.persistMemory) == "function" then
                context.persistMemory(actor, "groupMarch", march)
            else
                memory.groupMarch = march
            end
        end
        if march.shaped == true and ((march.x - sx) ^ 2 + (march.y - sy) ^ 2) <= 1.44 then
            return { kind = "idle", intent = "march_hold", cooldownUntilMs = context.now + 900 }
        end
        return context.startMovement(actor, shell,
            { x = march.x, y = march.y, z = march.z }, "patrol",
            { timeoutMs = context.defaults.movement.patrolTimeoutMs })
    end,
})

return true
