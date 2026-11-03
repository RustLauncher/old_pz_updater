require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local D = {
    id = "discretion",
    zombieRadius = 25, crewRadius = 20, cacheMs = 3000, scanCap = 600, sightChecks = 40, closeRadius = 3,
    gunScore = 8, carriedScore = 5, meleeScore = 3, unarmedScore = 1,
    lowAmmoCost = 0.35, loudCost = 0.6, oddsWeight = 0.4, oddsMin = -0.6, oddsMax = 0.4,
    commitMs = 120000, pruneMs = 60000, nextPruneMs = 0, logMs = 30000,
    factionAggression = { hostile = 0.7, careful = 0.35, neutral = 0.25, friendly = 0.15, allied = 0.1 },
    temper = { predator = 0.3, veteran = 0.15, seasoned = 0, fresh = -0.15 },
    near = { { 8, 0.35 }, { 15, 0.15 } },
    loudBy = { default = 15, hardened = 30 },
    attackEncounters = { raid = true, fullscale_raid = true, assassination = true },
    huntIntents = { hunt_nearby = true, manhunt_player = true, assault_player = true, full_raid = true },
    attackModes = { hunt = true, manhunt = true, assault = true, full_raid = true },
    cache = {}, waiting = {}, committed = {}, zombieCache = {}, logged = {},
    metrics = { weighed = 0, held = 0, fought = 0, lowAmmo = 0, tooLoud = 0, outgunned = 0, patience = 0, attackers = 0 },
}
ProjectALife.Discretion = D

function D.active()
    return Gate.on(D.id, "Discretion_Enabled", true)
end

function D.fightAt()
    return Gate.number("Discretion_FightPercent", 50, 0, 100) / 100
end

function D.lowAmmo()
    return Gate.number("Discretion_LowAmmoRounds", 6, 0, 30)
end

function D.patienceMs()
    return Gate.number("Discretion_PatienceSeconds", 45, 10, 600) * 1000
end

function D.ask(object, method, ...)
    if object == nil then return nil end
    local query = object[method]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object, ...)
    if not ok then return nil end
    return value
end

function D.xy(body)
    local x, y = D.ask(body, "getX"), D.ask(body, "getY")
    if tonumber(x) == nil or tonumber(y) == nil then return nil end
    return x, y
end

function D.within(body, cx, cy, r2)
    local x, y = D.xy(body)
    return x ~= nil and (x - cx) ^ 2 + (y - cy) ^ 2 <= r2
end

function D.isNpc(body)
    return Gate.uidOf(body) ~= nil
end

function D.rounds(shell)
    local item = D.ask(shell, "getPrimaryHandItem")
    if D.ask(item, "isRanged") ~= true then return nil end
    local magazines = ProjectALife.MagazineState
    local loaded = 0
    if magazines ~= nil then
        if type(magazines.isInfinite) == "function" and magazines.isInfinite(shell) == true then return 999 end
        if type(magazines.current) == "function" then
            local ok, count = pcall(magazines.current, item)
            loaded = ok and tonumber(count) or 0
        end
    end
    local reserve = 0
    if type(shell.hasModData) == "function" and shell:hasModData() == true then
        local data = shell:getModData()
        reserve = type(data) == "table" and tonumber(data.ProjectALifePrimaryAmmoUnits) or 0
    end
    return loaded + reserve
end

function D.carriesGun(character)
    local attached = D.ask(character, "getAttachedItems")
    local size = tonumber(D.ask(attached, "size")) or 0
    for i = 0, size - 1 do
        local item = D.ask(D.ask(attached, "get", i), "getItem")
        if D.ask(item, "isRanged") == true then return true end
    end
    return false
end

function D.firepower(character)
    local item = D.ask(character, "getPrimaryHandItem")
    if D.ask(item, "isRanged") ~= true then
        if D.carriesGun(character) then return D.carriedScore end
        if item ~= nil and D.ask(item, "getFullType") ~= "Base.BareHands" then return D.meleeScore end
        return D.unarmedScore
    end
    if D.isNpc(character) then
        local rounds = D.rounds(character)
        if rounds ~= nil and rounds < D.lowAmmo() then return D.meleeScore end
    end
    return D.gunScore
end

function D.countZombies(x, y, viewer)
    local cell = type(getCell) == "function" and getCell() or nil
    local list = D.ask(cell, "getZombieList")
    local size = tonumber(D.ask(list, "size")) or 0
    local r2, close2 = D.zombieRadius ^ 2, D.closeRadius ^ 2
    local sight = viewer ~= nil and type(viewer.CanSee) == "function"
    local count, checks = 0, 0
    for i = 0, math.min(size, D.scanCap) - 1 do
        local zed = list:get(i)
        local zx, zy = D.xy(zed)
        if zx ~= nil and zed ~= viewer then
            local d2 = (zx - x) ^ 2 + (zy - y) ^ 2
            if d2 <= r2 and not D.isNpc(zed) then
                if not sight or d2 <= close2 then
                    count = count + 1
                elseif checks < D.sightChecks then
                    checks = checks + 1
                    if D.ask(viewer, "CanSee", zed) == true then count = count + 1 end
                end
            end
        end
    end
    return count
