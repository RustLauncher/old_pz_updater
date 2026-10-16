require "ProjectALife/Behaviours/ALifeInjuryRules"
require "ProjectALife/Combat/ALifeInjury"
require "ProjectALife/Combat/ALifeHealth"
require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}

local Rules = ProjectALife.InjuryRules
local Injury = ProjectALife.Injury
local Health = ProjectALife.Health

local Aid = {
    lastAt = setmetatable({}, { __mode = "k" }),
    metrics = { asked = 0, refused = 0, deaths = 0, penalised = 0, given = 0, noKit = 0, tooFar = 0, sentAway = 0,
        awayFailed = 0, converted = 0, convertFailed = 0 },
}
ProjectALife.InjuryAid = Aid

function Aid.refuse(reason)
    Aid.metrics.refused = Aid.metrics.refused + 1
    return { ok = false, reason = reason }
end

function Aid.patientFor(player, uid)
    if not Rules.flag("Injury_Enabled", true) or not Injury.multiplayerAllowed() then return nil, nil, "disabled" end
    if player == nil or type(uid) ~= "string" or uid == "" or #uid > 64 then return nil, nil, "unavailable" end
    local shell, binding = Injury.shellOf(uid)
    local data = Injury.dataOf(shell)
    if shell == nil or data == nil then return nil, nil, "unavailable" end
    local record = Injury.recordOf(data)
    if record == nil or record.lifecycle ~= "active" or record.uid ~= uid
            or data.ProjectALifeUID ~= uid or data.ProjectALifeGeneration ~= record.generation
            or binding.generation ~= record.generation then return nil, nil, "unavailable" end
    local injury = type(record.memory) == "table" and record.memory.injury or nil
    if type(injury) ~= "table" or injury.s ~= "down" then return nil, nil, "not_injured" end
    if data.ProjectALifeInjured ~= "down" then return nil, nil, "not_injured" end
    local px, py, pz = Injury.xyz(player)
    local sx, sy, sz = Injury.xyz(shell)
    if px == nil or sx == nil then return nil, nil, "unavailable" end
    local reach = Rules.settings().reachTiles
    if math.abs(sz - pz) > 0.5 or (sx - px) ^ 2 + (sy - py) ^ 2 > reach * reach then return nil, nil, "too_far" end
    data.ProjectALifeInjuryTalkUntilMs = Injury.now() + 20000
    return shell, data, nil
end

function Aid.attackerOf(shell, data)
    local attacker = Health.lastAttacker[shell]
    local byPlayer, byActor = false, false
    if attacker ~= nil and type(instanceof) == "function" then
        byPlayer = instanceof(attacker, "IsoPlayer") == true
        if not byPlayer then
            local other = Injury.dataOf(attacker)
            byActor = other ~= nil and other.ProjectALifeUID ~= nil and attacker ~= shell
        end
    end
    return Rules.attackerClass(data.ProjectALifeLastAttackKind, byPlayer, byActor)
end

function Aid.factionName(record)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(record.factionId) or nil
    local name = type(faction) == "table" and type(faction.general) == "table" and faction.general.name or nil
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function Aid.outpostFacts(record, player)
    local memory = type(record.memory) == "table" and record.memory or nil
    local sites = ProjectALife.OutpostRegistry
    if memory == nil or memory.outpostId == nil or sites == nil or type(sites.read) ~= "function" then return nil end
    local site = sites.read(tostring(memory.outpostId))
    if type(site) ~= "table" or tonumber(site.x) == nil or tonumber(site.y) == nil then return nil end
    local px, py = Injury.xyz(player)
    if px == nil then return nil end
    return {
        distance = Rules.distance(px, py, site.x, site.y),
        direction = Rules.direction(px, py, site.x, site.y),
    }
end

function Aid.facts(shell, data, record, player)
    local names = ProjectALife.Names
    local tactics = ProjectALife.SquadTactics
    local x, y = Injury.xyz(shell)
    local facts = { faction = Aid.factionName(record), crew = 1, attacker = Aid.attackerOf(shell, data) }
    if names ~= nil and type(names.of) == "function" then facts.name = names.of(record) end
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.groupId ~= nil and tactics ~= nil and type(tactics.livingMembers) == "function" then
        local ok, count = pcall(tactics.livingMembers, memory.groupId, record.uid, x or 0, y or 0, 80)
        if ok then facts.crew = 1 + (tonumber(count) or 0) end
    end
    facts.outpost = Aid.outpostFacts(record, player)
    local knowledge = ProjectALife.Knowledge
    local fix = memory.knowledgeFix
    if type(fix) == "table" and knowledge ~= nil and type(knowledge.keyOf) == "function" then
        local ok, key = pcall(knowledge.keyOf, player)
        facts.hunting = ok and key ~= nil and fix.key == key
    end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.nearestTown) == "function" and x ~= nil then
        local ok, town = pcall(speech.nearestTown, x, y)
        if ok then facts.town = town end
    end
    return facts
