require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Combat/ALifeBlood"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Health = {
    settings = {

        bleedFraction = 0.10,

        bleedOutMs = 10000,

        legChance = 55,

        bodyLimbPercent = 35,

        limpWithWeapon = true,

        bandageMs = 4200,

        healToFraction = 0.65,

        regenPerHour = 0.015,
        regenQuietMs = 20000,
        regenMaxHours = 24,

        sheetsMs = 5600,
        sheetsHealToFraction = 0.5,

        fireZombieHealth = 1.8,
        fireUnitsPerSecond = 48,
        fireStepMaxMs = 1000,
    },

    lastAttacker = setmetatable({}, { __mode = "kv" }),
    metrics = { wounds = 0, legWounds = 0, bleedOuts = 0, healed = 0, downed = 0,
        stains = 0, burned = 0, burnKills = 0, turned = 0 },
}
ProjectALife.Health = Health

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Health.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Health.settings[key] ~= nil and tonumber(value) ~= nil then
            Health.settings[key] = tonumber(value)
        end
    end
    if options.enabled ~= nil then Health.enabled = options.enabled ~= false end
    return true
end

Health.enabled = true

function Health.holdOwner(shell, treated)
    local data = shell:getModData()
    data.ProjectALifeHealthRevision = (tonumber(data.ProjectALifeHealthRevision) or 0) + 1
    data.ProjectALifeHealthPendingUntilMs = nowMs() + 3000
    data.ProjectALifeHealthAck = nil
    data.ProjectALifeTreatmentRevision = data.ProjectALifeHealthRevision
    data.ProjectALifeTreatmentGeneration = data.ProjectALifeGeneration
    data.ProjectALifeTreatmentTreated = treated == true or nil
    return data
end

function Health.syncOwner(shell, injuryState)
    local executor = ProjectALife.Executor
    if type(isServer) ~= "function" or not isServer() or executor == nil
            or not executor.serverDelegates() then return false end
    local data = Health.holdOwner(shell, true)
    return executor.pushHealth(shell, data.ProjectALifeUID, data.ProjectALifeGeneration,
        nil, nil, nil, nil, false, injuryState, true)
end

function Health.invulnerable(shell, suppliedData)
    if shell == nil then return false end
    local data = suppliedData
    if type(data) ~= "table" and shell.getModData ~= nil then
        data = shell:getModData()
    end
    return type(data) == "table" and data.ProjectALifeInvulnerable == true
end

function Health.pin(shell, suppliedData)
    if shell == nil then return false end
    local pinned = false
    pcall(function()
        local data = type(suppliedData) == "table" and suppliedData or shell:getModData()
        if type(data) ~= "table" or data.ProjectALifeInvulnerable ~= true then return end
        data.ProjectALifeWoundLeg = nil
        data.ProjectALifeBleedOutAtMs = nil
        data.ProjectALifeDownedUntilMs = nil
        data.ProjectALifeWounds = nil
        data.ProjectALifeHealDoneAtMs = nil
        local value = ProjectALife.ShellSimulation.maximumFor(shell)
        if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.setHealth(shell, value)
        else shell:setHealth(value) end
        pinned = true
    end)
    return pinned
end

Health.bloodZones = {
    head = { "Head", "Neck" },
    torso = { "Torso_Upper", "Torso_Lower" },
    body = { "Torso_Upper", "Torso_Lower" },
    limb = { "UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R" },
}

function Health.stain(target, zone)
    if target == nil then return false end
    local painted = 0
    pcall(function()
        if target.addBlood == nil then return end
        local names = Health.bloodZones[tostring(zone)] or Health.bloodZones.torso

        local first = 1
        if #names > 2 then first = 1 + 2 * roll(2) end
        for index = first, first + 1 do
            local part
            if BloodBodyPartType ~= nil then part = BloodBodyPartType[names[index]] end
            if part ~= nil then
                target:addBlood(part, true, true, false)
                painted = painted + 1
            end
        end
        if painted > 0 then return end
        target:addBlood(nil, false, true, false)
    end)
    if painted > 0 then Health.metrics.stains = Health.metrics.stains + 1 end
    return painted > 0
end

