require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local B = {
    id = "breach_policy", cacheMs = 2000, windowTries = 3, windowMs = 15000, windowKeepMs = 60000,
    raidEncounters = { "raid", "fullscale_raid", "assassination" },
    raidModes = { hunt = true, manhunt = true, assault = true, full_raid = true },
    raidIntents = { hunt_nearby = true, manhunt_player = true, assault_player = true, full_raid = true },
    lootIntents = { collect_supplies = true, search_container = true, scavenge = true },
    fightKinds = { combat = true, retreat = true, recovering = true },
    cache = {}, tries = {}, nextPruneMs = 0,
    metrics = { noMotive = 0, otherWay = 0, windowFirst = 0, held = 0, passed = 0 },
}
ProjectALife.Breaching = B

function B.active()
    return Gate.on(B.id, "Breach_Policy", true)
end

function B.ask(object, method, ...)
    if object == nil then return nil end
    local query = object[method]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object, ...)
    if not ok then return nil end
    return value
end

function B.sides(shell, object)
    local traversal = ProjectALife.ObstacleTraversal
    local near, far = traversal.trySquare, traversal.tryNext
    if near ~= nil and far ~= nil and B.ask(near, "getBuilding") ~= B.ask(far, "getBuilding") then return near, far end
    local a, b = B.ask(object, "getSquare"), B.ask(object, "getOppositeSquare")
    if a == nil or b == nil then return nil, nil end
    local sx, sy = tonumber(B.ask(shell, "getX")), tonumber(B.ask(shell, "getY"))
    if sx == nil or sy == nil then return nil, nil end
    local da = (a:getX() + 0.5 - sx) ^ 2 + (a:getY() + 0.5 - sy) ^ 2
    local db = (b:getX() + 0.5 - sx) ^ 2 + (b:getY() + 0.5 - sy) ^ 2
    if db < da then return b, a end
    return a, b
end

