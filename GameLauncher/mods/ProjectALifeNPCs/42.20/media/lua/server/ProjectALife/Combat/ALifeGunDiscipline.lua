require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local D = {
    id = "gun_discipline",
    moduleId = "weaponSwitchMelee",
    contactTiles = 2, closeTiles = 8, hordeTiles = 12, noiseTiles = 25, allyTiles = 8,
    lowHealth = 0.4, allyHealth = 60, stickyMs = 3000, memoMs = 500, rollMs = 30000,
    avoidMs = 45000, episodeGapMs = 8000, resumeAfterMs = 1000,
    cache = {}, avoids = {}, cacheCount = 0, cacheCap = 256, weak = { __mode = "v" },
    metrics = { held = 0, fired = 0, avoided = 0, avoidResumed = 0, swapped = 0, rolls = 0, rollsPassed = 0, reasons = {} },
}
ProjectALife.GunDiscipline = D

function D.percent()
    local value = Gate.number("Combat_GunsVsZombiesPercent", 50, 0, 100)
    if value == 15 then return 50 end
    return value
end

function D.noiseLimit()
    return Gate.number("Combat_GunNoiseZombies", 8, 0, 40)
end

function D.hordeSize()
    return Gate.number("Combat_GunHordeSize", 5, 2, 30)
end

function D.active()
    return D.percent() < 100
end

function D.switchOn(actor)
    local registry = ProjectALife.ModuleRegistry
    if registry == nil or type(registry.allows) ~= "function" or type(actor) ~= "table"
            or type(registry.modules) ~= "table" or registry.modules[D.moduleId] == nil then return true end
    return registry.allows(actor, D.moduleId) == true
end

function D.nowMs()
    return Gate.nowMs()
end

function D.keyOf(actor, shell)
    if type(actor) == "table" and type(actor.uid) == "string" then return actor.uid end
    return tostring(shell)
end

function D.rows(now)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.bodies) ~= "function" then return {} end
    local ok, rows = pcall(caution.bodies, now)
    if not ok or type(rows) ~= "table" then return {} end
    return rows
end

function D.tally(shell, now)
    local result = { contact = 0, close = 0, horde = 0, noise = 0 }
    local sx, sy, sz
    if shell ~= nil and type(shell.getX) == "function" and type(shell.getY) == "function"
            and type(shell.getZ) == "function" then
        sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
    end
    if sx == nil then return result end
    local rows = D.rows(now)
    local contact2, close2 = D.contactTiles ^ 2, D.closeTiles ^ 2
    local horde2, noise2 = D.hordeTiles ^ 2, D.noiseTiles ^ 2
    for index = 1, #rows do
        local row = rows[index]
        if math.abs((row.z or sz) - sz) < 1.5 then
            local d2 = (row.x - sx) ^ 2 + (row.y - sy) ^ 2
            if d2 <= noise2 then result.noise = result.noise + 1 end
            if d2 <= horde2 then result.horde = result.horde + 1 end
            if d2 <= close2 then result.close = result.close + 1 end
            if d2 <= contact2 then result.contact = result.contact + 1 end
        end
    end
    return result
end

function D.meleeOf(shell)
    local weapons = ProjectALife.Weapons
    if weapons == nil or type(weapons.bestMelee) ~= "function" then return nil end
    return weapons.bestMelee(shell)
end

function D.healthOf(actor, shell)
    local survival = ProjectALife.Survival
    if survival == nil or type(survival.healthRatio) ~= "function" then return 1 end
    local ok, ratio = pcall(survival.healthRatio, actor, shell)
    if not ok then return 1 end
    return tonumber(ratio) or 1
end

function D.stateDuty(actor)
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    if type(actor) ~= "table" or catalog == nil or rules == nil or type(catalog.faction) ~= "function"
            or type(rules.blocOf) ~= "function" then return false end
    local ok, bloc = pcall(function() return rules.blocOf(catalog.faction(actor.factionId)) end)
    return ok and (bloc == "military" or bloc == "law")
end

function D.playerHurt(player)
    if player == nil or type(player.getBodyDamage) ~= "function" then return false end
    local ok, hurt = pcall(function()
        if type(player.isDead) == "function" and player:isDead() == true then return false end
        local body = player:getBodyDamage()
        if body == nil or type(body.getHealth) ~= "function" then return false end
        return (tonumber(body:getHealth()) or 100) < D.allyHealth
    end)
    return ok and hurt == true
end

function D.allyDown(actor, shell)
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" or shell == nil or type(shell.getX) ~= "function" then
        return false
    end
    local relations = ProjectALife.Relations
    local sx, sy = shell:getX(), shell:getY()
    local reach = D.allyTiles ^ 2
    for _, player in ipairs(locator.list()) do
        if type(player.getX) == "function" and type(player.getY) == "function"
                and (player:getX() - sx) ^ 2 + (player:getY() - sy) ^ 2 <= reach and D.playerHurt(player) then
            local stance = "neutral"
            if relations ~= nil and type(relations.playerStance) == "function" then
                local ok, value = pcall(relations.playerStance, actor, player)
                if ok and value ~= nil then stance = value end
            end
            if stance ~= "hostile" then return true end
        end
    end
    return false
