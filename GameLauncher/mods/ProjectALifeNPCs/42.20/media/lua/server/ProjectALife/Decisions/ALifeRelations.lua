require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/Records/ALifeRelationLayers"
require "ProjectALife/Decisions/ALifeFairness"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Reputation = ProjectALife.Reputation
local Layers = ProjectALife.RelationLayers
local Relations = { warfare = true }
ProjectALife.Relations = Relations

function Relations.configure(options)
    Relations.warfare = options == nil or options.warfare ~= false
end

local function normalized(value)
    value = string.lower(tostring(value or ""))

    if value == "suspicious" then return "careful" end
    if value == "allied" then return "friendly" end
    if value == "friendly" or value == "neutral" or value == "hostile"
            or value == "careful" then
        return value
    end
    return nil
end

function Relations.baselineStance(actor, player)
    local authored = Relations.spawnStance(type(actor) == "table" and actor.memory or nil)
    if authored ~= nil then return authored, "spawn" end
    local faction = type(actor) == "table" and Catalog.faction(actor.factionId) or nil
    if faction == nil then return nil, nil end
    local word, layer = Layers.towardPlayer(faction, Layers.professionOf(player))
    local stance = normalized(word)
    local personal = ProjectALife.PersonalRep
    if player ~= nil and personal ~= nil and type(personal.firstContact) == "function" then
        local reputation = ProjectALife.Reputation
        local hasRow = reputation ~= nil and type(reputation.recordedStatus) == "function"
            and reputation.recordedStatus(player, actor) ~= nil
        if not hasRow then
            local ok, cell = pcall(personal.firstContact, player, actor, stance)
            local cells = ProjectALife.RepLevels ~= nil and ProjectALife.RepLevels.cells or nil
            if ok and type(cell) == "string" and cells ~= nil and type(cells[cell]) == "table" then
                return cells[cell].stance, "reputation"
            end
        end
    end
    return stance, layer
end

function Relations.spawnStance(memory)
    local value = type(memory) == "table" and memory.spawnStance or nil
    if value == "friendly" or value == "neutral"
            or value == "careful" or value == "hostile" then return value end
    return nil
end

Relations.orderedModes = { hunt = true, manhunt = true, assault = true, full_raid = true }

function Relations.orderedHostile(actor, player)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" or player == nil or memory.hostileOverride == false then return false end
    if memory.role == "backup" or memory.supportRole == "backup" or memory.revengeKey ~= nil then return false end
    local key = Reputation.playerKey(player)
    if key == nil then return false end
    local named = memory.targetUsername
    if type(named) == "string" and named ~= "" then
        local wanted = string.lower(named)
        if string.lower(tostring(key)) == wanted then return true end
        local ok, username = pcall(function() return player:getUsername() end)
        return ok and string.lower(tostring(username or "")) == wanted
    end
    return memory.debugSpawn == true and Relations.orderedModes[string.lower(tostring(memory.adminMode or ""))] == true
end

function Relations.hostileToPlayer(actor, player)
    local memory = type(actor) == "table" and actor.memory or nil
    if memory and memory.robberyTruce and player ~= nil then
        local key = Reputation.playerKey(player)
        local untilMs = key and tonumber(memory.robberyTruce[key])
        local now = type(getTimestampMs) == "function" and getTimestampMs() or math.floor(os.time() * 1000)
        if untilMs and now < untilMs then return false end
    end

    if type(memory) == "table" and player ~= nil and type(memory.robbery) == "table" then
        local robbery = ProjectALife.ModuleRobbery
        local key = Reputation.playerKey(player)
        if key ~= nil and robbery ~= nil and type(robbery.activeFor) == "function" then
            local ok, holding = pcall(robbery.activeFor, actor, key)
            if ok and holding == true then return false end
        elseif key ~= nil and memory.robbery.playerKey == key
                and memory.robbery.phase ~= "execute" then

            return false
        end
    end
    local standoff = ProjectALife.Standoff
    if type(memory) == "table" and player ~= nil and standoff ~= nil and type(standoff.holdsFor) == "function"
            and standoff.holdsFor(memory, Reputation.playerKey(player)) then return false end
    local fair = ProjectALife.Fairness
    if player ~= nil and fair ~= nil and type(fair.hostilityStands) == "function"
            and not fair.hostilityStands(actor, player) then return false end
    if type(memory) == "table" and player ~= nil
            and type(memory.hostileToPlayerKeys) == "table" then
        local key = Reputation.playerKey(player)
        if key ~= nil and memory.hostileToPlayerKeys[key] == true then return true end
    end
    if Relations.orderedHostile(actor, player) then return true, "ordered_hostile" end

    if player ~= nil and type(Reputation.recordedStatus) == "function" then
        local earned
        local ok, value = pcall(Reputation.recordedStatus, player, actor)
        if ok then earned = value end
        if earned == "hostile" then return true end
    end
    if type(memory) == "table" then
        if memory.hostileOverride == true then return true end
        if memory.hostileOverride == false then return false end
    end
    if player ~= nil and type(Relations.adapters) == "table"
            and type(Relations.adapters.reputation) == "function" then
        local ok, answer = pcall(Relations.adapters.reputation, actor, player)
        if ok and (answer == true or answer == false) then return answer end
    end
    return Relations.baselineStance(actor, player) == "hostile"