function B.motive(actor, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local decisions = ProjectALife.DecisionLoop
    local order = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders[actor.uid] or nil
    if type(order) == "table" and order.generation == actor.generation
            and (order.untilMs == nil or now < (tonumber(order.untilMs) or 0)) then
        return "order"
    end
    local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[actor.uid] or nil
    if type(state) == "table" then
        if B.fightKinds[state.kind] then return "fight" end
        if B.raidIntents[state.intent] then return "raid" end
    end
    local crew = ProjectALife.MeleeCrew
    if crew ~= nil and type(crew.breachMotive) == "function" and crew.breachMotive(actor, state) == true then
        return "breach_axe"
    end
    local encounter = string.lower(tostring(memory.encounterKind or memory.encounter or ""))
    for _, kind in ipairs(B.raidEncounters) do
        if string.sub(encounter, 1, #kind) == kind then return "raid" end
    end
    if memory.hostileOverride == true then return "raid" end
    local backup = memory.supportRole == "backup" or memory.role == "backup"
    local programs, catalog = ProjectALife.Programs, ProjectALife.Catalog
    local mode
    if programs ~= nil and type(programs.mode) == "function" and catalog ~= nil and type(catalog.faction) == "function" then
        local faction = catalog.faction(actor.factionId)
        local program = type(faction) == "table" and type(faction.spawn) == "table"
            and string.lower(tostring(faction.spawn.program or "patrol")) or "patrol"
        local ok, value = pcall(programs.mode, actor, program)
        mode = ok and value or nil
    end
    if B.raidModes[mode] and not backup then return "raid" end
    if memory.lootPhase ~= nil and mode == "scavenge" then return "loot" end
    if actor.activity == "scavenging" or (type(state) == "table" and (state.kind == "scavenging" or B.lootIntents[state.intent])) then
        return "loot"
    end
    return nil
end

function B.kindOf(opening)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or opening.ix == nil then return nil end
    local z = math.floor(tonumber(opening.z) or 0)
    local out = cell:getGridSquare(math.floor(opening.x), math.floor(opening.y), z)
    local inside = cell:getGridSquare(math.floor(opening.ix), math.floor(opening.iy), z)
    if out == nil or inside == nil then return nil end
    local door = B.ask(out, "getDoorTo", inside) or B.ask(inside, "getDoorTo", out)
    if door ~= nil then return "door", B.ask(door, "isBarricaded") == true end
    local window = B.ask(out, "getWindowTo", inside) or B.ask(inside, "getWindowTo", out)
        or B.ask(out, "getWindowFrameTo", inside) or B.ask(inside, "getWindowFrameTo", out)
    if window ~= nil then return "window", B.ask(window, "isBarricaded") == true end
    return nil
end

function B.alternative(shell, actor, far, edgeKey, forcingDoor, now)
    local key = tostring(actor.uid) .. "|" .. tostring(edgeKey)
    local hit = B.cache[key]
    if hit ~= nil and now < hit.untilMs then return hit.answer end
    local entrances = ProjectALife.Entrances
    local building = B.ask(far, "getBuilding")
    local answer = false
    if entrances ~= nil and type(entrances.openings) == "function" and building ~= nil then
        local ok, list = pcall(entrances.openings, building, shell:getX(), shell:getY(), shell:getZ(), actor, false)
        if ok and type(list) == "table" then
            if type(entrances.dropFailed) == "function" then
                local copy = {}
                for index, opening in ipairs(list) do copy[index] = opening end
                list = entrances.dropFailed(copy, shell) or copy
            end
            local closed = type(entrances.cost) == "table" and tonumber(entrances.cost.closedDoor) or 2
            for _, opening in ipairs(list) do
                if opening.edgeKey ~= nil and opening.edgeKey ~= edgeKey then
                    local kind, barricaded = B.kindOf(opening)
                    if kind == "door" and not barricaded and (tonumber(opening.cost) or 99) <= closed then
                        answer = "other_way"
                        break
                    end
                    if forcingDoor and kind == "window" and not barricaded then answer = "window_first" end
                end
            end
        end
    end
    B.cache[key] = { answer = answer, untilMs = now + B.cacheMs }
    return answer
end

function B.windowSpent(uid, edgeKey, now)
    if uid == nil or edgeKey == nil then return false end
    B.tries[uid] = B.tries[uid] or {}
    local entry = B.tries[uid][edgeKey]
    if entry == nil or now - entry.firstMs > B.windowKeepMs then
        entry = { count = 0, firstMs = now }
        B.tries[uid][edgeKey] = entry
    end
    entry.count = entry.count + 1
    return entry.count > B.windowTries or now - entry.firstMs >= B.windowMs
end

function B.prune(now)
    if now < B.nextPruneMs then return end
    B.nextPruneMs = now + B.windowKeepMs
    for key, hit in pairs(B.cache) do
        if now >= hit.untilMs then B.cache[key] = nil end
    end
    for uid, edges in pairs(B.tries) do
        for edgeKey, entry in pairs(edges) do
            if now - entry.firstMs > B.windowKeepMs then edges[edgeKey] = nil end
        end
        local any = false
        for _ in pairs(edges) do any = true break end
        if not any then B.tries[uid] = nil end
    end
end

function B.refusal(shell, object)
    if shell == nil or object == nil or not B.active() then return nil end
    local policy, traversal = ProjectALife.DoorPolicy, ProjectALife.ObstacleTraversal
    if policy == nil or traversal == nil or type(policy.actorOf) ~= "function" then return nil end
    local actor = policy.actorOf(shell)
    if actor == nil then return nil end
    local near, far = B.sides(shell, object)
    if near == nil or far == nil then return nil end
    local into, from = B.ask(far, "getBuilding"), B.ask(near, "getBuilding")
    if into == nil or into == from then return nil end
    local now = Gate.nowMs()
    B.prune(now)
    local motive = B.motive(actor, now)
    if motive == nil then
        B.metrics.noMotive = B.metrics.noMotive + 1
        if type(traversal.refuseCourteously) == "function" then traversal.refuseCourteously(shell) end
        return "breach_no_motive_reroute"
    end
    local edgeKey = traversal.edgeKey(near, far)
    if motive == "raid" or motive == "loot" then
        local forcingDoor = B.ask(near, "getDoorTo", far) ~= nil
        local other = B.alternative(shell, actor, far, edgeKey, forcingDoor, now)
        if other == "other_way" then
            B.metrics.otherWay = B.metrics.otherWay + 1
            traversal.markOpening(shell, edgeKey, "courteous", now)
            return "breach_other_way_reroute"
        end
        if other == "window_first" then
            if not B.windowSpent(actor.uid, edgeKey, now) then
                B.metrics.windowFirst = B.metrics.windowFirst + 1
                traversal.markOpening(shell, edgeKey, "courteous", now)
                return "breach_window_first_reroute"
            end
        end
    end
    if type(traversal.boundaryEntry) == "function" and traversal.boundaryEntry(shell, object, actor) == false then
        B.metrics.held = B.metrics.held + 1
        return "breach_told_reroute"
    end
    B.metrics.passed = B.metrics.passed + 1
    return nil
end

return B