end

function D.zombiesNear(x, y, uid, viewer, now)
    local hit = D.zombieCache[uid]
    if hit ~= nil and now < hit.untilMs then return hit.count end
    local count = D.countZombies(x, y, viewer)
    D.zombieCache[uid] = { count = count, untilMs = now + D.cacheMs }
    return count
end

function D.sides(actor, shell, player)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local ours, theirs = D.firepower(shell), D.firepower(player)
    local cx, cy = D.xy(shell)
    local px, py = D.xy(player)
    local r2 = D.crewRadius ^ 2
    local decisions = ProjectALife.DecisionLoop
    local orders = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders or {}
    for _, uid in ipairs(Gate.aiUids()) do
        local record = uid ~= actor.uid and Gate.recordOf(uid) or nil
        local other = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
        local body = other ~= nil and Gate.shellOf(uid) or nil
        if body ~= nil and record.lifecycle ~= "dead" then
            local crew = (memory.groupId ~= nil and other.groupId == memory.groupId)
                or (memory.outpostId ~= nil and other.outpostId == memory.outpostId)
            local order = orders[uid]
            local escort = type(order) == "table" and order.kind == "follow" and order.player == player
            if crew and cx ~= nil and D.within(body, cx, cy, r2) then
                ours = ours + D.firepower(body)
            elseif escort and px ~= nil and D.within(body, px, py, r2) then
                theirs = theirs + D.firepower(body)
            end
        end
    end
    if px ~= nil then
        for _, other in ipairs(Gate.players()) do
            if other ~= player and D.within(other, px, py, r2) then theirs = theirs + D.firepower(other) end
        end
    end
    return ours, theirs
end

function D.temperamentOf(actor, now)
    local risk = ProjectALife.Risk
    if risk ~= nil and type(risk.temperament) == "function" then
        local ok, value = pcall(risk.temperament, actor, now)
        if ok and type(value) == "string" then return value end
    end
    return "seasoned"
end

function D.aggression(actor, now)
    local reputation = ProjectALife.Reputation
    local baseline
    if reputation ~= nil and type(reputation.escalationBaseline) == "function" then
        local ok, value = pcall(reputation.escalationBaseline, actor)
        if ok then baseline = value end
    end
    local temperament = D.temperamentOf(actor, now)
    return (D.factionAggression[baseline] or D.factionAggression.careful) + (D.temper[temperament] or 0), temperament
end

function D.score(actor, shell, player, now)
    local parts = {}
    local aggression, temperament = D.aggression(actor, now)
    parts.aggression, parts.temperament = aggression, temperament
    local hardened = temperament == "veteran" or temperament == "predator"
    local ours, theirs = D.sides(actor, shell, player)
    local ratio = ours / math.max(0.5, theirs)
    parts.ratio = ratio
    parts.odds = math.max(D.oddsMin, math.min(D.oddsMax, (ratio - 1) * D.oddsWeight))
    local x, y = D.xy(shell)
    local tx, ty = D.xy(player)
    local distance = (x ~= nil and tx ~= nil) and math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2) or math.huge
    parts.distance = distance
    for _, band in ipairs(D.near) do
        if distance <= band[1] then parts.near = band[2] break end
    end
    local rounds = D.rounds(shell)
    if rounds ~= nil and rounds < D.lowAmmo() and D.firepower(player) >= D.gunScore then
        parts.lowAmmo = -D.lowAmmoCost
        D.metrics.lowAmmo = D.metrics.lowAmmo + 1
    end
    local loud = hardened and D.loudBy.hardened or D.loudBy.default
    if x ~= nil and rounds ~= nil and D.zombiesNear(x, y, actor.uid, shell, now) >= loud then
        parts.loud = -D.loudCost
        D.metrics.tooLoud = D.metrics.tooLoud + 1
    end
    if ratio < (hardened and 0.5 or 0.8) then D.metrics.outgunned = D.metrics.outgunned + 1 end
    parts.total = aggression + parts.odds + (parts.near or 0) + (parts.lowAmmo or 0) + (parts.loud or 0)
    return parts.total, parts
end

