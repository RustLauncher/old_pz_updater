ProjectALife = ProjectALife or {}
if ProjectALife.Interop ~= nil then return ProjectALife.Interop end

local Interop = { VERSION = 1, residents = {}, hooks = {},
    metrics = { failed = 0, residentFailed = 0, spawned = 0, died = 0, hits = 0, inventoryFailed = 0,
        listeners = 0, residentTests = 0, hookListeners = {} },
    spawnedBodies = setmetatable({}, { __mode = "k" }),
    deadBodies = setmetatable({}, { __mode = "k" }),
    lootedBodies = setmetatable({}, { __mode = "k" }),
    events = { ProjectALife_NpcSpawned = true, ProjectALife_NpcDied = true,
        ProjectALife_NpcHit = true, ProjectALife_Shot = true },
    points = { ["outpost.beforeBuildRound"] = true, ["outpost.afterTeardown"] = true,
        ["outpost.siting"] = true, ["loot.corpse"] = true } }
ProjectALife.Interop = Interop

function Interop.registerEvents()
    if LuaEventManager == nil or type(LuaEventManager.AddEvent) ~= "function" then return false end
    for name in pairs(Interop.events) do
        local ok = pcall(LuaEventManager.AddEvent, name)
        if not ok then Interop.metrics.failed = Interop.metrics.failed + 1 end
    end
    return true
end

function Interop.emit(name, ...)
    if Interop.events[name] ~= true or type(triggerEvent) ~= "function" then return false end
    local ok = pcall(triggerEvent, name, ...)
    if not ok then Interop.metrics.failed = Interop.metrics.failed + 1 end
    return ok
end

function Interop.once(published, body, uid, generation)
    if type(body) ~= "table" and type(body) ~= "userdata" then return false end
    if type(uid) ~= "string" or uid == "" or tonumber(generation) == nil then return false end
    local key = uid .. ":" .. tostring(generation)
    if published[body] == key then return false end
    published[body] = key
    return true
end

function Interop.exploreWanted()
    local gate = ProjectALife.FeatureGate
    if type(gate) ~= "table" or type(gate.flag) ~= "function" then return false end
    return ProjectALife.FeatureGate.flag("Compat_NoPocketLoot", false) == true
end

function Interop.explore(body)
    if not Interop.exploreWanted() then return false end
    if type(body.getInventory) ~= "function" then return false end
    local ok, inventory = pcall(body.getInventory, body)
    if not ok or inventory == nil or type(inventory.setExplored) ~= "function" then return false end
    ok = pcall(inventory.setExplored, inventory, true)
    if not ok then Interop.metrics.inventoryFailed = Interop.metrics.inventoryFailed + 1 end
    return ok
end

function Interop.spawned(body, uid, generation)
    if Interop.uidOf(body) ~= uid or not Interop.once(Interop.spawnedBodies, body, uid, generation) then return false end
    Interop.explore(body)
    Interop.metrics.spawned = Interop.metrics.spawned + 1
    return Interop.emit("ProjectALife_NpcSpawned", body, uid)
end

function Interop.died(body, uid, generation, killer)
    if not Interop.once(Interop.deadBodies, body, uid, generation) then return false end
    Interop.metrics.died = Interop.metrics.died + 1
    return Interop.emit("ProjectALife_NpcDied", body, uid, killer)
end

function Interop.hit(body, attacker, damage)
    if not Interop.isNpc(body) or type(damage) ~= "number" or damage ~= damage
            or damage <= 0 or damage == math.huge then return false end
    Interop.metrics.hits = Interop.metrics.hits + 1
    return Interop.emit("ProjectALife_NpcHit", body, attacker, damage)
end

function Interop.onDead(body)
    if type(isClient) ~= "function" or not isClient() then return false end
    local uid = Interop.uidOf(body)
    if uid == nil then return false end
    local data = Interop.data(body)
    local generation = data ~= nil and tonumber(data.ProjectALifeGeneration) or nil
    if generation == nil then generation = tonumber(Interop.variable(body, "ALifeGeneration")) end
    local killer
    if type(body.getAttackedBy) == "function" then
        local ok, value = pcall(body.getAttackedBy, body)
        if ok then killer = value end
    end
    return Interop.died(body, uid, generation, killer)
end

function Interop.data(body)
    if type(body) ~= "table" and type(body) ~= "userdata" then return nil end
    if type(body.getModData) ~= "function" then return nil end
    if type(body.hasModData) == "function" then
        local ok, has = pcall(body.hasModData, body)
        if not ok or has ~= true then return nil end
    end
    local ok, data = pcall(body.getModData, body)
    if ok and type(data) == "table" then return data end
    return nil
end

function Interop.variable(body, name)
    if type(body) ~= "table" and type(body) ~= "userdata" then return nil end
    local getter = body.getVariableString
    if type(getter) ~= "function" then getter = body.GetVariable end
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, body, name)
    if ok then return value end
    return nil
end

