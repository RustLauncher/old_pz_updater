ProjectALife = ProjectALife or {}

local Resistance = {
    settings = {
        sightTiles = 15,
        reachCap = 40,
        sprintTiles = 10,
        closingSpeed = 0.5,
        sprintFleeFloor = 0.35,
        shakenBonus = 0.15,
        noteMs = 1000,
        openingMs = 500,
        openingHoldMs = 1500,
        retreatScale = { predator = 0.25, veteran = 0.45, seasoned = 0.6, fresh = 1.1 },
        flinchTemperaments = { fresh = true },
    },
    counted = {},
    gaps = {},
    metrics = { enduranceRestRefusedInSight = 0, holdWhileSeen = 0, sprintHeld = 0, holdReasons = {} },
}
ProjectALife.Resistance = Resistance

function Resistance.clock()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Resistance.ask(object, method, ...)
    if object == nil then return nil end
    local query = object[method]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object, ...)
    if not ok then return nil end
    return value
end

function Resistance.configure(options)
    options = type(options) == "table" and options or {}
    local settings = Resistance.settings
    for _, name in ipairs({ "sightTiles", "reachCap", "sprintTiles", "closingSpeed", "sprintFleeFloor", "shakenBonus" }) do
        if tonumber(options[name]) ~= nil then settings[name] = tonumber(options[name]) end
    end
    return settings
end

function Resistance.reset()
    Resistance.counted, Resistance.gaps = {}, {}
    Resistance.metrics = { enduranceRestRefusedInSight = 0, holdWhileSeen = 0, sprintHeld = 0, holdReasons = {} }
    return true
end

function Resistance.forgetActor(uid)
    if uid == nil then return end
    Resistance.gaps[uid] = nil
    for _, bucket in pairs(Resistance.counted) do bucket[uid] = nil end
end

function Resistance.count(actor, name, now)
    local uid = type(actor) == "table" and actor.uid or nil
    if uid == nil then return false end
    local bucket = Resistance.counted[name]
    if bucket == nil then
        bucket = {}
        Resistance.counted[name] = bucket
    end
    if now < (bucket[uid] or -1e12) + Resistance.settings.noteMs then return false end
    bucket[uid] = now
    Resistance.metrics[name] = (Resistance.metrics[name] or 0) + 1
    return true
end

function Resistance.person(kind)
    return kind == "player" or kind == "actor" or kind == "npc"
end

function Resistance.kindOf(body)
    if body == nil then return nil end
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.peekKind) == "function" then
        local ok, kind = pcall(combat.peekKind, body)
        if ok and type(kind) == "string" then return kind end
    end
    if type(instanceof) == "function" and instanceof(body, "IsoPlayer") then return "player" end
    return "zombie"
end

function Resistance.visible(shell, threat)
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.visible) == "function" then
        local ok, seen = pcall(perception.visible, shell, threat)
        return ok and seen == true
    end
    return Resistance.ask(shell, "CanSee", threat) == true
end

function Resistance.gap(shell, threat)
    local sx, sy, sz = Resistance.ask(shell, "getX"), Resistance.ask(shell, "getY"), Resistance.ask(shell, "getZ")
    local tx, ty, tz = Resistance.ask(threat, "getX"), Resistance.ask(threat, "getY"), Resistance.ask(threat, "getZ")
    if tonumber(sx) == nil or tonumber(tx) == nil or tonumber(sy) == nil or tonumber(ty) == nil then return nil end
    return math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2), math.abs((tonumber(sz) or 0) - (tonumber(tz) or 0))
end

function Resistance.reach(shell, threat)
    local combat = ProjectALife.Combat
    if combat == nil or type(combat.weaponFor) ~= "function" or type(combat.engagementReach) ~= "function" then
        return 0
    end
    local ok, weapon = pcall(combat.weaponFor, shell)
    if not ok or weapon == nil then return 0 end
    local found, reach = pcall(combat.engagementReach, weapon, shell, threat)
    if found and tonumber(reach) ~= nil then return math.min(Resistance.settings.reachCap, reach) end
    return 0
end

function Resistance.fleeing(actor)
    local uid = type(actor) == "table" and actor.uid or nil
    if uid == nil then return false end
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear ~= nil and type(gunFear.flights) == "table" and gunFear.flights[uid] ~= nil then return true end
    local fear = ProjectALife.ModuleFear
    local record = fear ~= nil and type(fear.actors) == "table" and fear.actors[uid] or nil
    return type(record) == "table" and record.flight ~= nil
end

function Resistance.pinned(actor, shell, threat, kind, now)
    if Resistance.fleeing(actor) then return false end
    if threat == nil or shell == nil or not Resistance.person(kind) then return false end
    if Resistance.ask(threat, "isDead") == true then return false end
    local gap, rise = Resistance.gap(shell, threat)
    if gap == nil or rise >= 1 then return false end
    if gap > math.max(Resistance.settings.sightTiles, Resistance.reach(shell, threat)) then return false end
    return Resistance.visible(shell, threat)
