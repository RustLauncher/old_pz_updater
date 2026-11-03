require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Presence = {
    id = "talk",
    settings = {
        enabled = true,
        checkMs = 700,
        greetRadius = 5,
        greetCooldownMs = 180000,
        passRadius = 8,
        passChance = 35,
        passCooldownMs = 120000,
        spotRadius = 30,
        spotCooldownMs = 600000,
        stareRadius = 2.5,
        stareAfterMs = 20000,
        stareCooldownMs = 300000,
        courtesy = true,
        courtesyTiles = 6,
        playerListMs = 250,
        memoMs = 500,
        pruneEveryMs = 60000,

        coopGapMs = 12000,
    },
    fights = {},
    nextCheckAt = {},
    greeted = {},
    passed = {},
    spotted = {},
    lingering = {},
    stared = {},
    playerList = {},
    playerListAtMs = nil,
    playerListFrom = nil,
    memo = { uid = nil, player = nil, atMs = 0, courteous = false },
    prunedAtMs = nil,
    metrics = { holds = 0, greets = 0, passes = 0, spots = 0, stares = 0, leadsRefused = 0 },
}
ProjectALife.ModuleTalkPresence = Presence

Presence.spotRegisters = { outlaw = true, raider = true, gang = true, club = true, prison = true, crime = true }

Presence.courteousStances = { friendly = true, allied = true, neutral = true, careful = true }

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(maximum)
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