end

function Relations.sameSide(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then return false end
    if source.uid ~= nil and source.uid == target.uid then return true end
    if source.factionId ~= nil and source.factionId == target.factionId then return true end
    local sm = type(source.memory) == "table" and source.memory or {}
    local tm = type(target.memory) == "table" and target.memory or {}
    if sm.groupId ~= nil and sm.groupId == tm.groupId then return true end
    if sm.outpostId ~= nil and sm.outpostId == tm.outpostId then return true end
    if sm.supportForGroupId ~= nil and sm.supportForGroupId == tm.groupId then return true end
    if tm.supportForGroupId ~= nil and tm.supportForGroupId == sm.groupId then return true end
    return false
end

function Relations.status(source, target)
    if not Relations.warfare or source == nil or target == nil then return "neutral" end
    if source.uid == target.uid then return "friendly" end

    local sm, tm = source.memory or {}, target.memory or {}
    local sg, tg = sm.groupId or ("solo:" .. tostring(source.uid)), tm.groupId or ("solo:" .. tostring(target.uid))
    if sm.supportForGroupId == tg or tm.supportForGroupId == sg
            or (sm.supportForGroupId ~= nil and sm.supportForGroupId == tm.supportForGroupId)
            or (sm.outpostId ~= nil and sm.outpostId == tm.outpostId) then return "friendly" end
    if source.factionId == target.factionId then
        local sourceMemory = type(source.memory) == "table" and source.memory or {}
        local targetMemory = type(target.memory) == "table" and target.memory or {}
        local groupCombat = sourceMemory.debugGroupWarfare == true
            and targetMemory.debugGroupWarfare == true
            and type(sourceMemory.groupId) == "string"
            and type(targetMemory.groupId) == "string"
            and sourceMemory.groupId ~= targetMemory.groupId
        return groupCombat and "hostile" or "friendly"
    end
    local grudges = source.memory and source.memory.hostileToActorKeys
    if type(grudges) == "table" and grudges[target.uid] == true then return "hostile" end
    local sourceFaction = Catalog.faction(source.factionId)
    local targetFaction = Catalog.faction(target.factionId)
    if sourceFaction == nil or targetFaction == nil then return "neutral" end

    return normalized(Layers.towardFaction(sourceFaction, targetFaction)) or "hostile"
end

function Relations.playerStance(actor, player)
    local stance = Relations.basePlayerStance(actor, player)
    local fair = ProjectALife.Fairness
    if stance == "hostile" and player ~= nil and fair ~= nil and type(fair.stanceFor) == "function" then
        return fair.stanceFor(actor, player, stance)
    end
    return stance
end

function Relations.basePlayerStance(actor, player)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) == "table" then
        if memory.hostileOverride == true then return "hostile" end

        if player ~= nil and type(memory.hostileToPlayerKeys) == "table" then
            local key = Reputation.playerKey(player)
            if key ~= nil and memory.hostileToPlayerKeys[key] == true then return "hostile" end
        end
    end
    local party = ProjectALife.Party
    if player ~= nil and party ~= nil and type(party.friendly) == "function" and party.friendly(actor, player) then
        return "friendly"
    end
    local stance = Relations.baselineStance(actor, player) or "neutral"

    local forced = type(memory) == "table" and memory.hostileOverride == false
    if forced then stance = "friendly" end
    if player ~= nil then
        local status
        if type(Reputation.recordedStatus) == "function" then
            local ok, earned = pcall(Reputation.recordedStatus, player, actor)
            if ok then status = earned end
        end
        if status == "hostile" then return "hostile" end
        if not forced and (status == "friendly" or status == "careful" or status == "neutral") then

            if not (status == "neutral" and stance == "careful") then stance = status end
        end
    end

    if type(memory) == "table" and player ~= nil then
        local key = Reputation.playerKey(player)
        local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
        if key ~= nil then
            local wary = type(memory.carefulPlayerKeys) == "table" and tonumber(memory.carefulPlayerKeys[key]) or nil
            if wary ~= nil and now < wary and (stance == "neutral" or stance == "friendly") then stance = "careful" end
            local tolerated = type(memory.tolerateUntil) == "table" and tonumber(memory.tolerateUntil[key]) or nil
            if tolerated ~= nil and now < tolerated and stance == "careful" then stance = "neutral" end
        end
    end
    if type(memory) == "table" and memory.hostileOverride == true then return "hostile" end
    return stance