function Interop.isNpc(body)
    local data = Interop.data(body)
    if data ~= nil and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true) then return true end
    local marked = Interop.variable(body, "ALifeActor")
    return marked == true or marked == "true"
end

function Interop.uidOf(body)
    if not Interop.isNpc(body) then return nil end
    local data = Interop.data(body)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    if type(uid) ~= "string" or uid == "" then uid = Interop.variable(body, "ALifeUID") end
    if type(uid) == "string" and uid ~= "" then return uid end
    return nil
end

function Interop.snapshot(value, seen, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind ~= "table" or depth >= 8 or seen[value] then return nil end
    seen[value] = true
    local result, count = {}, 0
    for key, entry in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            result[key] = Interop.snapshot(entry, seen, depth + 1)
            count = count + 1
            if count >= 128 then break end
        end
    end
    seen[value] = nil
    return result
end

function Interop.actorOf(uid)
    if type(uid) ~= "string" then return nil end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.peek) ~= "function" then return nil end
    local actor = registry.peek(uid)
    if type(actor) ~= "table" then return nil end
    return Interop.snapshot(actor, {}, 0)
end

function Interop.visitActor(callback, actor)
    if actor.lifecycle == "active" then
        local ok = pcall(callback, Interop.snapshot(actor, {}, 0))
        if not ok then Interop.metrics.failed = Interop.metrics.failed + 1 end
        return 1
    end
    return 0
end

function Interop.forEachNpc(callback)
    if type(callback) ~= "function" then return 0 end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    local visited = 0
    registry.each(function(actor) visited = visited + Interop.visitActor(callback, actor) end)
    return visited
end

function Interop.registerResidentTest(callback)
    if type(callback) ~= "function" then return false end
    for _, registered in ipairs(Interop.residents) do if registered == callback then return true end end
    Interop.residents[#Interop.residents + 1] = callback
    Interop.metrics.residentTests = #Interop.residents
    return true
end

function Interop.classify(body)
    if Interop.isNpc(body) then
        for _, callback in ipairs(Interop.residents) do
            local ok, resident = pcall(callback, body)
            if not ok then Interop.metrics.residentFailed = Interop.metrics.residentFailed + 1 end
            if ok and resident == true then return "npc_resident" end
        end
        return "npc_human"
    end
    if (type(body) == "table" or type(body) == "userdata") and type(instanceof) == "function"
            and instanceof(body, "IsoZombie") then return "zombie" end
    return "unknown"
end

function Interop.on(name, callback)
    if Interop.points[name] ~= true or type(callback) ~= "function" then return false end
    local callbacks = Interop.hooks[name] or {}
    for _, registered in ipairs(callbacks) do if registered == callback then return true end end
    callbacks[#callbacks + 1] = callback
    Interop.hooks[name] = callbacks
    Interop.listenerCounts()
    return true
end

function Interop.listenerCounts()
    local counts, total = {}, 0
    for name in pairs(Interop.points) do
        local count = #(Interop.hooks[name] or {})
        counts[name] = count
        total = total + count
    end
    Interop.metrics.listeners = total
    Interop.metrics.hookListeners = Interop.snapshot(counts, {}, 0)
    return counts
end

function Interop.qaLine()
    local hooks = {}
    for name, count in pairs(Interop.listenerCounts()) do hooks[#hooks + 1] = name .. ":" .. tostring(count) end
    table.sort(hooks)
    local m = Interop.metrics
    return "[ALIFE-QA] Interop: v=" .. tostring(Interop.VERSION) .. " listeners=" .. tostring(m.listeners)
        .. " residents=" .. tostring(#Interop.residents) .. " spawned=" .. tostring(m.spawned)
        .. " died=" .. tostring(m.died) .. " hits=" .. tostring(m.hits) .. " failed=" .. tostring(m.failed)
        .. " residentFailed=" .. tostring(m.residentFailed) .. " inventoryFailed=" .. tostring(m.inventoryFailed)
        .. " hooks=" .. table.concat(hooks, ",")
end

function Interop.argument(value)
    if type(value) == "table" then return Interop.snapshot(value, {}, 0) end
    return value
end

function Interop.call(callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then Interop.metrics.failed = Interop.metrics.failed + 1 end
    return ok, result
end

function Interop.run(name, a, b, c, d)
    local allowed = true
    for _, callback in ipairs(Interop.hooks[name] or {}) do
        local ok, result = Interop.call(callback, Interop.argument(a), Interop.argument(b),
            Interop.argument(c), Interop.argument(d))
        if ok and result == false then allowed = false end
    end
    return allowed
end

function Interop.looted(shell, actor, plan)
    if type(actor) ~= "table" or not Interop.isNpc(shell)
            or not Interop.once(Interop.lootedBodies, shell, actor.uid, actor.generation or 0) then return false end
    return Interop.run("loot.corpse", shell, actor, plan)
end

Interop.registerEvents()
if type(Events) == "table" and Events.OnZombieDead ~= nil
        and type(Events.OnZombieDead.Add) == "function" then
    Events.OnZombieDead.Add(Interop.onDead)
end
return Interop
