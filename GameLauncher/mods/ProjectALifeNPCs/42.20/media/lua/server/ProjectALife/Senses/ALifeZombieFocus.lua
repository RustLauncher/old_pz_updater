require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local F = {
    id = "zombie_focus", ignoreMs = 750, maxSkips = 5, closingRadius = 15, postRadius = 12, outpostMargin = 10,
    metrics = { skipped = 0, kept = 0 },
}
ProjectALife.ZombieFocus = F

function F.active()
    return Gate.on(F.id, "ZombieFocus_Enabled", true)
end

function F.radius()
    return Gate.number("ZombieFocus_Radius", 8, 2, 30)
end

function F.ask(object, method, ...)
    if object == nil then return nil end
    local query = object[method]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object, ...)
    if not ok then return nil end
    return value
end

function F.isPlayer(object)
    return object ~= nil and type(instanceof) == "function" and instanceof(object, "IsoPlayer") == true
end

function F.targetsFriend(actor, shell, zombie, now)
    local target = F.ask(zombie, "getTarget")
    if target == nil then return false end
    if target == shell then return true end
    local relations = ProjectALife.Relations
    if relations == nil then return false end
    if F.isPlayer(target) then
        if type(relations.playerStance) ~= "function" then return false end
        local ok, stance = pcall(relations.playerStance, actor, target)
        if not ok then return false end
        if stance == "friendly" or stance == "allied" then return true end
        if stance == "neutral" then
            local speech = ProjectALife.Speech
            local key = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(target) or nil
            local lease = type(actor.memory) == "table" and type(actor.memory.tolerateUntil) == "table"
                and key ~= nil and tonumber(actor.memory.tolerateUntil[key]) or nil
            return lease ~= nil and now < lease
        end
        return false
    end
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.actorOf) ~= "function" or type(relations.sameSide) ~= "function" then return false end
    local ally = policy.actorOf(target)
    return type(ally) == "table" and relations.sameSide(actor, ally) == true
end

function F.atHome(actor, zombie)
    local zx, zy = tonumber(F.ask(zombie, "getX")), tonumber(F.ask(zombie, "getY"))
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if zx == nil or zy == nil or memory == nil then return false end
    local outposts = ProjectALife.OutpostRegistry
    if memory.outpostId ~= nil and outposts ~= nil and type(outposts.read) == "function" then
        local site = outposts.read(memory.outpostId)
        local b = type(site) == "table" and site.bounds or nil
        local margin = F.outpostMargin
        if type(b) == "table" and zx >= (b.x1 or 0) - margin and zx <= (b.x2 or 0) + margin
                and zy >= (b.y1 or 0) - margin and zy <= (b.y2 or 0) + margin then
            return true
        end
    end
    local anchor = memory.stance ~= "route" and (memory.stancePost or memory.stanceAnchor) or nil
    if type(anchor) == "table" and tonumber(anchor.x) ~= nil and tonumber(anchor.y) ~= nil then
        return (zx - anchor.x) ^ 2 + (zy - anchor.y) ^ 2 <= F.postRadius ^ 2
    end
    return false
end

function F.relevant(actor, shell, zombie, flat, now)
    local radius = F.radius()
    if tonumber(flat) ~= nil and flat <= radius * radius then return true end
    local perception = ProjectALife.Perception
    if tonumber(flat) ~= nil and flat <= F.closingRadius ^ 2 and perception ~= nil
            and type(perception.closingSpeed) == "function" then
        local ok, speed = pcall(perception.closingSpeed, shell, zombie)
        if ok and (tonumber(speed) or 0) > 0 then return true end
    end
    local held = perception ~= nil and type(perception.attackers) == "table" and perception.attackers[actor.uid] or nil
    if type(held) == "table" and held.attacker == zombie then return true end
    local decisions = ProjectALife.DecisionLoop
    local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[actor.uid] or nil
    if type(state) == "table" and state.kind == "combat" and state.threat == zombie then return true end
    if F.targetsFriend(actor, shell, zombie, now) then return true end
    return F.atHome(actor, zombie)
end

function F.pick(find, actor, shell, mode)
    local threat, flat, kind = find(actor, shell, mode)
    if threat == nil or kind ~= "zombie" or type(actor) ~= "table" or actor.uid == nil or not F.active() then
        return threat, flat, kind
    end
    local perception = ProjectALife.Perception
    local now = Gate.nowMs()
    for _ = 1, F.maxSkips do
        if F.relevant(actor, shell, threat, flat, now) then
            F.metrics.kept = F.metrics.kept + 1
            return threat, flat, kind
        end
        F.metrics.skipped = F.metrics.skipped + 1
        perception.ignore(actor.uid, threat, F.ignoreMs)
        threat, flat, kind = find(actor, shell, mode)
        if threat == nil or kind ~= "zombie" then return threat, flat, kind end
    end
    return nil
end

return F