function Health.onDamage(attacker, target, zone, remaining, maximum, now, forgiven, weapon, blocked)
    if Health.enabled ~= true or target == nil then return end
    if Health.invulnerable(target) then return Health.pin(target) end
    now = tonumber(now) or nowMs()
    local attack = ProjectALife.Wounds.attackKind(attacker, weapon)
    if blocked ~= true then
        Health.recordWound(attacker, target, zone, remaining, maximum, now, attack)
        Health.stain(target, zone)
        local blood = ProjectALife.Blood
        if blood ~= nil then pcall(blood.onHit, attacker, target, zone, remaining, maximum, now, weapon, attack) end
    end
    if blocked ~= true and tonumber(remaining) ~= nil and remaining > 0 then
        local playerHit = attacker ~= nil and type(instanceof) == "function" and instanceof(attacker, "IsoPlayer")
        if not playerHit then ProjectALife.Speech.combatBark(target, "HURT", attack, now) end
    end
    Health.afterWound(attacker, target, now, forgiven, attack)
end

function Health.startBleedOut(target, data, now)
    if data.ProjectALifeBleedOutAtMs ~= nil then return false end
    local injury = ProjectALife.Injury
    if injury ~= nil and type(injury.interceptBleed) == "function" then
        local ok, taken = pcall(injury.interceptBleed, target, data, now)
        if ok and taken == true then return false end
    end
    data.ProjectALifeBleedOutAtMs = now + Health.settings.bleedOutMs
    Health.metrics.bleedOuts = Health.metrics.bleedOuts + 1
    data.ProjectALifeDownedUntilMs = now + Health.settings.bleedOutMs
    Health.metrics.downed = Health.metrics.downed + 1
    data.ProjectALifeHealDoneAtMs, data.ProjectALifeHealToFraction = nil, nil
    data.ProjectALifeHandsBusyUntilMs = nil
    pcall(function()
        target:setKnockedDown(true)
        target:setFallOnFront(true)
    end)
    return true
end

function Health.recordWound(attacker, target, zone, remaining, maximum, now, attack)
    pcall(function()
        local data = target:getModData()
        if type(data) ~= "table" then return end
        data.ProjectALifeWounds = (tonumber(data.ProjectALifeWounds) or 0) + 1
        data.ProjectALifeLastWoundZone = zone
        data.ProjectALifeHitRunUntilMs = now + 8000
        data.ProjectALifeLastAttackKind = attack or ProjectALife.Wounds.attackKind(attacker, nil)
        Health.metrics.wounds = Health.metrics.wounds + 1
        if attacker ~= nil then Health.lastAttacker[target] = attacker end
        local limpBefore = data.ProjectALifeWoundLeg == true
        pcall(Health.addInjury, target, data, data.ProjectALifeLastAttackKind, zone)
        if not limpBefore and data.ProjectALifeWoundLeg == true then
            data.ProjectALifeSprintUntilMs = nil
            Health.metrics.legWounds = Health.metrics.legWounds + 1
        end
        local ceiling = (tonumber(maximum)
            or ProjectALife.ShellSimulation.standardHealth()) * Health.settings.bleedFraction
        if (tonumber(remaining) or 0) > 0 and remaining <= ceiling then
            Health.startBleedOut(target, data, now)
        end
    end)
end

Health.zombieParts = { { "arm_l", 20 }, { "arm_r", 20 }, { "torso", 25 }, { "leg_l", 10 }, { "leg_r", 10 }, { "head", 15 } }

function Health.worldHours()
    local hours = ProjectALife.ShellSimulation.worldHours()
    return tonumber(hours) or 0
end

function Health.injuriesOf(shell, data)
    if type(data) ~= "table" then return nil end
    local list = data.ProjectALifeInjuries
    if type(list) == "table" then return list end
    if data.ProjectALifeInjuriesRead == true then return nil end
    data.ProjectALifeInjuriesRead = true
    local registry = ProjectALife.ActorRegistry
    local uid = data.ProjectALifeUID
    if registry == nil or type(registry.peek) ~= "function" or type(uid) ~= "string" then return nil end
    local record = registry.peek(uid)
    local memory = record and record.memory or nil
    if type(memory) ~= "table" or type(memory.injuries) ~= "table" or #memory.injuries == 0 then return nil end
    data.ProjectALifeInjuries = ProjectALife.Wounds.copy(memory.injuries)
    return data.ProjectALifeInjuries
