require "ProjectALife/Talk/ALifeDialogueRoles"

ProjectALife = ProjectALife or {}

local Risk = {
    settings = {
        enabled = true,
        attackMemoryMs = 60000,
        temperamentCacheMs = 30000,
        pleadRadius = 15,
        pleadCooldownMs = 60000,
    },
    temperaments = {},
    attacked = {},
    pleaded = {},
    metrics = { asked = 0, refused = 0, selfDefence = 0, pleas = 0 },
}
ProjectALife.Risk = Risk

local function nowMs()
    if type(Risk.nowAdapter) == "function" then return Risk.nowAdapter() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Risk.reset()
    Risk.temperaments, Risk.attacked, Risk.pleaded = {}, {}, {}
    Risk.metrics = { asked = 0, refused = 0, selfDefence = 0, pleas = 0 }
end

local function uidOf(object)
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return nil end
    local uid = nil
    local data = object.getModData ~= nil and object:getModData() or nil
    if type(data) == "table" then uid = data.ProjectALifeUID end
    if uid == nil and object.GetVariable ~= nil then uid = object:GetVariable("ALifeUID") end
    if uid == "" then uid = nil end
    return uid
end

function Risk.keyOf(object)
    if object == nil then return nil end
    local isPlayer = type(instanceof) == "function" and instanceof(object, "IsoPlayer") == true
    if isPlayer then
        local speech = ProjectALife.Speech
        if speech ~= nil and type(speech.playerKey) == "function" then return "player:" .. tostring(speech.playerKey(object)) end
        return nil
    end
    local uid = uidOf(object)
    return uid ~= nil and ("npc:" .. tostring(uid)) or nil
end

function Risk.temperament(actor, now)
    local cached = Risk.temperaments[actor.uid]
    if cached ~= nil and now < cached.untilMs then return cached.value end
    local roles = ProjectALife.DialogueRoles
    local value = "seasoned"
    if roles ~= nil then
        local day = 0
        pcall(function() day = getGameTime():getNightsSurvived() end)
        local ok, who = pcall(roles.describe, actor, day)

        if ok and type(who) == "table" and who.temperament ~= nil and who.source ~= "fallback" then value = who.temperament end
    end
    Risk.temperaments[actor.uid] = { value = value, untilMs = now + Risk.settings.temperamentCacheMs }
    return value
end

function Risk.noteAttack(attacker, victimShell, now)
    now = now or nowMs()
    local key = Risk.keyOf(attacker)
    local uid = uidOf(victimShell)
    if key == nil or uid == nil then return false end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.read) == "function" and registry.read(tostring(uid)) or nil

    local ours = false
    pcall(function()
        local data = attacker:getModData()
        if type(data) ~= "table" or data.ProjectALifeOwned ~= true then return end
        local attackerUid = data.ProjectALifeUID
        if type(attackerUid) ~= "string" then return end
        local relations = ProjectALife.Relations
        if relations == nil or type(relations.sameSide) ~= "function" then

            ours = true
            return
        end
        local look = registry ~= nil and (registry.peek or registry.read) or nil
        local aggressor = look ~= nil and look(attackerUid) or nil
        ours = record == nil or aggressor == nil
            or relations.sameSide(record, aggressor) == true
    end)
    if ours then return false end
    local memory = record and type(record.memory) == "table" and record.memory or {}
    local group = tostring(memory.groupId or memory.outpostId or uid)
    Risk.attacked[group] = Risk.attacked[group] or {}
    Risk.attacked[group][key] = now + Risk.settings.attackMemoryMs
    local standoff = ProjectALife.Standoff
    if record ~= nil and standoff ~= nil and type(standoff.breakTruce) == "function" and string.sub(key, 1, 7) == "player:" then
        pcall(standoff.breakTruce, record, string.sub(key, 8), now)
    end
    return true
end

function Risk.decideInitiate(facts)
    local temperament = facts.temperament
    if temperament == "veteran" or temperament == "predator" then return true, "hardened" end
    if facts.attackedBy == true then return true, "self_defence" end
    if facts.grudge == true then return true, "grudge" end
    if facts.hostile == true then return true, "hostile" end
    if temperament == "fresh" then return false, "fresh" end
    return true, "doctrine"
end

local function near(a, b, reach)
    local ok, ax, ay, bx, by = pcall(function() return a:getX(), a:getY(), b:getX(), b:getY() end)
    return ok and ax ~= nil and (ax - bx) ^ 2 + (ay - by) ^ 2 <= reach * reach
end

function Risk.plead(actor, shell, target, now)
    if now < (Risk.pleaded[actor.uid] or 0) or not near(shell, target, Risk.settings.pleadRadius) then return false end
    Risk.pleaded[actor.uid] = now + Risk.settings.pleadCooldownMs
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    if talk == nil or speech == nil or type(talk.bark) ~= "function" then return false end
    local isPlayer = false
    pcall(function() isPlayer = instanceof(target, "IsoPlayer") end)
    local ok = pcall(function()
        local context = speech.contextFor(actor, isPlayer and target or nil)
        talk.bark(actor, shell, isPlayer and target or nil, "PLEAD", context)
    end)
    if ok then Risk.metrics.pleas = Risk.metrics.pleas + 1 end
    return ok
end

function Risk.mayInitiate(actor, shell, target, kind)
    if Risk.settings.enabled ~= true or type(actor) ~= "table" or target == nil then return true end
    local now = nowMs()
    Risk.metrics.asked = Risk.metrics.asked + 1
    local temperament = Risk.temperament(actor, now)
    if temperament == "veteran" or temperament == "predator" then return true end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local key = Risk.keyOf(target)
    local group = tostring(memory.groupId or memory.outpostId or actor.uid)
    local attackedBy = key ~= nil and Risk.attacked[group] ~= nil and now < (Risk.attacked[group][key] or 0)
    local grudge = false
    if kind == "player" and type(memory.hostileToPlayerKeys) == "table" and key ~= nil then
        grudge = memory.hostileToPlayerKeys[string.sub(key, 8)] == true
    elseif kind == "actor" and type(memory.hostileToActorKeys) == "table" and key ~= nil then
        grudge = memory.hostileToActorKeys[string.sub(key, 5)] == true
    end
    if kind == "actor" and ProjectALife.Perception and ProjectALife.Relations then
        local targetActor = ProjectALife.Perception.activeActorForShell(target)
        if targetActor and ProjectALife.Relations.hostile(actor, targetActor) then return true end
    end
    local relations = ProjectALife.Relations
    local hostile = kind == "player" and relations ~= nil
        and type(relations.hostileToPlayer) == "function" and relations.hostileToPlayer(actor, target) == true
    local may, reason = Risk.decideInitiate({ temperament = temperament, attackedBy = attackedBy, grudge = grudge, hostile = hostile })
    if may then
        if reason == "self_defence" then Risk.metrics.selfDefence = Risk.metrics.selfDefence + 1 end
        return true
    end
    Risk.metrics.refused = Risk.metrics.refused + 1
    Risk.plead(actor, shell, target, now)
    return false
end

return Risk