end

function D.entryFor(uid, target)
    if D.cache[uid] == nil then
        D.cacheCount = D.cacheCount + 1
        if D.cacheCount > D.cacheCap then D.cache, D.cacheCount = {}, 1 end
    end
    local entry = setmetatable({ target = target }, D.weak)
    D.cache[uid] = entry
    return entry
end

function D.roll(uid, target, now)
    local entry = D.cache[uid]
    if entry ~= nil and entry.target == target and entry.rollValue ~= nil and now < (entry.rollUntil or 0) then
        return entry.rollValue
    end
    local percent = D.percent()
    local passed = false
    if type(ZombRand) == "function" and percent > 0 then passed = ZombRand(100) < percent end
    D.metrics.rolls = D.metrics.rolls + 1
    if passed then D.metrics.rollsPassed = D.metrics.rollsPassed + 1 end
    if entry == nil or entry.target ~= target then entry = D.entryFor(uid, target) end
    entry.rollValue, entry.rollUntil = passed, now + D.rollMs
    return passed
end

function D.judge(actor, shell, target, facts, now)
    facts = type(facts) == "table" and facts or {}
    local tally = D.tally(shell, now)
    local armed = D.meleeOf(shell) ~= nil
    if tally.contact >= 2 then return true, "cornered" end
    if facts.immediateDanger == true and not armed then return true, "no_melee" end
    if tally.close > 0 and D.healthOf(actor, shell) <= D.lowHealth then return true, "low_health" end
    if tally.close > 0 and D.allyDown(actor, shell) then return true, "ally_down" end
    if D.percent() <= 0 then return false, "never" end
    local limit = D.noiseLimit()
    if limit > 0 and tally.noise > limit then return false, "noise" end
    if facts.routeBlocked == true and tally.horde >= D.hordeSize() then return true, "horde_block" end
    if facts.mission == "rescue" then return true, "rescue_order" end
    if D.stateDuty(actor) and (facts.mission == "combat"
            or (facts.mission == "guard" and facts.inTerritory == true)) then
        return true, "post_duty"
    end
    if D.roll(D.keyOf(actor, shell), target, now) then return true, "roll" end
    return false, "discipline"
end

function D.decide(actor, shell, target, facts, now)
    if not D.active() then return true, "off" end
    if not D.switchOn(actor) then return true, "module_off" end
    local caution = ProjectALife.Caution
    if caution ~= nil and type(caution.zombieMode) == "function" and caution.zombieMode(actor) == "fight" then
        return true, "fight_mode"
    end
    now = tonumber(now) or D.nowMs()
    local uid = D.keyOf(actor, shell)
    local entry = D.cache[uid]
    if entry ~= nil and entry.target == target then
        if entry.allowUntil ~= nil and now < entry.allowUntil then return true, entry.allowReason end
        if entry.memoUntil ~= nil and now < entry.memoUntil then return entry.memoAllow, entry.memoReason end
    end
    local allow, reason = D.judge(actor, shell, target, facts, now)
    entry = D.cache[uid]
    if entry == nil or entry.target ~= target then entry = D.entryFor(uid, target) end
    entry.memoAllow, entry.memoReason, entry.memoUntil = allow, reason, now + D.memoMs
    if allow and reason ~= "roll" and reason ~= "off" then
        entry.allowUntil, entry.allowReason = now + D.stickyMs, reason
    else
        entry.allowUntil, entry.allowReason = nil, nil
    end
    return allow, reason
end

function D.zombieFacts(actor, shell, target, now)
    local combat = ProjectALife.Combat
    if combat == nil or type(combat.currentEngagementFacts) ~= "function" or type(actor) ~= "table" then return nil end
    local ok, facts = pcall(combat.currentEngagementFacts, actor, shell, target, now)
    if ok then return facts end
    return nil
end

function D.isZombie(target)
    local combat = ProjectALife.Combat
    return target ~= nil and combat ~= nil and type(combat.kindOf) == "function" and combat.kindOf(target) == "zombie"
end

function D.holds(actor, shell, target, facts, now)
    if not D.active() or not D.isZombie(target) then return false end
    now = tonumber(now) or D.nowMs()
    local allow = D.decide(actor, shell, target, facts or D.zombieFacts(actor, shell, target, now), now)
    return allow ~= true
end

function D.count(reason)
    local reasons = D.metrics.reasons
    reasons[reason] = (reasons[reason] or 0) + 1
end