end

function Health.writeInjuries(record)
    record.memory = type(record.memory) == "table" and record.memory or {}
    local list = Health.pendingInjuries
    record.memory.injuries = (type(list) == "table" and #list > 0) and list or nil
end

function Health.persistInjuries(data)
    local registry = ProjectALife.ActorRegistry
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if registry == nil or type(uid) ~= "string" or type(registry.peek) ~= "function"
            or type(registry.updateTransient) ~= "function" then return false end
    local current = registry.peek(uid)
    if current == nil then return false end
    Health.pendingInjuries = ProjectALife.Wounds.copy(data.ProjectALifeInjuries)
    local ok, written = pcall(registry.updateTransient, current.uid, current.revision, Health.writeInjuries, true)
    Health.pendingInjuries = nil
    return ok and written == true
end

function Health.refreshInjuries(data)
    if type(isServer) ~= "function" or not isServer() or type(data) ~= "table" then return false end
    local registry = ProjectALife.ActorRegistry
    local uid = data.ProjectALifeUID
    if registry == nil or type(registry.peek) ~= "function" or type(uid) ~= "string" then return false end
    local record = registry.peek(uid)
    if record == nil then return false end
    local memory = type(record.memory) == "table" and record.memory or {}
    if type(memory.injuries) == "table" and #memory.injuries > 0 then
        data.ProjectALifeInjuries = ProjectALife.Wounds.copy(memory.injuries)
    else
        data.ProjectALifeInjuries = nil
    end
    data.ProjectALifeInjuriesRead = true
    return true
end

function Health.addInjury(target, data, cause, zone)
    local W = ProjectALife.Wounds
    Health.refreshInjuries(data)
    local part
    if zone == "body" and roll(100) < Health.settings.bodyLimbPercent then zone = "limb" end
    if cause == "zombie" then part = W.pick(roll(100), Health.zombieParts)
    else part = W.partFor(zone, roll(100), roll(100)) end
    local kind, severity = W.classify(cause, part, roll(100), roll(100), data.ProjectALifeLastWound)
    local list = Health.injuriesOf(target, data) or {}
    local hours = Health.worldHours()
    W.add(list, part, kind, severity, hours)
    data.ProjectALifeInjuries = list
    data.ProjectALifeLastWoundPart = part
    data.ProjectALifeLastWoundKind = kind
    Health.metrics.injuries = (Health.metrics.injuries or 0) + 1
    Health.applyInjuries(data, list, hours)
    Health.persistInjuries(data)
    return part, kind, severity
end

function Health.applyInjuries(data, list, hours)
    local limp, arms, bleed = ProjectALife.Wounds.effects(list, hours)
    if limp then
        data.ProjectALifeWoundLeg = true
        data.ProjectALifeInjuryLimp = true
    elseif data.ProjectALifeInjuryLimp == true then
        data.ProjectALifeInjuryLimp = nil
        data.ProjectALifeWoundLeg = nil
    end
    if arms < 1 then data.ProjectALifeArmAimScale = arms else data.ProjectALifeArmAimScale = nil end
    if bleed > 0 and (tonumber(data.ProjectALifeWounds) or 0) <= 0 then data.ProjectALifeWounds = 1 end
    return limp, arms, bleed
end

Health.injuryStepMs = 1000

function Health.injuryTick(shell, data, now)
    local list = Health.injuriesOf(shell, data)
    if list == nil then return false end
    local last = tonumber(data.ProjectALifeInjuryTickMs)
    if last ~= nil and now >= last and now - last < Health.injuryStepMs then return false end
    data.ProjectALifeInjuryTickMs = now
    local hours = Health.worldHours()
    local kept, healed = ProjectALife.Wounds.prune(list, hours)
    if healed > 0 then
        data.ProjectALifeInjuries = kept
        list = kept
        Health.metrics.injuriesHealed = (Health.metrics.injuriesHealed or 0) + healed
        Health.persistInjuries(data)
    end
    local _, _, bleed = Health.applyInjuries(data, list, hours)
    if #list == 0 then data.ProjectALifeInjuries = nil end
    if bleed <= 0 or last == nil or now <= last or data.ProjectALifeBleedOutAtMs ~= nil then return false end
    local sim = ProjectALife.ShellSimulation
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    local before = tonumber(sim.trueHealth(shell)) or 0
    if maximum <= 0 or before <= 0 then return false end
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.bleed) == "function" then
        local ok, scale = pcall(tuned.bleed)
        if ok and tonumber(scale) ~= nil then bleed = bleed * tonumber(scale) end
    end
    local after = before - maximum * bleed * math.min(5000, now - last) / 1000
    Health.metrics.bled = (Health.metrics.bled or 0) + 1
    if after <= maximum * Health.settings.bleedFraction then
        sim.setHealth(shell, math.max(0.01, math.min(before, maximum * Health.settings.bleedFraction)))
        Health.startBleedOut(shell, data, now)
        return true
    end
    sim.setHealth(shell, after)
    return true