function Presence.players()
    if type(Presence.playersAdapter) == "function" then return Presence.playersAdapter() end
    local list = {}
    pcall(function()
        local online = getOnlinePlayers and getOnlinePlayers() or nil
        if online ~= nil and online:size() > 0 then
            for index = 0, online:size() - 1 do list[#list + 1] = online:get(index) end
        else
            for index = 0, getNumActivePlayers() - 1 do
                local player = getSpecificPlayer(index)
                if player ~= nil then list[#list + 1] = player end
            end
        end
    end)
    return list
end

function Presence.nearestVisible(shell, radius)
    local best, bestDistance = nil, radius
    local sx, sy, sz
    pcall(function() sx, sy, sz = shell:getX(), shell:getY(), shell:getZ() end)
    if sx == nil then return nil end
    for _, player in ipairs(Presence.players()) do
        local ok, px, py, pz, dead = pcall(function() return player:getX(), player:getY(), player:getZ(), player:isDead() end)
        if ok and not dead and math.floor(pz) == math.floor(sz) then
            local d = math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2)
            if d <= bestDistance then
                local careful = ProjectALife.ModuleCareful
                local seen = careful == nil or type(careful.lineOfSight) ~= "function" or careful.lineOfSight(shell, player)
                if seen then best, bestDistance = player, d end
            end
        end
    end
    return best, bestDistance
end

function Presence.partyKey(actor, playerKey)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local party = memory.groupId
        or (memory.outpostId ~= nil and ("outpost:" .. tostring(memory.outpostId)))
        or actor.uid
    return tostring(playerKey) .. ":" .. tostring(party)
end

function Presence.playersAt(now)
    local at = Presence.playerListAtMs
    local from = Presence.playersAdapter or getOnlinePlayers
    if at == nil or now < at or now - at >= Presence.settings.playerListMs
            or from ~= Presence.playerListFrom then
        Presence.playerList = Presence.players()
        Presence.playerListAtMs, Presence.playerListFrom = now, from
    end
    return Presence.playerList
end

function Presence.standing(player)
    if type(player) ~= "table" and type(player) ~= "userdata" then return false end
    if type(player.getX) ~= "function" then return false end
    return type(player.isDead) ~= "function" or player:isDead() ~= true
end

function Presence.buildingOf(player)
    if type(player.getBuilding) ~= "function" then return nil end
    local building = player:getBuilding()
    if building == nil or type(building.getID) ~= "function" then return nil end
    return tostring(building:getID())
end

function Presence.courteous(actor, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return false end
    local ok, stance = pcall(relations.playerStance, actor, player)
    return ok == true and stance ~= nil and Presence.courteousStances[stance] == true
end

function Presence.courteousAt(actor, player, now)
    local memo = Presence.memo
    if memo.uid == actor.uid and memo.player == player
            and now >= memo.atMs and now - memo.atMs < Presence.settings.memoMs then
        return memo.courteous
    end
    local answer = Presence.courteous(actor, player)
    memo.uid, memo.player, memo.atMs, memo.courteous = actor.uid, player, now, answer
    return answer
end

function Presence.refused(reason)
    Presence.metrics.leadsRefused = Presence.metrics.leadsRefused + 1
    return true, reason
end

function Presence.refusesLead(actor, shell, lead, now)
    local s = Presence.settings
    if s.courtesy ~= true or type(actor) ~= "table" or type(lead) ~= "table"
            or lead.kind == "contact" then return false end
    local lx, ly = tonumber(lead.x), tonumber(lead.y)
    if lx == nil or ly == nil then return false end
    now = tonumber(now) or nowMs()
    local source = lead.source
    if source ~= nil and Presence.standing(source) and Presence.courteousAt(actor, source, now) then
        return Presence.refused("source")
    end
    local lz = math.floor(tonumber(lead.z) or 0)
    local reach = s.courtesyTiles * s.courtesyTiles
    local building = nil
    if type(lead.key) == "string" and string.sub(lead.key, 1, 2) == "b:" then building = string.sub(lead.key, 3) end
    local list = Presence.playersAt(now)
    for index = 1, #list do
        local player = list[index]
        if player ~= source and Presence.standing(player) then
            local px, py = tonumber(player:getX()), type(player.getY) == "function" and tonumber(player:getY()) or nil
            local pz = type(player.getZ) == "function" and tonumber(player:getZ()) or 0
            local near = px ~= nil and py ~= nil and math.floor(pz or 0) == lz
                and (px - lx) ^ 2 + (py - ly) ^ 2 <= reach
            if (near or (building ~= nil and Presence.buildingOf(player) == building))
                    and Presence.courteousAt(actor, player, now) then
                return Presence.refused(near and "near" or "building")
            end
        end
    end
    return false
end

function Presence.refusesSweep(actor, square, now)
    if square == nil or type(square.getBuilding) ~= "function" then return false end
    local building = square:getBuilding()
    if building == nil or type(building.getID) ~= "function" then return false end
    return Presence.refusesLead(actor, nil, { x = square:getX(), y = square:getY(), z = square:getZ(),
        kind = "sweep", key = "b:" .. tostring(building:getID()) }, now)
end

function Presence.prune(now)
    local at = Presence.prunedAtMs
    if at ~= nil and now >= at and now - at < Presence.settings.pruneEveryMs then return 0 end
    Presence.prunedAtMs = now
    local removed = 0
    for _, stamps in ipairs({ Presence.greeted, Presence.passed, Presence.spotted, Presence.stared, Presence.nextCheckAt }) do
        for key, untilMs in pairs(stamps) do
            if untilMs <= now then stamps[key] = nil; removed = removed + 1 end
        end
    end
    for party, fight in pairs(Presence.fights) do
        if now - fight.seenAtMs > Presence.settings.coopGapMs then Presence.fights[party] = nil; removed = removed + 1 end
    end
    local gap = Presence.settings.checkMs * 3
    for key, entry in pairs(Presence.lingering) do
        if now - entry.seen > gap then Presence.lingering[key] = nil; removed = removed + 1 end
    end
    return removed
end

function Presence.stare(actor, shell, player, key, distance, now, speechContext, party)
    local s = Presence.settings
    local entry = Presence.lingering[key]
    if distance > s.stareRadius then Presence.lingering[key] = nil; return end
    if entry == nil or now - entry.seen > s.checkMs * 3 then
        Presence.lingering[key] = { since = now, seen = now }
        return
    end
    entry.seen = now
    local once = party or key
    if now - entry.since < s.stareAfterMs or now < (Presence.stared[once] or 0) then return end
    Presence.stared[once] = now + s.stareCooldownMs
    Presence.lingering[key] = nil
    local talk = ProjectALife.Talk
    local said = talk.bark(actor, shell, player, "STARE_PLAYER", speechContext)
    if said ~= nil then
        Presence.metrics.stares = Presence.metrics.stares + 1
        if type(talk.awaitAnswer) == "function" then talk.awaitAnswer(actor, player, said, now) end
    end
end

function Presence.fighting(talk, actor, now)
    if type(talk.inFight) == "function" then return talk.inFight(actor, now) == true end
    return talk.inCombat(actor) == true
end

function Presence.coopInFight(actor, shell, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local party = tostring(memory.groupId or memory.outpostId or actor.uid)
    local fight = Presence.fights[party]
    if fight == nil or now < fight.seenAtMs or now - fight.seenAtMs > Presence.settings.coopGapMs then
        fight = { seenAtMs = now, said = false }
        Presence.fights[party] = fight
    end
    fight.seenAtMs = now
    if fight.said then return false end
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    if type(talk.coopLine) ~= "function" or speech == nil then return false end
    local player = Presence.nearestVisible(shell, Presence.settings.greetRadius)
    if player == nil or talk.stance(actor, player) ~= "neutral" then return false end
    if not speech.say(shell, talk.coopLine(), {}) then return false end
    fight.said = true
    Presence.metrics.coop = (Presence.metrics.coop or 0) + 1
    return true
end

function Presence.holdPlayer(shell, playerKey, talk, record)
    if playerKey == nil or shell == nil or type(shell.getX) ~= "function"
            or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function" then return nil end
    local speech = ProjectALife.Speech
    for _, player in ipairs(Presence.players()) do
        if speech.playerKey(player) == playerKey and speech.alive(player)
                and type(player.getX) == "function" and type(player.getY) == "function"
                and type(player.getZ) == "function"
                and math.floor(player:getZ()) == math.floor(shell:getZ())
                and (player:getX() - shell:getX()) ^ 2 + (player:getY() - shell:getY()) ^ 2 <= talk.settings.listenRadius ^ 2
                and talk.lineOfSight(player, shell, record) then return player end
    end
    return nil
end

function Presence.evaluate(actor, shell, context)
    if not Registry.allows(actor, "talk") then return nil end
    local now = tonumber(context and context.now) or nowMs()
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local talk = ProjectALife.Talk
    if talk == nil then return nil end

    local eligible = ProjectALife.Speech.talkable(shell, actor, now) == true
    if not eligible or (type(talk.busy) == "function" and talk.busy(actor, now)) then
        if type(talk.releaseHold) == "function" then talk.releaseHold(actor.uid, memory.talkHoldPlayerKey) end
        if memory.gossipHoldUntilMs ~= nil and type(talk.writeMemory) == "function" then
            talk.writeMemory(actor.uid, function(m) m.gossipHoldUntilMs, m.gossipToken, m.gossipFaceUid = nil, nil, nil end)
        end
        if eligible and Presence.fighting(talk, actor, now) then Presence.coopInFight(actor, shell, now) end
        return nil
    end

    local heldPlayer = nil
    if memory.talkHoldPlayerKey ~= nil then
        if (tonumber(memory.talkHoldUntilMs) or 0) > now then
            heldPlayer = Presence.holdPlayer(shell, memory.talkHoldPlayerKey, talk, actor)
        end
        if heldPlayer == nil and type(talk.releaseHold) == "function" then
            talk.releaseHold(actor.uid, memory.talkHoldPlayerKey)
        end
    end

    if heldPlayer ~= nil and not talk.inCombat(actor)
            and not (ProjectALife.Relations ~= nil and type(ProjectALife.Relations.playerStance) == "function"
                and memory.talkHoldPlayerKey ~= nil
                and ProjectALife.Relations.playerStance(actor, memory.talkHoldPlayerKey) == "careful") then
        ProjectALife.Speech.face(shell, heldPlayer)
        Presence.metrics.holds = Presence.metrics.holds + 1
        return { kind = "idle", intent = "talk_hold", cooldownUntilMs = math.min(tonumber(memory.talkHoldUntilMs), now + 100) }
    end
    if Presence.settings.enabled ~= true or talk.settings.enabled ~= true then return nil end
    if (tonumber(memory.gossipHoldUntilMs) or 0) > now and type(talk.writeMemory) == "function" then
        local caution = ProjectALife.Caution
        if caution ~= nil and type(caution.idleDanger) == "function" and caution.idleDanger(actor, shell, now) ~= nil then
            talk.writeMemory(actor.uid, function(m) m.gossipHoldUntilMs, m.gossipToken, m.gossipFaceUid = nil, nil, nil end)
            return nil
        end
    end
    if (tonumber(memory.gossipHoldUntilMs) or 0) > now and not talk.inCombat(actor) then
        local gossip = ProjectALife.Gossip
        local live = gossip ~= nil and type(gossip.liveFace) == "function"
            and gossip.liveFace(actor.uid, memory.gossipToken) or nil
        local faceUid = live or memory.gossipFaceUid
        local other = faceUid and talk.shellFor(faceUid) or nil
        if other ~= nil then
            ProjectALife.Speech.face(shell, other)
            local animations = ProjectALife.Animations
            if gossip ~= nil and animations ~= nil and type(gossip.gestureCue) == "function"
                    and type(animations.apply) == "function" then
                local cue = gossip.gestureCue(actor.uid, memory.gossipToken, shell, now)
                if cue ~= nil then pcall(animations.apply, shell, cue) end
            end
        end
        return { kind = "idle", intent = "gossip_meeting", cooldownUntilMs = now + 500 }
    elseif memory.gossipToken ~= nil and type(talk.writeMemory) == "function" then
        talk.writeMemory(actor.uid, function(m)
            if (tonumber(m.gossipHoldUntilMs) or 0) <= now then
                m.gossipHoldUntilMs, m.gossipFaceUid, m.gossipToken = nil, nil, nil
            end
        end)
    end
    if now < (Presence.nextCheckAt[actor.uid] or 0) then return nil end
    Presence.prune(now)
    Presence.nextCheckAt[actor.uid] = now + Presence.settings.checkMs
    if Presence.fighting(talk, actor, now) then
        Presence.coopInFight(actor, shell, now)
        return nil
    end

    local player, distance = Presence.nearestVisible(shell, Presence.settings.spotRadius)
    if player == nil then return nil end
    local Speech = ProjectALife.Speech
    local playerKey = Speech.playerKey(player)
    local stance = talk.stance(actor, player)
    local speechContext = Speech.contextFor(actor, player)
    speechContext.stance = stance

    if stance == "hostile" then
        if not Presence.spotRegisters[speechContext.register] then return nil end
        local group = tostring(memory.groupId or memory.outpostId or actor.uid) .. ":" .. tostring(playerKey)
        if now < (Presence.spotted[group] or 0) then return nil end
        local robbery = ProjectALife.ModuleRobbery
        if robbery ~= nil and type(robbery.activeFor) == "function" and robbery.activeFor(actor, playerKey) then return nil end
        Presence.spotted[group] = now + Presence.settings.spotCooldownMs
        if talk.bark(actor, shell, player, "SPOT_STRANGER", speechContext) ~= nil then
            Presence.metrics.spots = Presence.metrics.spots + 1
            local script = ProjectALife.EncounterScript
            if script ~= nil then script.noteSpot(actor, playerKey, now) end
            local fair = ProjectALife.Fairness
            if fair ~= nil and type(fair.noteSpotted) == "function" then fair.noteSpotted(actor, player, now) end
        end
        return nil
    end
    if stance ~= "friendly" and stance ~= "neutral" then return nil end

    local key = tostring(playerKey) .. ":" .. actor.uid
    local party = Presence.partyKey(actor, playerKey)
    if distance <= Presence.settings.greetRadius and actor.activity ~= "scavenging" then
        if now < (Presence.greeted[party] or 0) or now < (Presence.greeted[key] or 0) then
            Presence.stare(actor, shell, player, key, distance, now, speechContext, party)
            return nil
        end
        local said = talk.bark(actor, shell, player, "GREET_PLAYER", speechContext)
        if said ~= nil then
            Presence.greeted[party] = now + Presence.settings.greetCooldownMs
            Presence.metrics.greets = Presence.metrics.greets + 1
            if type(talk.awaitAnswer) == "function" then talk.awaitAnswer(actor, player, said, now) end
        else

            Presence.greeted[key] = now + Presence.settings.greetCooldownMs
        end
        return nil 
    end
    if stance == "friendly" and actor.activity == "moving" and distance <= Presence.settings.passRadius then
        local group = tostring(memory.groupId or actor.uid) .. ":" .. tostring(playerKey)
        if now < (Presence.passed[group] or 0) then return nil end
        Presence.passed[group] = now + Presence.settings.passCooldownMs
        if roll(100) < Presence.settings.passChance
                and talk.bark(actor, shell, player, "PASSING_PLAYER", speechContext) ~= nil then
            Presence.metrics.passes = Presence.metrics.passes + 1
        end
    end
    return nil
end

function Presence.reset()
    Presence.nextCheckAt, Presence.greeted, Presence.passed, Presence.spotted = {}, {}, {}, {}
    Presence.lingering, Presence.stared, Presence.fights = {}, {}, {}
    Presence.playerList, Presence.playerListAtMs, Presence.playerListFrom, Presence.prunedAtMs = {}, nil, nil, nil
    Presence.memo = { uid = nil, player = nil, atMs = 0, courteous = false }
    Presence.metrics = { holds = 0, greets = 0, passes = 0, spots = 0, stares = 0, leadsRefused = 0 }
end

Registry.register({
    id = "talk",
    kind = "orders",
    dispatch = "decision",

    priority = 4,
    label = "Talk and presence",
    summary = "Answers a player who talks, greets without stopping, says a word when passing, and calls out a stranger when it is an outlaw crew.",
    defaultEnabled = true,
    evaluate = Presence.evaluate,
})

return Presence