function D.refuses(actor, shell, target)
    if not D.active() or not D.isZombie(target) then return false end
    local now = D.nowMs()
    local facts = D.zombieFacts(actor, shell, target, now)
    local allow, reason = D.decide(actor, shell, target, facts, now)
    if allow then
        D.metrics.fired = D.metrics.fired + 1
        D.count(reason)
        return false
    end
    if D.meleeOf(shell) == nil then
        D.metrics.fired = D.metrics.fired + 1
        D.count("no_melee_engaged")
        return false
    end
    D.metrics.held = D.metrics.held + 1
    D.count("held_" .. tostring(reason))
    return true
end

function D.disarm(actor, shell, target, aim, now)
    if not D.holds(actor, shell, target, nil, now) then return false end
    local melee = D.meleeOf(shell)
    local weapons, animations = ProjectALife.Weapons, ProjectALife.Animations
    if melee == nil or weapons == nil or type(weapons.select) ~= "function" then return false end
    local slot = type(weapons.slot) == "function" and weapons.slot(melee) or nil
    if not weapons.select(shell, melee, slot or "melee") then return false end
    if type(aim) == "table" then
        aim.racked = true
        aim.readyAtMs = nil
        aim.weaponSwitchAtMs = now + 10000
    end
    if animations ~= nil then
        if type(animations.clear) == "function" then pcall(animations.clear, shell) end
        if type(animations.setCombatHold) == "function" then pcall(animations.setCombatHold, shell, false) end
    end
    D.metrics.swapped = D.metrics.swapped + 1
    return true
end

function D.beginCombat(actor, shell, target)
    if not D.active() or not D.isZombie(target) then return false end
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.weaponIsHeld) ~= "function" or animations.weaponIsHeld(shell) then
        return false
    end
    local now = D.nowMs()
    if not D.holds(actor, shell, target, nil, now) then return false end
    local melee = D.meleeOf(shell)
    local weapons = ProjectALife.Weapons
    if melee == nil or weapons == nil or type(weapons.current) ~= "function" or weapons.current(shell) == melee then
        return false
    end
    local slot = type(weapons.slot) == "function" and weapons.slot(melee) or nil
    if not weapons.select(shell, melee, slot or "melee") then return false end
    D.metrics.swapped = D.metrics.swapped + 1
    return true
end

function D.engagement(actor, shell, threat, facts, choice, reason, now)
    if choice ~= "commit" or not D.active() or not D.isZombie(threat) then return choice, reason end
    now = tonumber(now) or D.nowMs()
    local allow = D.decide(actor, shell, threat, facts, now)
    if allow or D.meleeOf(shell) ~= nil then return choice, reason end
    D.noteAvoid(actor, now)
    D.metrics.avoided = D.metrics.avoided + 1
    return "bypass", "gun_discipline"
end

function D.noteAvoid(actor, now)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then return false end
    now = tonumber(now) or D.nowMs()
    local mark = D.avoids[actor.uid]
    if mark ~= nil and now >= mark.lastMs and now - mark.lastMs <= D.episodeGapMs then
        mark.lastMs = now
        return false
    end
    D.avoids[actor.uid] = { atMs = now, lastMs = now, counted = false }
    return true
end

function D.noteMoving(actor, now)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then return false end
    local mark = D.avoids[actor.uid]
    if mark == nil or mark.counted == true then return false end
    now = tonumber(now) or D.nowMs()
    if now - mark.lastMs > D.avoidMs then
        D.avoids[actor.uid] = nil
        return false
    end
    if now - mark.atMs < D.resumeAfterMs then return false end
    mark.counted = true
    D.metrics.avoidResumed = D.metrics.avoidResumed + 1
    return true
end

function D.forget(uid)
    D.cache[uid] = nil
    D.avoids[uid] = nil
end

function D.reset()
    D.cache, D.avoids, D.cacheCount = {}, {}, 0
    D.metrics = { held = 0, fired = 0, avoided = 0, avoidResumed = 0, swapped = 0, rolls = 0, rollsPassed = 0, reasons = {} }
end

function D.qaLine()
    local m = D.metrics
    local parts = {}
    for reason, count in pairs(m.reasons) do parts[#parts + 1] = reason .. "=" .. tostring(count) end
    table.sort(parts)
    return "[ALIFE-QA] gunDiscipline percent=" .. tostring(D.percent()) .. " gunsVsZombiesHeld=" .. tostring(m.held)
        .. " gunsVsZombiesFired=" .. tostring(m.fired) .. " avoided=" .. tostring(m.avoided)
        .. " avoidResumed=" .. tostring(m.avoidResumed) .. " swapped=" .. tostring(m.swapped)
        .. " rolls=" .. tostring(m.rollsPassed) .. "/" .. tostring(m.rolls)
        .. " why=" .. (#parts > 0 and table.concat(parts, ",") or "none")
end

ProjectALife.ModuleRegistry.register({
    id = "weaponSwitchMelee",
    kind = "craft",
    label = "Switch to melee against zombies",
    summary = "On: a gun user may keep the gun stowed and use a melee weapon, shove or walk past zombies (the Combat Expert gun discipline). Off: the NPC uses the weapon it holds.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

return D