end

function Relations.auditLine(actor, player)
    if type(actor) ~= "table" or player == nil then return nil end
    local faction = Catalog.faction(actor.factionId)
    local base = normalized(Layers.towardPlayer(faction, nil)) or "neutral"
    local shift = Layers.shiftFor(faction, Layers.professionOf(player))
    local reputation = Reputation.recordedStatus(player, actor)
    return "[ALIFE-REL] uid=" .. tostring(actor.uid) .. " faction=" .. tostring(actor.factionId)
        .. " player=" .. tostring(Reputation.playerKey(player)) .. " base=" .. base
        .. " folderOverride=none professionShift=" .. tostring(shift)
        .. " reputation=" .. tostring(reputation or "none")
        .. " final=" .. Relations.playerStance(actor, player)
end

function Relations.hostile(source, target)
    local stance = Relations.status(source, target)

    return stance == "hostile"
end

Relations.aggression = {}
Relations.aggressionHoldMs = 10000
Relations.aggressionLimit = 64

function Relations.actorRecord(value)
    if value == nil then return nil end
    local registry = ProjectALife.ActorRegistry
    local look = registry ~= nil and (registry.peek or registry.read) or nil
    if type(look) ~= "function" then return nil end
    if type(value) == "table" and type(value.uid) == "string" then
        local record = look(value.uid)
        if record ~= nil and record.generation == value.generation then return record end
        return nil
    end
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
    if type(value.getModData) ~= "function" then return nil end
    local data = value:getModData()
    if type(data) ~= "table" or data.ProjectALifeOwned ~= true or type(data.ProjectALifeUID) ~= "string" then return nil end
    local record = look(data.ProjectALifeUID)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[data.ProjectALifeUID] or nil
    if record ~= nil and binding ~= nil and binding.shell == value
            and binding.generation == record.generation
            and tonumber(data.ProjectALifeGeneration) == record.generation then return record end
    return nil
end

function Relations.aggressionKey(value)
    local record = Relations.actorRecord(value)
    if record ~= nil then return "actor:" .. record.uid end
    if type(value) == "table" and value.uid ~= nil then return nil end
    if type(value) == "string" then return "player:" .. value end
    if value == nil or type(instanceof) ~= "function" or not instanceof(value, "IsoPlayer") then return nil end
    local key = Reputation.playerKey(value)
    if key ~= nil then return "player:" .. tostring(key) end
    return nil
end

function Relations.aggressionEntry(a, b, now)
    local ak, bk = Relations.aggressionKey(a), Relations.aggressionKey(b)
    if ak == nil or bk == nil or ak == bk then return nil end
    local key = ak .. "|" .. bk
    if bk < ak then key = bk .. "|" .. ak end
    local entry = Relations.aggression[key]
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs() or math.floor(os.time() * 1000))
    if entry ~= nil and now >= entry.atMs and now < entry.untilMs then return entry, ak, bk, key end
    return nil, ak, bk, key
end

function Relations.noteAggression(aggressor, victim, now)
    if type(isClient) == "function" and isClient() then return false end
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs() or math.floor(os.time() * 1000))
    local entry, ak, bk, key = Relations.aggressionEntry(aggressor, victim, now)
    if key == nil then return false end
    if entry == nil then
        local count, oldestKey, oldest = 0, nil, math.huge
        for id, held in pairs(Relations.aggression) do
            if now >= held.untilMs or now < held.atMs then Relations.aggression[id] = nil
            else
                count = count + 1
                if held.untilMs < oldest then oldestKey, oldest = id, held.untilMs end
            end
        end
        if count >= Relations.aggressionLimit and oldestKey ~= nil then Relations.aggression[oldestKey] = nil end
        entry = { initiator = Relations.openerOf(aggressor, victim, ak, bk), atMs = now }
        Relations.aggression[key] = entry
    end
    entry.untilMs = now + Relations.aggressionHoldMs
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.onAggression) == "function" then pcall(talk.onAggression, aggressor, victim) end
    return true