end

function Resistance.tired(actor, shell, threat, kind, now, exhausted)
    if exhausted ~= true then return false end
    now = tonumber(now) or Resistance.clock()
    if Resistance.pinned(actor, shell, threat, kind, now) then
        Resistance.count(actor, "enduranceRestRefusedInSight", now)
        return false
    end
    return true
end

function Resistance.restRefused(actor, shell, threat, kind, now)
    now = tonumber(now) or Resistance.clock()
    if not Resistance.pinned(actor, shell, threat, kind, now) then return false end
    Resistance.count(actor, "enduranceRestRefusedInSight", now)
    return true
end

function Resistance.noteHold(actor, shell, threat, kind, choice, reason, now)
    if choice ~= "watch" and choice ~= "bypass" then return false end
    now = tonumber(now) or Resistance.clock()
    if not Resistance.pinned(actor, shell, threat, kind, now) then return false end
    if not Resistance.count(actor, "holdWhileSeen", now) then return true end
    local reasons = Resistance.metrics.holdReasons
    local key = tostring(reason or choice)
    reasons[key] = (reasons[key] or 0) + 1
    return true
end

function Resistance.temperament(actor, now)
    local risk = ProjectALife.Risk
    if risk == nil or type(risk.temperament) ~= "function" or type(actor) ~= "table" or actor.uid == nil then
        return "seasoned"
    end
    local ok, value = pcall(risk.temperament, actor, now)
    if ok and type(value) == "string" then return value end
    return "seasoned"
end

function Resistance.shaken(actor, shell, now)
    local survival = ProjectALife.Survival
    if survival == nil or type(survival.recentLoss) ~= "function" then return false end
    local ok, shaken = pcall(survival.recentLoss, actor, shell, now)
    return ok and shaken == true
end

function Resistance.retreatHealthFor(actor, shell, now, base)
    base = tonumber(base) or 0.35
    now = tonumber(now) or Resistance.clock()
    local scale = Resistance.settings.retreatScale[Resistance.temperament(actor, now)] or 1
    local limit = base * scale
    if Resistance.shaken(actor, shell, now) then limit = limit + Resistance.settings.shakenBonus end
    return math.max(0.02, math.min(0.8, limit))
end

function Resistance.mayFlinch(actor, now)
    return Resistance.settings.flinchTemperaments[Resistance.temperament(actor, tonumber(now) or Resistance.clock())] == true
end

function Resistance.escaping(actor, target, gap, now)
    local uid = type(actor) == "table" and actor.uid or nil
    if uid == nil or tonumber(gap) == nil then return false end
    local settings = Resistance.settings
    local last = Resistance.gaps[uid]
    if last == nil then
        Resistance.gaps[uid] = { gap = gap, atMs = now, escapingUntilMs = 0 }
        return false
    end
    if now < last.atMs then
        last.gap, last.atMs = gap, now
        return false
    end
    if now - last.atMs >= settings.openingMs then
        local rate = (gap - last.gap) / ((now - last.atMs) / 1000)
        local runs = Resistance.ask(target, "isRunning") == true or Resistance.ask(target, "isSprinting") == true
        if runs and rate >= -settings.closingSpeed then last.escapingUntilMs = now + settings.openingHoldMs end
        last.gap, last.atMs = gap, now
    end
    return now < last.escapingUntilMs
end

function Resistance.mayBurst(actor, shell, target, distance, now)
    local settings = Resistance.settings
    now = tonumber(now) or Resistance.clock()
    distance = tonumber(distance) or 0
    if distance <= settings.sprintTiles or Resistance.fleeing(actor) then return true end
    if not Resistance.person(Resistance.kindOf(target)) then return true end
    if Resistance.escaping(actor, target, distance, now) then
        local endurance = ProjectALife.Endurance
        if endurance == nil or type(endurance.value) ~= "function" or type(endurance.settings) ~= "table" then
            return true
        end
        local maximum = math.max(1, tonumber(endurance.settings.maximum) or 100)
        return endurance.value(actor, shell, now) / maximum >= settings.sprintFleeFloor
    end
    Resistance.count(actor, "sprintHeld", now)
    return false
end

function Resistance.crewPresses(actor, contact)
    if type(actor) ~= "table" or type(contact) ~= "table" or contact.kind ~= "player" then return false end
    local relations = ProjectALife.Relations
    if contact.target ~= nil and relations ~= nil and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, actor, contact.target)
        if ok and stance == "hostile" then return true end
    end
    local discretion = ProjectALife.Discretion
    if discretion ~= nil and type(discretion.attacker) == "function" then
        local ok, attacker = pcall(discretion.attacker, actor)
        if ok and attacker == true then return true end
    end
    return false
end

return Resistance
