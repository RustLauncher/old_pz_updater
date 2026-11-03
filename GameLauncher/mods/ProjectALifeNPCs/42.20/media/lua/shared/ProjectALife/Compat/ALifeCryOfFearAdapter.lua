require "ProjectALife/Compat/ALifeCompatRegistry"

ProjectALife = ProjectALife or {}
if ProjectALife.CryOfFearAdapter ~= nil then return ProjectALife.CryOfFearAdapter end

local Registry = ProjectALife.CompatRegistry
local Adapter = {
    installed = false,
    sweepMs = 1000,
    sweepCap = 400,
    probeCap = 8,
    nextSweepMs = 0,
    config = {
        modIds = { "CryOfFear", "CryOfFearMonsters", "CryOfFearMod", "CoF", "CoFMonsters" },
        modContains = { "cryoffear", "cryfear" },
        modExact = { "cof", "cofmonsters", "cofmobs" },
        flagKeys = { "ProjectALifeHostileMonster", "CoF", "CoFMonster", "isCoF", "CryOfFear", "cofMonster" },
        namePrefixes = { "cof" },
        nameContains = { "cryoffear", "cry_of_fear", "faceless", "sawrunner", "suicider", "slugger", "carcass" },
    },
    seen = setmetatable({}, { __mode = "k" }),
    probed = {},
    metrics = { monsters = 0, targetingNpcs = 0, forcedBites = 0, sweeps = 0, probes = 0 },
}
ProjectALife.CryOfFearAdapter = Adapter

function Adapter.normal(text)
    return (string.gsub(string.lower(tostring(text or "")), "[^%w]", ""))
end

function Adapter.addMod(id)
    if type(id) == "string" and id ~= "" then Adapter.config.modIds[#Adapter.config.modIds + 1] = id end
end

function Adapter.addOutfit(token)
    if type(token) == "string" and token ~= "" then
        Adapter.config.nameContains[#Adapter.config.nameContains + 1] = string.lower(token)
        Adapter.seen = setmetatable({}, { __mode = "k" })
    end
end

function Adapter.addFlag(key)
    if type(key) == "string" and key ~= "" then Adapter.config.flagKeys[#Adapter.config.flagKeys + 1] = key end
end

function Adapter.modPresent(active)
    if type(active) ~= "table" then return false end
    local config = Adapter.config
    for _, id in ipairs(config.modIds) do
        if active[id] == true or active[string.lower(id)] == true then return true end
    end
    for id in pairs(active) do
        local flat = Adapter.normal(id)
        for _, token in ipairs(config.modContains) do
            if string.find(flat, token, 1, true) ~= nil then return true end
        end
        for _, exact in ipairs(config.modExact) do
            if flat == exact then return true end
        end
    end
    return false
end

function Adapter.nameMatches(name)
    if type(name) ~= "string" or name == "" then return false end
    local lowered = string.lower(name)
    for _, prefix in ipairs(Adapter.config.namePrefixes) do
        if string.sub(lowered, 1, #prefix) == prefix then return true end
    end
    for _, token in ipairs(Adapter.config.nameContains) do
        if string.find(lowered, token, 1, true) ~= nil then return true end
    end
    return false
end

function Adapter.flagged(body)
    if Registry.ask(body, "hasModData") == false then return false end
    local data = Registry.ask(body, "getModData")
    if type(data) ~= "table" then return false end
    for _, key in ipairs(Adapter.config.flagKeys) do
        if data[key] == true then return true end
    end
    return false
end

function Adapter.classify(body)
    if Registry.isOurs(body) then return false end
    if Adapter.flagged(body) then return true end
    if Adapter.nameMatches(Registry.ask(body, "getOutfitName")) then return true end
    if Adapter.nameMatches(Registry.ask(body, "getVariableString", "ZombieType")) then return true end
    return false
end

function Adapter.isMonster(body)
    if not Adapter.installed or body == nil then return false end
    local known = Adapter.seen[body]
    if known ~= nil then return known end
    local verdict = Adapter.classify(body) == true
    Adapter.seen[body] = verdict
    if verdict then Adapter.probe(body) end
    return verdict
end

function Adapter.probe(body)
    local metrics = Adapter.metrics
    if metrics.probes >= Adapter.probeCap then return end
    local outfit = tostring(Registry.ask(body, "getOutfitName"))
    if Adapter.probed[outfit] then return end
    Adapter.probed[outfit] = true
    metrics.probes = metrics.probes + 1
    print("[A-Life] CryOfFear monster seen: outfit=" .. outfit .. " state=" .. tostring(Registry.ask(body, "getActionStateName")))
end

function Adapter.forcePose(zombie, bite, now, window)
    if not Adapter.installed or type(bite) ~= "table" then return false end
    if bite.forced == true then return true end
    local opened = tonumber(bite.openedAtMs) or now
    if now - opened < (tonumber(window) or 900) * 0.5 then return false end
    if not Adapter.isMonster(zombie) then return false end
    bite.forced = true
    Adapter.metrics.forcedBites = Adapter.metrics.forcedBites + 1
    return true
end

function Adapter.sweep(now)
    local metrics = Adapter.metrics
    metrics.sweeps = metrics.sweeps + 1
    local cell = type(getCell) == "function" and getCell() or nil
    local list = cell ~= nil and Registry.ask(cell, "getZombieList") or nil
    local count = list ~= nil and tonumber(Registry.ask(list, "size")) or 0
    local horde = ProjectALife.HordeRelations
    local monsters, targeting = 0, 0
    for index = 0, math.min(count, Adapter.sweepCap) - 1 do
        local body = Registry.ask(list, "get", index)
        if body ~= nil and Adapter.isMonster(body) and Registry.ask(body, "isDead") ~= true then
            monsters = monsters + 1
            local memory = horde ~= nil and type(horde.chaseOf) == "function" and horde.chaseOf(body) or nil
            if type(memory) == "table" and memory.kind == "actor" then targeting = targeting + 1 end
        end
    end
    metrics.monsters, metrics.targetingNpcs = monsters, targeting
end

function Adapter.tick()
    if not Adapter.installed then return end
    local now = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    if now < Adapter.nextSweepMs and now >= Adapter.nextSweepMs - 2 * Adapter.sweepMs then return end
    Adapter.nextSweepMs = now + Adapter.sweepMs
    Adapter.sweep(now)
end

function Adapter.qaLine()
    local metrics = Adapter.metrics
    return "[ALIFE-QA] CryOfFear: active=" .. tostring(Adapter.installed) .. " monsters=" .. tostring(metrics.monsters)
        .. " targetingNpcs=" .. tostring(metrics.targetingNpcs) .. " forcedBites=" .. tostring(metrics.forcedBites)
end

function Adapter.detect()
    local compat = ProjectALife.ModCompat
    if compat == nil or type(compat.activeSet) ~= "function" then return false end
    return Adapter.modPresent(compat.activeSet())
end

function Adapter.install()
    if Adapter.installed then return true end
    Adapter.installed = true
    if not Adapter.hooked and type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
        Events.OnTick.Add(Adapter.tick)
        Adapter.hooked = true
    end
    return true
end

function Adapter.undo()
    Adapter.installed = false
    Adapter.seen = setmetatable({}, { __mode = "k" })
end

Registry.register({ id = "CryOfFear", mods = {}, phase = "client",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