end

function Health.fearHit(attacker, target, now)
    local gunFear = ProjectALife.ModuleGunFear
    if attacker == nil or gunFear == nil or type(gunFear.onHurt) ~= "function" then return false end
    local data = target:getModData()
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    local store = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or store == nil or type(store.read) ~= "function" then return false end
    local record = store.read(uid)
    if record == nil then return false end
    return gunFear.onHurt(record, target, attacker, now)
end

function Health.afterWound(attacker, target, now, forgiven, attack)
    local relations = ProjectALife.Relations
    if forgiven ~= true and relations ~= nil and type(relations.noteAggression) == "function" then
        relations.noteAggression(attacker, target, now)
    end

    local alreadyDead = false
    pcall(function() alreadyDead = target:isDead() == true end)
    if alreadyDead then return end

    if forgiven ~= true then
        pcall(ProjectALife.Reputation.onPlayerDamagedActor, attacker, target)
        if ProjectALife.PersonalRep ~= nil and type(ProjectALife.PersonalRep.noteHit) == "function" then
            pcall(ProjectALife.PersonalRep.noteHit, attacker, target)
        end
        if ProjectALife.NpcOpinion ~= nil and type(ProjectALife.NpcOpinion.note) == "function" then
            pcall(ProjectALife.NpcOpinion.note, "hit", target, attacker)
        end
    end

    if ProjectALife.Talk ~= nil and type(ProjectALife.Talk.onHitByPlayer) == "function" then
        pcall(ProjectALife.Talk.onHitByPlayer, attacker, target, attack)
    end
    if forgiven == true then return end

    pcall(Health.fearHit, attacker, target, now)

    if attacker ~= nil and ProjectALife.ModuleCareful ~= nil
            and type(ProjectALife.ModuleCareful.onHitByPlayer) == "function" then
        pcall(ProjectALife.ModuleCareful.onHitByPlayer, attacker, target)
    end

    if attacker ~= nil and ProjectALife.Risk ~= nil and type(ProjectALife.Risk.noteAttack) == "function" then
        pcall(ProjectALife.Risk.noteAttack, attacker, target, now)
    end

    pcall(function()
        local perception = ProjectALife.Perception
        if perception == nil or type(perception.noteAttacker) ~= "function" then return end
        if type(instanceof) == "function" and not instanceof(attacker, "IsoPlayer") then return end
        local uid = target:getModData().ProjectALifeUID
        if uid == nil then uid = target:GetVariable("ALifeUID") end
        if type(uid) ~= "string" or uid == "" then return end
        perception.noteAttacker(uid, attacker, 12000, "player")
    end)
end

function Health.zoneForEngineHit(bodyPart, rolled)
    local named
    pcall(function()
        local name = string.lower(tostring(bodyPart))
        if string.find(name, "head", 1, true) or string.find(name, "neck", 1, true) then
            named = "head"
        elseif string.find(name, "leg", 1, true) or string.find(name, "foot", 1, true)
                or string.find(name, "thigh", 1, true) then
            named = "limb"
        end
    end)
    if named ~= nil then return named end
    local damage = ProjectALife.HumanDamage
    if damage == nil or type(damage.zoneFor) ~= "function" then return "torso" end
    local value = tonumber(rolled)
    if value == nil then value = roll(100) end
    local ok, picked = pcall(damage.zoneFor, value)
    if not ok or type(picked) ~= "string" then return "torso" end
    return picked