end

function Aid.repAdjust(player, delta, cause)
    local personal, reputation = ProjectALife.PersonalRep, ProjectALife.Reputation
    if personal == nil or reputation == nil or type(personal.rowFor) ~= "function"
            or type(personal.adjust) ~= "function" then return 0 end
    local ok, applied = pcall(function()
        local key = reputation.playerKey(player)
        if key == nil then return 0 end
        local row = personal.rowFor(key, player, true)
        if row == nil then return 0 end
        local bucket
        if delta > 0 then bucket = "deed" end
        local changed, from = personal.adjust(row, delta, personal.nowHours(), false, bucket)
        personal.dirty = true
        if type(personal.announce) == "function" then personal.announce(player, cause, changed, from) end
        return changed
    end)
    if ok then return tonumber(applied) or 0 end
    return 0
end

function Aid.stanceOf(record, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return "neutral" end
    local ok, stance = pcall(relations.playerStance, record, player)
    if ok and type(stance) == "string" then return stance end
    return "neutral"
end

function Aid.bleedOut(shell, data)
    local attacker = Health.lastAttacker[shell] or shell
    pcall(function() ProjectALife.ShellSimulation.setHealth(shell, 0) end)
    pcall(function() shell:Kill(attacker) end)
    Injury.onDeath(shell, data)
    Injury.metrics.interrogationDeaths = Injury.metrics.interrogationDeaths + 1
    Aid.metrics.deaths = Aid.metrics.deaths + 1
end

function Aid.interrogate(player, args)
    local uid = type(args) == "table" and tostring(args.uid or "") or ""
    local question = type(args) == "table" and tostring(args.question or "") or ""
    local payload = { kind = "interrogate", uid = uid, question = question, ok = false }
    local now = Injury.now()
    if now < (Aid.lastAt[player] or 0) then payload.reason = "busy"; return payload end
    Aid.lastAt[player] = now + 700
    if not Rules.questionKnown(question) then payload.reason = "unknown_question"; return payload end
    local shell, data, why = Aid.patientFor(player, uid)
    if shell == nil then payload.reason = why; return payload end
    local record = Injury.recordOf(data)
    if record == nil then payload.reason = "unavailable"; return payload end
    local settings = Rules.settings()
    Injury.metrics.interrogations = Injury.metrics.interrogations + 1
    Aid.metrics.asked = Aid.metrics.asked + 1
    local stance = Aid.stanceOf(record, player)
    if stance ~= "hostile" and data.ProjectALifePenalised ~= true then
        data.ProjectALifePenalised = true
        Aid.metrics.penalised = Aid.metrics.penalised + 1
        Aid.repAdjust(player, -settings.repPenalty, "interrogated")
    end
    local rolled = Injury.roll(100)
    if Rules.dies(settings.deathPercent, rolled) then
        Aid.bleedOut(shell, data)
        payload.ok, payload.died = true, true
        Injury.log("interrogation uid=" .. uid .. " q=" .. question .. " roll=" .. tostring(rolled) .. " result=died")
        return payload
    end
    local asked = type(data.ProjectALifeAsked) == "table" and data.ProjectALifeAsked or {}
    data.ProjectALifeAsked = asked
    local text
    if asked[question] == true then
        text = Rules.refusedText
    else
        text = Rules.answer(question, Aid.facts(shell, data, record, player), Injury.roll(1000))
        asked[question] = true
    end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.say) == "function" then
        pcall(speech.say, shell, text, { downedOk = true, face = player })
    end
    payload.ok, payload.text = true, text
    Injury.log("interrogation uid=" .. uid .. " q=" .. question .. " roll=" .. tostring(rolled) .. " result=answered")
    return payload
end

function Aid.mutate(record)
    local memory = type(record.memory) == "table" and record.memory or {}
    record.memory = memory
    local key = Aid.pendingKey
    memory.spawnStance = "neutral"
    memory.hostileOverride = nil
    if key ~= nil and type(memory.hostileToPlayerKeys) == "table" then memory.hostileToPlayerKeys[key] = nil end
    memory.groupId = Aid.pendingGroup
    memory.outpostId, memory.outpostSquadId, memory.squadId = nil, nil, nil
    memory.supportForGroupId = nil
    if memory.conduct == "leader" then memory.conduct = nil end
    memory.injuryAided = key or true
end