end

function Relations.openerOf(aggressor, victim, ak, bk)
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.openedBetween) == "function" and fair.openedBetween(victim, aggressor) then
        return bk
    end
    return ak
end

function Relations.wasAggressor(actor, other, now)
    local entry, key = Relations.aggressionEntry(actor, other, now)
    return entry ~= nil and entry.initiator == key
end

function Relations.isSelfDefence(defender, other, now)
    local entry, _, key = Relations.aggressionEntry(defender, other, now)
    return entry ~= nil and entry.initiator == key
end

function Relations.witnesses(record, victim, aggressor)
    if record.uid == victim.uid then return true end
    local watchdog = ProjectALife.Watchdog
    local bindings = watchdog ~= nil and watchdog.bindings or nil
    if type(bindings) ~= "table" then return false end
    local binding, target = bindings[record.uid], bindings[victim.uid]
    local shell = binding ~= nil and binding.shell or nil
    local body = target ~= nil and target.shell or nil
    if shell == nil or body == nil or binding.generation ~= record.generation
            or target.generation ~= victim.generation then return false end
    if type(shell.getCurrentSquare) ~= "function" or shell:getCurrentSquare() == nil
            or type(body.getCurrentSquare) ~= "function" or body:getCurrentSquare() == nil
            or type(shell.getX) ~= "function" or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function"
            or type(body.getX) ~= "function" or type(body.getY) ~= "function" or type(body.getZ) ~= "function" then return false end
    local talk = ProjectALife.Talk
    local radius = talk ~= nil and type(talk.settings) == "table" and tonumber(talk.settings.mateHitRadius) or 15
    local dx, dy = shell:getX() - body:getX(), shell:getY() - body:getY()
    if math.floor(shell:getZ()) ~= math.floor(body:getZ()) or dx * dx + dy * dy > radius * radius then return false end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.engineCanSee) == "function" then
        return perception.engineCanSee(shell, body) == true
    end
    return type(shell.CanSee) == "function" and shell:CanSee(body) == true
end

function Relations.provoke(victim, aggressor)
    if victim == nil or aggressor == nil or not Relations.warfare
            or victim.uid == aggressor.uid then return false end
    if Relations.status(victim, aggressor) == "friendly"
            and Relations.status(aggressor, victim) ~= "hostile" then return false end
    Relations.noteAggression(aggressor, victim)
    if Relations.isSelfDefence(aggressor, victim) then return false end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return false end
    local memory = victim.memory or {}
    local members = {}
    registry.each(function(record)
        local m = record.memory or {}
        if record.lifecycle == "active" and (record.uid == victim.uid
                or (memory.groupId ~= nil and m.groupId == memory.groupId)
                or (memory.outpostId ~= nil and m.outpostId == memory.outpostId))
                and Relations.witnesses(record, victim, aggressor) then
            members[#members + 1] = record.uid
        end
    end)
    for _, uid in ipairs(Relations.writeGrudge(registry, members, aggressor.uid)) do
        local perception = ProjectALife.Perception
        if perception ~= nil then perception.forgetIgnored(uid) end
        local decisions = ProjectALife.DecisionLoop
        if decisions ~= nil and decisions.passiveQuietAtMs ~= nil then decisions.passiveQuietAtMs[uid] = nil end
    end
    return true
end

function Relations.writeGrudge(registry, members, aggressorUid)
    local function mutation(current)
        current.memory = current.memory or {}
        current.memory.hostileToActorKeys = current.memory.hostileToActorKeys or {}
        current.memory.hostileToActorKeys[aggressorUid] = true
    end
    local present = {}
    if type(registry.updateMany) ~= "function" then
        for _, uid in ipairs(members) do
            local record = registry.read(uid)
            if record ~= nil then
                registry.update(uid, record.revision, mutation)
                present[#present + 1] = uid
            end
        end
        return present
    end
    local look = type(registry.peek) == "function" and registry.peek or registry.read
    local pending = {}
    for _, uid in ipairs(members) do
        local record = look(uid)
        if record ~= nil then
            present[#present + 1] = uid
            local keys = type(record.memory) == "table" and record.memory.hostileToActorKeys or nil
            if not (type(keys) == "table" and keys[aggressorUid] == true) then
                pending[#pending + 1] = uid
            end
        end
    end
    if #pending > 0 then registry.updateMany(pending, mutation) end
    return present
end

return Relations