end

function Health.onEngineHit(shell, wielder, bodyPart, now, after, forgiven, weapon, blocked)
    if Health.enabled ~= true or shell == nil then return end
    if Health.invulnerable(shell) then return Health.pin(shell) end
    local zone = Health.zoneForEngineHit(bodyPart)
    local remaining, maximum = 0, ProjectALife.ShellSimulation.standardHealth()
    pcall(function()
        remaining = tonumber(ProjectALife.ShellSimulation.trueHealth(shell)) or 0
        maximum = ProjectALife.ShellSimulation.maximumFor(shell)
    end)
    if tonumber(after) ~= nil then remaining = math.max(0, tonumber(after)) end
    Health.onDamage(wielder, shell, zone, remaining, maximum, now, forgiven, weapon, blocked)
end

function Health.burnLoss(killRate, elapsedMs, pool)
    local s = Health.settings
    local rate, ms, maximum = tonumber(killRate) or 0, tonumber(elapsedMs) or 0, tonumber(pool) or 0
    if rate <= 0 or ms <= 0 or maximum <= 0 then return 0 end
    ms = math.min(ms, s.fireStepMaxMs)
    local engine = rate / 20 * s.fireUnitsPerSecond * ms / 1000
    return engine * math.max(0, maximum / s.fireZombieHealth - 1)
end

function Health.burn(shell, data, now)
    if shell.isOnFire == nil or shell:isOnFire() ~= true then
        data.ProjectALifeBurnAtMs = nil
        return false
    end
    local last = tonumber(data.ProjectALifeBurnAtMs)
    data.ProjectALifeBurnAtMs = now
    if last == nil or now <= last or shell.getFireKillRate == nil then return false end
    local simulation = ProjectALife.ShellSimulation
    local maximum = simulation.maximumFor(shell)
    local rate = tonumber(shell:getFireKillRate()) or 0
    local loss = Health.burnLoss(rate, now - last, maximum)
    if loss <= 0 then return false end
    local before = tonumber(simulation.trueHealth(shell)) or 0
    if before <= 0 then return false end
    local after = before - loss
    Health.metrics.burned = Health.metrics.burned + 1
    if now >= (tonumber(data.ProjectALifeBurnInjuryAtMs) or 0) then
        data.ProjectALifeBurnInjuryAtMs = now + 2000
        pcall(Health.addInjury, shell, data, "fire", "body")
    end

    local s = Health.settings
    local engineStep = rate / 20 * s.fireUnitsPerSecond * s.fireStepMaxMs / 1000
    if after > engineStep then
        simulation.setHealth(shell, after)
        return true
    end
    simulation.setHealth(shell, 0)
    shell:Kill(Health.lastAttacker[shell] or shell)
    Health.metrics.burnKills = Health.metrics.burnKills + 1
    return true
end

function Health.tick(shell, data, now)
    if Health.enabled ~= true or shell == nil or type(data) ~= "table" then return end
    if Health.invulnerable(shell, data) then return Health.pin(shell, data) end
    if Health.burn(shell, data, now) and shell:isDead() then return end
    if Health.turning(shell, data) then return end
    pcall(Health.injuryTick, shell, data, now)
    local blood = ProjectALife.Blood
    if blood ~= nil then pcall(blood.drip, shell, data, now) end
    pcall(Health.showBandages, shell, data)
    pcall(Health.regen, shell, data, now)
    local bleedAt = tonumber(data.ProjectALifeBleedOutAtMs)
    if bleedAt ~= nil and now >= bleedAt then
        data.ProjectALifeBleedOutAtMs = nil
        pcall(function()
            local attacker = Health.lastAttacker[shell]
            if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.setHealth(shell, 0)
            else shell:setHealth(0) end
            shell:Kill(attacker or shell)
        end)
        return
    end
    local healDoneAt = tonumber(data.ProjectALifeHealDoneAtMs)
    if healDoneAt ~= nil and now >= healDoneAt then
        data.ProjectALifeHealDoneAtMs = nil
        Health.heal(shell, data)
    end
end

function Health.rememberedTurn(uid)
    local registry = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or registry == nil or type(registry.peek) ~= "function" then return nil end
    local record = registry.peek(uid)
    if record == nil or type(record.memory) ~= "table" then return nil end
    return tonumber(record.memory.infectedTurnAtHours)