function Aid.convert(record, player, now)
    local registry = ProjectALife.ActorRegistry
    local reputation = ProjectALife.Reputation
    if registry == nil or type(registry.update) ~= "function" then return false end
    local current = registry.peek(record.uid)
    if current == nil then return false end
    Aid.pendingKey = reputation ~= nil and reputation.playerKey(player) or nil
    Aid.pendingGroup = "alife-injured:" .. tostring(record.uid) .. ":" .. tostring(now)
    local updated, reason = registry.update(current.uid, current.revision, Aid.mutate)
    Aid.pendingKey, Aid.pendingGroup = nil, nil
    if updated == nil then
        Aid.metrics.convertFailed = Aid.metrics.convertFailed + 1
        Injury.log("aid convert failed uid=" .. tostring(record.uid) .. " reason=" .. tostring(reason))
        return false
    end
    Aid.metrics.converted = Aid.metrics.converted + 1
    return true
end

function Aid.standable(x, y, z)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if square == nil then return false end
    local ok, free = pcall(function()
        if square:isSolid() == true or square:isSolidTrans() == true then return false end
        return square:isFree(false) == true
    end)
    return ok and free == true
end

function Aid.sendAway(shell, data, player, now, settings)
    local decisions = ProjectALife.DecisionLoop
    local x, y, z = Injury.xyz(shell)
    local px, py = Injury.xyz(player)
    if decisions == nil or type(decisions.setOrder) ~= "function" or x == nil or px == nil then return nil end
    local generation = data.ProjectALifeGeneration
    for attempt = 0, 27 do
        local ax, ay = Rules.leaveAnchor(x, y, px, py, settings.leaveTiles, attempt)
        if Aid.standable(ax, ay, z) then
            local ok, accepted = pcall(decisions.setOrder, data.ProjectALifeUID, generation, {
                kind = "patrol", source = "player", quiet = true,
                anchor = { x = ax, y = ay, z = math.floor(z) }, untilMs = now + settings.leaveMs,
            })
            if ok and accepted == true then return ax, ay end
        end
    end
    return nil
end

function Aid.give(player, args)
    local uid = type(args) == "table" and tostring(args.uid or "") or ""
    local payload = { kind = "aid", uid = uid, ok = false }
    local now = Injury.now()
    if now < (Aid.lastAt[player] or 0) then payload.reason = "busy"; return payload end
    Aid.lastAt[player] = now + 700
    local shell, data, why = Aid.patientFor(player, uid)
    if shell == nil then
        if why == "too_far" then Aid.metrics.tooFar = Aid.metrics.tooFar + 1 end
        payload.reason = why
        return payload
    end
    local record = Injury.recordOf(data)
    if record == nil then payload.reason = "unavailable"; return payload end
    local inventory
    pcall(function() inventory = player:getInventory() end)
    local item, kit = Rules.kitOf(inventory)
    if item == nil then
        Aid.metrics.noKit = Aid.metrics.noKit + 1
        payload.reason = "no_kit"
        return payload
    end
    Health.useKit(player, item)
    local settings = Rules.settings()
    Aid.convert(record, player, now)
    Injury.recover(shell, data, now, "aided", math.max(kit.heal, settings.aidFraction), true)
    local ax, ay = Aid.sendAway(shell, data, player, now, settings)
    if ax ~= nil then Aid.metrics.sentAway = Aid.metrics.sentAway + 1 else Aid.metrics.awayFailed = Aid.metrics.awayFailed + 1 end
    Aid.repAdjust(player, settings.repGain, "saved")
    local current = Injury.recordOf(data)
    local stored = current ~= nil and type(current.memory) == "table" and current.memory.injury or nil
    Health.syncOwner(shell, stored or false)
    Injury.say(shell, data, "INJURED_UP", player)
    Injury.metrics.aided = Injury.metrics.aided + 1
    Aid.metrics.given = Aid.metrics.given + 1
    payload.ok, payload.item = true, kit.item
    Injury.log("aid uid=" .. uid .. " item=" .. tostring(kit.item) .. " away=" .. tostring(ax ~= nil))
    return payload
end

function Aid.onClientCommand(module, command, player, args)
    if module ~= "ProjectALife" or player == nil then return end
    if command ~= "injuryInterrogate" and command ~= "injuryAid" then return end
    local ok, payload = pcall(function()
        if command == "injuryInterrogate" then return Aid.interrogate(player, args) end
        return Aid.give(player, args)
    end)
    if not ok then
        Injury.metrics.faults = (Injury.metrics.faults or 0) + 1
        Injury.lastFault = tostring(payload)
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil then pcall(plus.luaError, "injury", payload, true, command) end
        payload = { ok = false, reason = "fault", uid = type(args) == "table" and args.uid or nil }
    end
    Injury.reply(player, payload)
end

if type(Events) == "table" and Events.OnClientCommand ~= nil and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Aid.onClientCommand)
end

return Aid