function D.attacker(actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local encounter = string.lower(tostring(memory.encounter or memory.encounterKind or ""))
    if D.attackEncounters[encounter] then return true end
    if memory.hostileOverride == true or D.huntIntents[actor.intent] then return true end
    local programs, catalog = ProjectALife.Programs, ProjectALife.Catalog
    if programs ~= nil and type(programs.mode) == "function" and catalog ~= nil and type(catalog.faction) == "function" then
        local faction = catalog.faction(actor.factionId)
        local program = type(faction) == "table" and type(faction.spawn) == "table"
            and string.lower(tostring(faction.spawn.program or "patrol")) or "patrol"
        local ok, mode = pcall(programs.mode, actor, program)
        if ok and D.attackModes[mode] then return true end
    end
    return false
end

function D.provoked(actor, player, key, now)
    local fair = ProjectALife.Fairness
    if fair == nil then return false end
    if type(fair.adminHostile) == "function" and fair.adminHostile(actor) then return true end
    if type(fair.grudge) == "function" and fair.grudge(actor, key) then return true end
    return type(fair.underAttack) == "function" and fair.underAttack(actor, player, now) == true
end

function D.fighting(actor)
    local decisions = ProjectALife.DecisionLoop
    local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[actor.uid] or nil
    return type(state) == "table" and state.kind == "combat"
end

function D.standoffHolds(actor, player, now)
    local standoff = ProjectALife.Standoff
    if standoff == nil or type(standoff.holdsFor) ~= "function" or type(standoff.keyOf) ~= "function" then return false end
    return standoff.holdsFor(actor.memory, standoff.keyOf(player), now) == true
end

function D.prune(now)
    if now < D.nextPruneMs then return end
    D.nextPruneMs = now + D.pruneMs
    for key, hit in pairs(D.cache) do
        if now >= hit.untilMs then D.cache[key] = nil end
    end
    for key, entry in pairs(D.waiting) do
        if now - entry.seenMs > D.pruneMs then D.waiting[key] = nil end
    end
    for key, untilMs in pairs(D.committed) do
        if now >= untilMs then D.committed[key] = nil end
    end
    for key, hit in pairs(D.zombieCache) do
        if now >= hit.untilMs then D.zombieCache[key] = nil end
    end
    for key, untilMs in pairs(D.logged) do
        if now >= untilMs then D.logged[key] = nil end
    end
end

function D.note(actor, key, parts, why, now)
    local id = tostring(actor.uid) .. ">" .. tostring(key)
    if now < (D.logged[id] or 0) then return end
    D.logged[id] = now + D.logMs
    print(string.format("[A-Life] discretion: %s %s player at %.0f tiles: score %.2f (aggression %+.2f %s, odds %+.2f %.1f:1, close %+.2f, ammo %+.2f, zombies %+.2f) -> %s",
        tostring(actor.uid), "vs", math.min(999, parts.distance or 999), parts.total or 0, parts.aggression or 0,
        tostring(parts.temperament), parts.odds or 0, parts.ratio or 0, parts.near or 0, parts.lowAmmo or 0, parts.loud or 0,
        why or "fight"))
end

function D.holdOff(actor, shell, player, now)
    if type(actor) ~= "table" or actor.uid == nil or shell == nil or player == nil or not D.active() then return nil end
    now = tonumber(now) or Gate.nowMs()
    D.prune(now)
    local key = ProjectALife.Fairness ~= nil and type(ProjectALife.Fairness.keyOf) == "function"
        and ProjectALife.Fairness.keyOf(player) or nil
    if key == nil or D.provoked(actor, player, key, now) or D.fighting(actor) or D.standoffHolds(actor, player, now) then
        return nil
    end
    if D.attacker(actor) then
        D.metrics.attackers = D.metrics.attackers + 1
        return nil
    end
    local id = actor.uid .. ">" .. key
    local hit = D.cache[id]
    if hit ~= nil and now < hit.untilMs then return hit.why end
    if now < (D.committed[id] or 0) then return nil end
    D.metrics.weighed = D.metrics.weighed + 1
    local total, parts = D.score(actor, shell, player, now)
    local why = nil
    if total >= D.fightAt() then
        D.waiting[id] = nil
        D.committed[id] = now + D.commitMs
        D.metrics.fought = D.metrics.fought + 1
    else
        why = parts.loud and "too_loud" or parts.lowAmmo and "low_ammo" or "odds"
        local entry = D.waiting[id]
        if entry == nil then
            entry = { sinceMs = now, seenMs = now }
            D.waiting[id] = entry
        end
        entry.seenMs = now
        if why == "odds" and now - entry.sinceMs >= D.patienceMs() then
            D.waiting[id] = nil
            D.committed[id] = now + D.commitMs
            D.metrics.patience = D.metrics.patience + 1
            why = nil
        else
            D.metrics.held = D.metrics.held + 1
        end
    end
    D.cache[id] = { why = why, untilMs = now + D.cacheMs }
    D.note(actor, key, parts, why, now)
    return why
end

return D