end

function Health.turning(shell, data)
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.worldHours) ~= "function" then return false end
    local turnAt = tonumber(data.ProjectALifeTurnAtHours)
    if turnAt == nil then
        if data.ProjectALifeInfectionRead == true then return false end
        data.ProjectALifeInfectionRead = true
        turnAt = Health.rememberedTurn(data.ProjectALifeUID)
        if turnAt == nil then return false end
        data.ProjectALifeTurnAtHours = turnAt
    end
    local hours = sim.worldHours()
    if hours == nil or hours < turnAt then return false end
    if type(shell.isDead) == "function" and shell:isDead() then return false end
    Health.metrics.turned = (Health.metrics.turned or 0) + 1
    sim.setHealth(shell, 0)
    shell:Kill(Health.lastAttacker[shell] or shell)
    return true
end

function Health.downedHolds(untilMs, now)
    local limit = tonumber(untilMs)
    return limit ~= nil and (tonumber(now) or 0) < limit
end

Health.bandageParts = {
    head = "Base.Bandage_Head", torso = "Base.Bandage_Chest",
    arm_l = "Base.Bandage_LeftLowerArm", arm_r = "Base.Bandage_RightLowerArm",
    leg_l = "Base.Bandage_LeftLowerLeg", leg_r = "Base.Bandage_RightLowerLeg",
}
Health.bandageCap = 3

function Health.bandageTypes(list)
    local out, seen = {}, {}
    for _, injury in ipairs(type(list) == "table" and list or {}) do
        local kind = ProjectALife.Wounds.kinds[injury.k]
        local itemType = Health.bandageParts[injury.p]
        if kind ~= nil and kind.bleed ~= nil and injury.b == true and itemType ~= nil
                and not seen[itemType] and #out < Health.bandageCap then
            seen[itemType] = true
            out[#out + 1] = itemType
        end
    end
    table.sort(out)
    return out
end

function Health.showBandages(shell, data)
    local list = Health.injuriesOf(shell, data)
    if (list == nil or #list == 0) and (data.ProjectALifeBandageKey == nil or data.ProjectALifeBandageKey == "") then
        return false
    end
    local types = Health.bandageTypes(list)
    local key = table.concat(types, "|")
    if data.ProjectALifeBandageKey == key or (data.ProjectALifeBandageKey == nil and key == "") then return false end
    data.ProjectALifeBandageKey = key
    data.ProjectALifeBandages = #types > 0 and types or nil
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.wearsGarments) == "function" and hydrator.wearsGarments()
            and type(hydrator.showBandages) == "function" then
        hydrator.showBandages(shell, types)
    end
    return true
end

function Health.regen(shell, data, now)
    local last = tonumber(data.ProjectALifeRegenHours)
    local hours = Health.worldHours()
    if last == nil or hours < last then
        data.ProjectALifeRegenHours = hours
        return false
    end
    local step = hours - last
    if step < 0.02 then return false end
    data.ProjectALifeRegenHours = hours
    if data.ProjectALifeBleedOutAtMs ~= nil then return false end
    local rate = Health.settings.regenPerHour
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.regenPlan) == "function" then
        local ok, rested, planned = pcall(tuned.regenPlan, data, now, rate)
        if ok then
            if not rested then return false end
            rate = tonumber(planned) or rate
        end
    end
    local hit = tonumber(data.ProjectALifeLastHitAtMs)
    if hit ~= nil and now - hit < Health.settings.regenQuietMs then return false end
    local list = Health.injuriesOf(shell, data)
    local W = ProjectALife.Wounds
    for _, injury in ipairs(list or {}) do
        if W.bleeding(injury, hours) then return false end
    end
    local sim = ProjectALife.ShellSimulation
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    local health = tonumber(sim.trueHealth(shell)) or 0
    if maximum <= 0 or health <= 0 or health >= maximum then return false end
    step = math.min(step, Health.settings.regenMaxHours)
    sim.setHealth(shell, math.min(maximum, health + maximum * rate * step))
    Health.metrics.regenerated = (Health.metrics.regenerated or 0) + 1
    return true
end

function Health.heal(shell, data)
    pcall(function()
        data = data or shell:getModData()
        data.ProjectALifeWoundLeg = nil
        data.ProjectALifeBleedOutAtMs = nil
        data.ProjectALifeDownedUntilMs = nil
        data.ProjectALifeWounds = nil
        local list = Health.injuriesOf(shell, data)
        if list ~= nil and ProjectALife.Wounds.bandage(list) + ProjectALife.Wounds.splint(list) > 0 then
            Health.persistInjuries(data)
        end
        data.ProjectALifeInjuryLimp = nil
        data.ProjectALifeHealToFraction = nil
        data.ProjectALifeRegenHours = Health.worldHours()
        Health.metrics.healed = Health.metrics.healed + 1
    end)

    pcall(function()
        local held = shell:getPrimaryHandItem()
        local heldType = held ~= nil and tostring(held:getFullType()) or ""
        if heldType == "Base.Bandage" or heldType == "Base.RippedSheets" then
            shell:setPrimaryHandItem(nil)
            shell:getModData().ProjectALifeHandsBusyUntilMs = nil
            local inventory = shell:getInventory()
            if inventory ~= nil then inventory:Remove(held) end
        end
        local animations = ProjectALife.Animations
        if animations ~= nil and type(animations.refreshWeapon) == "function" then
            animations.refreshWeapon(shell, false)
        end
    end)
    return true
end

function Health.wounded(data)
    if type(data) ~= "table" then return false end
    return data.ProjectALifeWoundLeg == true
        or data.ProjectALifeBleedOutAtMs ~= nil
        or (tonumber(data.ProjectALifeWounds) or 0) > 0
end

Health.treatReach = 3.5
Health.treatKits = {
    { item = "Base.AlcoholBandage", fraction = 0.7 }, { item = "Base.Bandage", fraction = 0.65 },
    { item = "Base.AlcoholRippedSheets", fraction = 0.55 }, { item = "Base.RippedSheets", fraction = 0.5 },
}
Health.reportAt = setmetatable({}, { __mode = "k" })
Health.viewAt = setmetatable({}, { __mode = "k" })
Health.viewReach = 10
Health.viewGapMs = 300

function Health.reply(player, payload)
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", "npcWounds", payload) end
        return true
    end
    if type(ProjectALife.WoundsClientReceive) == "function" then
        ProjectALife.WoundsClientReceive(payload)
        return true
    end
    return false
end

function Health.patientFor(player, uid, reach)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    local shell = binding ~= nil and binding.shell or nil
    if shell == nil or shell:isDead() then return nil, "unavailable" end
    local limit = tonumber(reach) or Health.treatReach
    if math.abs(shell:getZ() - player:getZ()) > 0.5
            or (shell:getX() - player:getX()) ^ 2 + (shell:getY() - player:getY()) ^ 2 > limit ^ 2 then
        return nil, "too_far"
    end
    return shell, nil
end

function Health.kitOf(player, wanted)
    local inventory = player:getInventory()
    if inventory == nil then return nil end
    for _, kit in ipairs(Health.treatKits) do
        if wanted == nil or kit.item == wanted then
            local item = inventory:getFirstTypeRecurse(kit.item)
            if item ~= nil then return item, kit end
        end
    end
    return nil
end

function Health.hpPercent(shell)
    local sim = ProjectALife.ShellSimulation
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    local current = tonumber(sim.trueHealth(shell)) or 0
    if maximum <= 0 then return nil end
    return math.max(0, math.min(100, math.floor(current / maximum * 100 + 0.5)))
end

function Health.useKit(player, item)
    local container = item:getContainer() or player:getInventory()
    container:Remove(item)
    if type(isServer) == "function" and isServer() and type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, container, item)
    end
end

function Health.splintBy(player, data, list)
    local broken = false
    for _, injury in ipairs(list or {}) do
        if injury.k == "fracture" and injury.sp ~= true then broken = true end
    end
    if not broken then return "not_needed" end
    local inventory = player:getInventory()
    local item = inventory ~= nil and inventory:getFirstTypeRecurse("Base.Splint") or nil
    if item == nil then return "no_splint" end
    Health.useKit(player, item)
    ProjectALife.Wounds.splint(list)
    Health.applyInjuries(data, list, Health.worldHours())
    Health.persistInjuries(data)
    Health.metrics.splintedByPlayer = (Health.metrics.splintedByPlayer or 0) + 1
    if type(addXp) == "function" and Perks ~= nil and Perks.Doctor ~= nil then pcall(addXp, player, Perks.Doctor, 5) end
    return nil
end

function Health.treatBy(player, record, shell, data, list, wanted)
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, record, player)
        if ok and stance == "hostile" and not Health.downedHolds(data.ProjectALifeDownedUntilMs, nowMs()) then
            return "hostile"
        end
    end
    local open = 0
    for _, injury in ipairs(list or {}) do
        local kind = ProjectALife.Wounds.kinds[injury.k]
        if kind ~= nil and kind.bleed ~= nil and injury.b ~= true then open = open + 1 end
    end
    if open == 0 and data.ProjectALifeBleedOutAtMs == nil then return "not_needed" end
    local item, kit = Health.kitOf(player, wanted)
    if item == nil then return "no_kit" end
    Health.useKit(player, item)
    data.ProjectALifeHealToFraction = kit.fraction
    Health.heal(shell, data)
    Health.metrics.treatedByPlayer = (Health.metrics.treatedByPlayer or 0) + 1
    if type(addXp) == "function" and Perks ~= nil and Perks.Doctor ~= nil then pcall(addXp, player, Perks.Doctor, 5) end
    return nil
end

function Health.onWoundsCommand(player, args)
    local uid = type(args) == "table" and tostring(args.uid or "") or ""
    local payload = { uid = uid, ok = false }
    local view = uid ~= "" and args.view == true and args.treat ~= true and args.splint ~= true
    if view then payload.view = true end
    if Health.enabled ~= true or player == nil or uid == "" or #uid > 64 then
        payload.reason = "unavailable"
        return Health.reply(player, payload)
    end
    local now = nowMs()
    local gate, gap, reach = Health.reportAt, 400, nil
    if view then gate, gap, reach = Health.viewAt, Health.viewGapMs, Health.viewReach end
    if now < (gate[player] or 0) then return false end
    gate[player] = now + gap
    local shell, why = Health.patientFor(player, uid, reach)
    local registry = ProjectALife.ActorRegistry
    local record = shell ~= nil and registry ~= nil and registry.read(uid) or nil
    if shell == nil or record == nil or record.lifecycle ~= "active" then
        payload.reason = why or "unavailable"
        return Health.reply(player, payload)
    end
    local data = shell:getModData()
    Health.refreshInjuries(data)
    local list = Health.injuriesOf(shell, data)
    if args.treat == true or args.splint == true then
        local relations = ProjectALife.Relations
        if relations ~= nil and type(relations.playerStance) == "function" and args.splint == true then
            local ok, stance = pcall(relations.playerStance, record, player)
            if ok and stance == "hostile" and data.ProjectALifeBleedOutAtMs == nil then payload.reason = "hostile" end
        end
        if payload.reason == nil and args.splint == true then
            payload.reason = Health.splintBy(player, data, list)
        elseif payload.reason == nil then
            payload.reason = Health.treatBy(player, record, shell, data, list, type(args.kit) == "string" and args.kit or nil)
        end
        payload.treated = payload.reason == nil
        list = Health.injuriesOf(shell, data)
        if payload.treated then Health.syncOwner(shell) end
    end
    payload.ok = payload.reason == nil
    payload.injuries = ProjectALife.Wounds.copy(list)
    payload.hours = Health.worldHours()
    payload.downed = data.ProjectALifeBleedOutAtMs ~= nil or nil
    payload.hp = Health.hpPercent(shell)
    payload.state = type(data.ProjectALifeInjured) == "string" and data.ProjectALifeInjured or nil
    return Health.reply(player, payload)
end

function Health.onClientCommand(module, command, player, args)
    if module ~= "ProjectALife" or command ~= "npcWounds" then return end
    local ok = pcall(Health.onWoundsCommand, player, args)
    if not ok then Health.metrics.woundCommandFaults = (Health.metrics.woundCommandFaults or 0) + 1 end
end

if type(Events) == "table" and Events.OnClientCommand ~= nil and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Health.onClientCommand)
end

return Health
