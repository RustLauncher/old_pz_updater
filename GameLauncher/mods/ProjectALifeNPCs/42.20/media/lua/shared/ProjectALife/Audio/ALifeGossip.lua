ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Talk/ALifeSpeech"

local Gossip = {
    settings = {
        groupBarkGapMs = 7500,
        globalBarkGapMs = 2200,
        textOnlyBeatMs = 2200,
        turnWatchdogMs = 20000,
        firstSightMinMs = 10000,
        firstSightRangeMs = 15000,
        ambientRefundMs = 30000,
    },
    registry = {},
    scenes = {},
    active = {},
    globalActive = {},
    cooldowns = {},
    globalCooldown = { ambient = 0, combat = 0 },
    barkCooldown = {},
    globalBarkAt = 0,
    armedAt = {},
    playedScenes = {},
    playbacks = {},
    playbackByContext = {},
    seenTokens = {},
    sequence = 0,
    adapters = {},
    metrics = { starts = 0, preemptions = 0, missingParticipants = 0, meet = {} },
    meetNextAt = {},
    meetSeen = {},
    meetPairAt = {},
    meetGlobalAt = 0,
    meetSettings = {
        radius = 8,
        probeMinMs = 2500,
        probeSpreadMs = 1500,
        dwellMs = 4000,
        cooldownMs = 360000,
        cooldownSpreadMs = 240000,
        pairCooldownMs = 900000,
        globalGapMs = 20000,
        stayMs = 75000,
        walkMs = 40000,
        walkTiles = 10,
        maxMembers = 24,
        seenKeepMs = 15000,
    },
    meetClass = { civilian = "civ", family = "civ", worker = "civ", rescue = "res", law = "law",
        swat = "law", military = "mil", elite = "mil" },
    meetStances = { friendly = true, neutral = true, careful = true },
}
ProjectALife.Gossip = Gossip

local function nowMs()
    if type(Gossip.adapters.nowMs) == "function" then
        return math.floor(tonumber(Gossip.adapters.nowMs()) or 0)
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function stableNumber(value)
    local result, text = 0, tostring(value or "")
    for index = 1, #text do
        result = (result * 33 + string.byte(text, index)) % 2147483647
    end
    return result
end

function Gossip.stableIndex(token, maximum)
    maximum = math.floor(tonumber(maximum) or 0)
    if maximum < 1 then return nil end
    return stableNumber(token) % maximum + 1
end

local function cleanId(value)
    if type(value) ~= "string" then return nil end
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    if value == "" or #value > 96 or string.find(value, "[%c,]") then return nil end
    return value
end

local function copyTurn(turn)
    return {
        event = turn.event,
        sound = turn.sound,
        text = turn.text,
        duration = tonumber(turn.duration),
        textOnly = turn.textOnly == true,

        slot = tonumber(turn.slot),
    }
end

function Gossip.validate(id, turns, options)
    id, options = cleanId(id), options or {}
    if id == nil then return nil, "gossip_id_invalid" end
    if type(turns) ~= "table" or #turns < 1 then
        return nil, "gossip_turns_empty"
    end
    local context = tostring(options.context or "ambient")
    if context ~= "ambient" and context ~= "combat" then
        return nil, "gossip_context_invalid"
    end
    local normalized = {}
    for index, turn in ipairs(turns) do
        if type(turn) ~= "table" or tonumber(turn.duration) == nil
                or tonumber(turn.duration) <= 0 then
            return nil, "gossip_turn_duration_invalid:" .. tostring(index)
        end
        local event = cleanId(turn.event)
        local sound = cleanId(turn.sound)
        local text = type(turn.text) == "string" and turn.text or nil
        local textOnly = turn.textOnly == true
        if textOnly and (text == nil or string.match(text, "^%s*$")) then
            return nil, "gossip_text_only_empty:" .. tostring(index)
        end
        if not textOnly and event == nil and sound == nil then
            return nil, "gossip_turn_source_missing:" .. tostring(index)
        end
        if event ~= nil and sound ~= nil then
            return nil, "gossip_turn_source_ambiguous:" .. tostring(index)
        end
        local catalog = ProjectALife.VoiceCatalog
        if event ~= nil and catalog ~= nil
                and type(catalog.resolveEvent) == "function"
                and catalog.resolveEvent(event) == nil then
            return nil, "gossip_event_unknown:" .. tostring(index)
        end
        normalized[index] = copyTurn({
            event = event, sound = sound, text = text,
            duration = tonumber(turn.duration), textOnly = textOnly, slot = turn.slot,
        })
    end

    local minimum = math.max(options.allowSolo == true and 1 or 2,
        math.floor(tonumber(options.minParticipants) or 3))
    return {
        id = id,
        corpus = options.corpus == true,
        turns = normalized,
        context = context,
        topic = tostring(options.topic or "any"),
        gate = type(options.gate) == "string" and options.gate ~= "" and options.gate or nil,
        voiceProfile = tostring(options.voiceProfile or "*"),
        minParticipants = minimum,
        cooldownMin = math.max(0, math.floor(tonumber(options.cooldownMin) or 90000)),
        cooldownRange = math.max(0, math.floor(tonumber(options.cooldownRange) or 150000)),
        globalCooldownMin = math.max(0,
            math.floor(tonumber(options.globalCooldownMin) or 45000)),
        globalCooldownRange = math.max(0,
            math.floor(tonumber(options.globalCooldownRange) or 45000)),
    }
end

function Gossip.register(id, turns, options)
    local scene, reason = Gossip.validate(id, turns, options)
    if scene == nil then return false, reason end
    local previous = Gossip.scenes[scene.id]
    Gossip.scenes[scene.id] = scene
    if previous ~= nil then
        for index, value in ipairs(Gossip.registry) do
            if value.id == scene.id then Gossip.registry[index] = scene; return true, scene end
        end
    end
    Gossip.registry[#Gossip.registry + 1] = scene
    return true, scene
end

function Gossip.sceneIds()
    local result = {}
    for id in pairs(Gossip.scenes) do result[#result + 1] = id end
    table.sort(result)
    return result
end

function Gossip.configure(adapters)
    Gossip.adapters = adapters or {}
end

function Gossip.configureVoice(adapters)
    adapters = adapters or {}
    for _, key in ipairs({
        "nowMs", "showText", "playSound", "stopSound",
        "textEnabled", "audioEnabled", "enabled",
    }) do
        Gossip.adapters[key] = adapters[key]
    end
end

function Gossip.reset()
    Gossip.active = {}
    Gossip.globalActive = {}
    Gossip.cooldowns = {}
    Gossip.globalCooldown = { ambient = 0, combat = 0 }
    Gossip.barkCooldown = {}
    Gossip.globalBarkAt = 0
    Gossip.armedAt = {}
    Gossip.playedScenes = {}
    Gossip.playbacks = {}
    Gossip.playbackByContext = {}
    Gossip.seenTokens = {}
    Gossip.sequence = 0
    Gossip.playedByUid = {}
    Gossip.metrics = { starts = 0, preemptions = 0, missingParticipants = 0, meet = {} }
    Gossip.meetNextAt = {}
    Gossip.meetSeen = {}
    Gossip.meetPairAt = {}
    Gossip.meetGlobalAt = 0
end

local function variable(shell, name)
    if shell == nil then return nil end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and data["Project" .. name] ~= nil then
        return data["Project" .. name]
    end
    local valueOk, value = pcall(function() return shell:GetVariable(name) end)
    return valueOk and value or nil
end

local function alive(shell)
    if not ProjectALife.Speech.alive(shell) then return false end
    if type(Gossip.adapters.shellAlive) == "function" then
        return Gossip.adapters.shellAlive(shell) == true
    end
    if type(shell.getSquare) ~= "function" then return false end
    local squareOk, square = pcall(function() return shell:getSquare() end)
    if not squareOk or square == nil then return false end
    if type(shell.isAlive) ~= "function" then return true end
    local aliveOk, living = pcall(function() return shell:isAlive() end)
    return not aliveOk or living ~= false
end

local function position(shell)
    if type(Gossip.adapters.position) == "function" then
        local value = Gossip.adapters.position(shell)
        if type(value) == "table" then return value end
    end
    local ok, x, y, z = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ()
    end)
    if not ok then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function inCombat(participant, now)
    if type(Gossip.adapters.combatActive) == "function" then
        return Gossip.adapters.combatActive(
            participant.actor, participant.shell, now) == true
    end
    local actor = participant.actor or {}
    local activity, intent = tostring(actor.activity or ""), tostring(actor.intent or "")
    if activity == "combat" or string.find(intent, "attack", 1, true)
            or string.find(intent, "engage", 1, true)
            or string.find(intent, "manhunt", 1, true) then return true end
    if variable(participant.shell, "ALifeCombatActive") == true then return true end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.quietReason) == "function"
            and speech.quietReason(participant.shell, participant.actor, now) ~= nil then return true end

    if participant.actor ~= nil then return false end
    local ok, target = pcall(function() return participant.shell:getTarget() end)
    return ok and target ~= nil
end

local function records()
    if type(Gossip.adapters.records) == "function" then
        return Gossip.adapters.records() or {}
    end
    local registry = ProjectALife.ActorRegistry
    return registry ~= nil and type(registry.list) == "function" and registry.list() or {}
end

local function shellFor(uid)
    if type(Gossip.adapters.shellFor) == "function" then
        return Gossip.adapters.shellFor(uid)
    end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog and watchdog.bindings and watchdog.bindings[uid] or nil
    if binding then return binding.shell end
    return ProjectALife.Talk and ProjectALife.Talk.shellFor(uid) or nil
end

function Gossip.participants(groupId, anchorShell, context)
    groupId = cleanId(tostring(groupId or ""))
    local anchor = position(anchorShell)
    if groupId == nil or anchor == nil then return {} end
    local result = {}
    for _, actor in ipairs(records()) do
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local actorGroup = memory.groupId or (memory.outpostId and ("outpost:" .. tostring(memory.outpostId))) or ""
        if actor.lifecycle == "active" and tostring(actorGroup) == groupId then
            local shell = shellFor(actor.uid)
            local at = alive(shell) and position(shell) or nil
            if at ~= nil and at.x ~= nil and at.y ~= nil and at.z ~= nil then
                local dx, dy = at.x - anchor.x, at.y - anchor.y
                local participant = { uid = tostring(actor.uid), actor = actor, shell = shell }
                if dx * dx + dy * dy <= 64 and math.abs(at.z - anchor.z) <= 1
                        and (context ~= "ambient" or not inCombat(participant, nowMs())) then
                    result[#result + 1] = participant
                end
            end
        end
    end
    table.sort(result, function(left, right) return left.uid < right.uid end)
    return result
end

function Gossip.visitors(shell)
    local result = {}
    local presence = ProjectALife.ModuleTalkPresence
    if presence == nil or type(presence.players) ~= "function" then return result end
    local at = position(shell)
    if at == nil then return result end
    for _, player in ipairs(presence.players()) do
        local spot = position(player)
        if spot ~= nil and not player:isDead() and math.floor(spot.z) == math.floor(at.z)
                and (spot.x - at.x)^2 + (spot.y - at.y)^2 <= 16 then
            local sight = ProjectALife.ModuleCareful
            if sight ~= nil and type(sight.lineOfSight) == "function" and sight.lineOfSight(shell, player) then
                result[#result + 1] = player
            end
        end
    end
    return result
end

local function profileFor(participant, scene)

    if scene.corpus == true then return "corpus" end
    local catalog = ProjectALife.VoiceCatalog
    if catalog == nil then return nil end
    local requested = scene.voiceProfile
    if requested == "*" then
        requested = tostring(variable(participant.shell, "ALifeVoiceProfile") or "")
        if requested == "" then
            requested = variable(participant.shell, "ALifeFemale") == true
                and "calm_female" or "calm_male"
        elseif requested == "*" or requested == "random" then
            local female = variable(participant.shell, "ALifeFemale") == true
            local ids = catalog.shipProfileIds(female, scene.context == "ambient")
            requested = ids[Gossip.stableIndex(participant.uid .. ":voice", #ids)]
        end
    end
    requested = type(requested) == "string" and string.lower(requested) or ""
    local profile = catalog.profiles[requested]
    if profile == nil or profile.shipEnabled == false
            or (scene.context == "ambient" and profile.ambientEligible ~= true) then
        return nil
    end
    return requested
end

local function weightedEntry(entries, token)
    local total = 0
    for _, entry in ipairs(entries or {}) do
        total = total + math.max(1, math.floor(tonumber(entry.weight) or 1))
    end
    if total < 1 then return nil end
    local pick = stableNumber(token) % total + 1
    for _, entry in ipairs(entries) do
        pick = pick - math.max(1, math.floor(tonumber(entry.weight) or 1))
        if pick <= 0 then return entry end
    end
    return entries[#entries]
end

function Gossip.resolveTurn(scene, participants, turnNumber, token)
    local turn = scene and scene.turns and scene.turns[turnNumber] or nil
    if turn == nil or type(participants) ~= "table" or #participants < 1 then
        return nil, "gossip_turn_missing"
    end
    local participant = (turn.slot ~= nil and participants[turn.slot])
        or participants[(turnNumber - 1) % #participants + 1]
    if participant == nil or not alive(participant.shell) then
        return nil, "gossip_participant_missing"
    end
    local profileId = profileFor(participant, scene)
    if profileId == nil then return nil, "gossip_profile_unavailable" end
    if turn.textOnly then
        local text = turn.text
        local speech = ProjectALife.Speech
        if scene.corpus == true and speech ~= nil and type(speech.render) == "function" then
            text = speech.render(text, nil, participant.shell) or text
        end
        return {
            uid = participant.uid, shell = participant.shell, text = text,
            profile = profileId,
            sound = nil, durationMs = math.min(Gossip.settings.turnWatchdogMs,
                math.max(Gossip.settings.textOnlyBeatMs, (tonumber(turn.duration) or 2.2) * 1000)),
            textOnly = true,
        }
    end
    if turn.sound ~= nil then
        return {
            uid = participant.uid, shell = participant.shell,
            profile = profileId,
            text = turn.text, sound = turn.sound,
            durationMs = math.min(Gossip.settings.turnWatchdogMs,
                math.max(1, math.floor(turn.duration * 1000))),
        }
    end
    local catalog = ProjectALife.VoiceCatalog
    local entries = catalog.entries(profileId, turn.event)
    local entry = weightedEntry(entries, tostring(token) .. ":" .. tostring(turnNumber)
        .. ":" .. participant.uid .. ":" .. tostring(turn.event))
    if entry == nil then return nil, "gossip_entry_missing" end
    return {
        uid = participant.uid, shell = participant.shell, profile = profileId,
        event = turn.event, text = entry.text or turn.text
            or catalog.captionFor(profileId, turn.event, entry), sound = entry.sound,
        durationMs = math.min(Gossip.settings.turnWatchdogMs,
            math.max(tonumber(entry.durationMs) or 0,
                math.floor((tonumber(turn.duration) or 2.2) * 1000))),
        textOnly = entry.sound == nil,
    }
end

local function sceneSupports(scene, participants)
    if #participants < scene.minParticipants then return false end
    for _, participant in ipairs(participants) do
        if profileFor(participant, scene) == nil then return false end
    end
    for index, turn in ipairs(scene.turns) do
        if turn.event ~= nil then
            local participant = participants[(index - 1) % #participants + 1]
            local profileId = profileFor(participant, scene)
            if profileId == nil
                    or #ProjectALife.VoiceCatalog.entries(profileId, turn.event) == 0 then
                return false
            end
        end
    end
    return true
end

function Gossip.gateFits(scene, participants)
    if scene.gate == nil then return true end
    local data, speech = ProjectALife.DialogueData, ProjectALife.Speech
    if data == nil or speech == nil or type(speech.contextFor) ~= "function" then return false end
    local gate = data.parseGate(scene.gate)
    for _, participant in ipairs(participants) do
        local ok, context = pcall(speech.contextFor, participant.actor, nil)
        if not ok or type(context) ~= "table" or not data.allows(gate, context) then return false end
    end
    return true
end

function Gossip.selectScene(context, topic, candidates, token, excluded)
    local choices = {}
    for _, scene in ipairs(Gossip.registry) do
        local topicMatches = scene.topic == topic or topic == "any"
            or (scene.topic == "any" and topic ~= "patrol_departure")
        if scene.context == context and topicMatches
                and not (excluded and excluded[scene.id])
                and #candidates >= scene.minParticipants then
            local exact = {}
            for index = 1, math.min(#candidates, #scene.turns, 4) do
                exact[index] = candidates[index]
            end
            if Gossip.gateFits(scene, exact) and sceneSupports(scene, exact) then
                choices[#choices + 1] = { scene = scene, participants = exact }
            end
        end
    end
    if #choices == 0 then return nil, "gossip_scene_unavailable" end
    return choices[Gossip.stableIndex(token, #choices)]
end

Gossip.corpusSettings = { sampleMatches = 24, playedPerUid = 300, soloChance = 100 }
Gossip.playedByUid = {}

function Gossip.corpusScene(sceneId)
    sceneId = tostring(sceneId or "")
    local existing = Gossip.scenes[sceneId]
    if existing ~= nil then return existing end
    if string.sub(sceneId, 1, 7) ~= "corpus:" then return nil end
    local data = ProjectALife.DialogueData
    if data == nil then return nil end
    data.load()
    local source = data.sceneById[string.sub(sceneId, 8)]
    if source == nil then return nil end
    local turns = {}
    for index, turn in ipairs(source.turns) do
        local seconds = math.max(2.2, math.min(9, 1.2 + #tostring(turn.t) * 0.055))
        turns[index] = { text = turn.t, duration = seconds, textOnly = true, slot = turn.s }
    end
    local meet = source.topic == "meet"
    local scene = Gossip.validate(sceneId, turns, {
        corpus = true, allowSolo = true, minParticipants = source.min, topic = source.topic,
        context = "ambient",
        cooldownMin = meet and 60000 or nil, cooldownRange = meet and 60000 or nil,
        globalCooldownMin = meet and 15000 or nil, globalCooldownRange = meet and 15000 or nil,
    })
    if scene == nil then return nil end
    scene.gate = source.g
    Gossip.scenes[sceneId] = scene
    return scene
end

function Gossip.soloParticipant(shell)
    local uid = tostring(variable(shell, "ALifeUID") or "")
    if uid == "" or not alive(shell) then return nil end
    for _, actor in ipairs(records()) do
        if tostring(actor.uid) == uid and actor.lifecycle == "active" then
            local participant = { uid = uid, actor = actor, shell = shell }
            if inCombat(participant, nowMs()) then return nil end
            return participant
        end
    end
    return nil
end

local function playedBy(uid, id)
    local entry = Gossip.playedByUid[uid]
    return entry ~= nil and entry.set[id] == true
end

function Gossip.notePlayed(participants, id)
    for _, participant in ipairs(participants or {}) do
        local entry = Gossip.playedByUid[participant.uid]
        if entry == nil then
            entry = { list = {}, set = {} }
            Gossip.playedByUid[participant.uid] = entry
        end
        if not entry.set[id] then
            entry.list[#entry.list + 1] = id
            entry.set[id] = true
            while #entry.list > Gossip.corpusSettings.playedPerUid do
                entry.set[table.remove(entry.list, 1)] = nil
            end
        end
    end
end

function Gossip.meetNote(name)
    local counts = Gossip.metrics.meet
    if type(counts) ~= "table" then counts = {}; Gossip.metrics.meet = counts end
    counts[name] = (counts[name] or 0) + 1
end

function Gossip.meetLevel()
    if type(Gossip.adapters.meetLevel) == "function" then
        return math.floor(math.max(1, math.min(4, tonumber(Gossip.adapters.meetLevel()) or 3)))
    end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local level = type(vars) == "table" and tonumber(vars.Talk_GroupMeetings) or 3
    return math.floor(math.max(1, math.min(4, level)))
end

function Gossip.meetScale()
    return ({ 1, 2.5, 1, 0.5 })[Gossip.meetLevel()] or 1
end

function Gossip.groupKey(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    if memory.groupId ~= nil and memory.groupId ~= "" then return tostring(memory.groupId) end
    if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
    return "solo:" .. tostring(type(actor) == "table" and actor.uid or "")
end

function Gossip.canonicalGroup(shell, groupId)
    local uid = variable(shell, "ALifeUID")
    local registry = ProjectALife.ActorRegistry
    if uid == nil or registry == nil or type(registry.peek) ~= "function" then return groupId end
    local actor = registry.peek(tostring(uid))
    if type(actor) ~= "table" or type(actor.memory) ~= "table" then return groupId end
    local memory = actor.memory
    local raw = memory.groupId ~= nil and memory.groupId ~= "" and tostring(memory.groupId) or nil
    local matches = raw ~= nil and (raw == groupId or "group:" .. raw == groupId)
        or memory.outpostId ~= nil and "outpost:" .. tostring(memory.outpostId) == groupId
    if not matches then return groupId end
    return cleanId(Gossip.groupKey(actor)) or groupId
end

function Gossip.registerOf(participant)
    if participant.register ~= nil then return participant.register ~= "" and participant.register or nil end
    local speech = ProjectALife.Speech
    local register = ""
    if speech ~= nil and type(speech.contextFor) == "function" and participant.actor ~= nil then
        local ok, context = pcall(speech.contextFor, participant.actor, nil)
        if ok and type(context) == "table" and context.register ~= nil then register = tostring(context.register) end
    end
    participant.register = register
    return register ~= "" and register or nil
end

function Gossip.meetEligible(participant, now)
    local actor = participant.actor
    if type(actor) ~= "table" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if now < (tonumber(memory.talkHoldUntilMs) or 0) or now < (tonumber(memory.gossipHoldUntilMs) or 0) then return false end
    if memory.orderedTo ~= nil or memory.robbery ~= nil or memory.visit ~= nil or memory.guest ~= nil then return false end
    local register = Gossip.registerOf(participant)
    if register ~= nil and Gossip.meetClass[register] == nil then return false end
    local fear = ProjectALife.ModuleFear
    local record = fear ~= nil and type(fear.actors) == "table" and fear.actors[actor.uid] or nil
    if type(record) == "table" and record.flight ~= nil then return false end
    local decisions = ProjectALife.DecisionLoop
    local order = decisions ~= nil and type(decisions.orders) == "table" and decisions.orders[actor.uid] or nil
    if type(order) == "table" and order.source ~= "leader" and order.generation == actor.generation
            and (order.untilMs == nil or now < order.untilMs) then return false end
    return true
end

function Gossip.meetCalm(chosen, now)
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.scan) ~= "function" then return true end
    for _, participant in ipairs(chosen) do
        if participant.shell ~= nil and participant.actor ~= nil then
            local ok, scan = pcall(fear.scan, participant.actor, participant.shell, now)
            if ok and type(scan) == "table" and ((tonumber(scan.chasers) or 0) > 0 or (tonumber(scan.weight) or 0) >= 1) then
                return false
            end
        end
    end
    return true
end

Gossip.meetScanCap = 96

function Gossip.meetingCandidates(groupId, anchorShell, candidates, now)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.status) ~= "function" then return candidates end
    local anchor
    for _, item in ipairs(candidates) do if item.shell == anchorShell then anchor = item; break end end
    if anchor == nil or anchor.actor == nil or now < (tonumber((anchor.actor.memory or {}).talkHoldUntilMs) or 0) then return candidates end
    local at = position(anchorShell)
    if at == nil then return candidates end
    if not Gossip.meetEligible(anchor, now) then return candidates end
    local sight = ProjectALife.ModuleCareful
    if sight == nil or type(sight.lineOfSight) ~= "function" then return candidates end
    local settings = Gossip.meetSettings
    local radius2 = settings.radius * settings.radius
    local groups = {}
    local reach2 = (settings.radius + 12) * (settings.radius + 12)
    local examined = 0
    for _, actor in ipairs(records()) do
        local rough = actor.worldPosition
        local near = actor.lifecycle == "active"
        if near and type(rough) == "table" and tonumber(rough.x) ~= nil and tonumber(rough.y) ~= nil then
            near = (rough.x - at.x) ^ 2 + (rough.y - at.y) ^ 2 <= reach2
        end
        if near then examined = examined + 1 end
        if examined > Gossip.meetScanCap then break end
        local memory = near and actor.memory or {}
        local key = near and Gossip.groupKey(actor) or nil
        if near and key ~= groupId and Gossip.active[key] == nil
                and now >= Gossip.cooldownAt(key, "meet") and now >= (Gossip.meetPairAt[Gossip.pairKey(groupId, key)] or 0)
                and now >= (tonumber(memory.talkHoldUntilMs) or 0) and now >= (tonumber(memory.gossipHoldUntilMs) or 0) then
            local left, right = relations.status(anchor.actor, actor), relations.status(actor, anchor.actor)
            if Gossip.meetStances[left] and Gossip.meetStances[right] then
                local shell = shellFor(actor.uid)
                local spot = alive(shell) and position(shell) or nil
                if spot ~= nil and spot.x ~= nil and math.floor(spot.z) == math.floor(at.z) then
                    local d2 = (spot.x - at.x) ^ 2 + (spot.y - at.y) ^ 2
                    if d2 <= radius2 then
                        local list = groups[key]
                        if list == nil then list = { key = key, d2 = d2 }; groups[key] = list end
                        list[#list + 1] = { uid = tostring(actor.uid), actor = actor, shell = shell, d2 = d2 }
                        if d2 < list.d2 then list.d2 = d2 end
                    end
                end
            end
        end
    end
    local ordered = {}
    for _, list in pairs(groups) do ordered[#ordered + 1] = list end
    table.sort(ordered, function(a, b) if a.d2 ~= b.d2 then return a.d2 < b.d2 end return a.key < b.key end)
    local chosen = { anchor }
    for _, list in ipairs(ordered) do
        if #chosen >= 3 then break end
        table.sort(list, function(a, b) if a.d2 ~= b.d2 then return a.d2 < b.d2 end return a.uid < b.uid end)
        local picked
        for index = 1, math.min(#list, 3) do
            local participant = list[index]
            if not inCombat(participant, now) and Gossip.meetEligible(participant, now)
                    and sight.lineOfSight(anchorShell, participant.shell) then
                picked = participant
                break
            end
        end
        if picked ~= nil then
            local fine = true
            for index = 2, #chosen do
                local a, b = relations.status(chosen[index].actor, picked.actor), relations.status(picked.actor, chosen[index].actor)
                if not (Gossip.meetStances[a] and Gossip.meetStances[b]) then fine = false; break end
            end
            if fine then chosen[#chosen + 1] = picked end
        end
    end
    if #chosen < 2 then return candidates end
    if not Gossip.meetCalm(chosen, now) then
        Gossip.meetNote("fear")
        return candidates
    end
    chosen.meeting = true
    return chosen
end

function Gossip.pairKey(left, right)
    if left < right then return left .. "|" .. right end
    return right .. "|" .. left
end

function Gossip.meetKey(candidates)
    local keys = {}
    for index, participant in ipairs(candidates) do keys[index] = Gossip.groupKey(participant.actor) end
    table.sort(keys)
    return table.concat(keys, "|")
end

function Gossip.meetingReady(candidates, now)
    local key = Gossip.meetKey(candidates)
    local settings = Gossip.meetSettings
    for seenKey, at in pairs(Gossip.meetSeen) do
        if now - at.lastMs > settings.seenKeepMs then Gossip.meetSeen[seenKey] = nil end
    end
    local seen = Gossip.meetSeen[key]
    if seen == nil then
        Gossip.meetSeen[key] = { firstMs = now, lastMs = now }
        return false, "meeting_dwell"
    end
    seen.lastMs = now
    if now - seen.firstMs < settings.dwellMs then return false, "meeting_dwell" end
    return true
end

function Gossip.releaseMeeting(state, keepSlot)
    local talk = ProjectALife.Talk
    if not state.meeting or talk == nil then return end
    for _, participant in ipairs(state.meetingMembers or state.participants) do
        if keepSlot == nil or participant.slot ~= keepSlot then
            talk.writeMemory(participant.uid, function(memory)
                if memory.gossipToken == state.token then
                    memory.gossipHoldUntilMs, memory.gossipFaceUid, memory.gossipToken = nil, nil, nil
                end
            end)
        end
    end
end

function Gossip.meetingMembers(state, now)
    local members, seen = {}, {}
    local count = #state.participants
    local sight = ProjectALife.ModuleCareful
    local limit = Gossip.meetSettings.maxMembers
    for index, speaker in ipairs(state.participants) do
        local other = state.participants[index % count + 1]
        local group = tostring((speaker.actor.memory or {}).groupId or "")
        local list = group ~= "" and Gossip.participants(group, speaker.shell, "ambient") or {}
        list[#list + 1] = speaker
        for _, participant in ipairs(list) do
            local memory, at, origin = participant.actor.memory or {}, position(participant.shell), position(speaker.shell)
            if not seen[participant.uid] and #members < limit and at and origin and math.floor(at.z) == math.floor(origin.z)
                    and now >= (tonumber(memory.talkHoldUntilMs) or 0)
                    and (participant.uid == speaker.uid
                        or (sight ~= nil and type(sight.lineOfSight) == "function"
                            and sight.lineOfSight(participant.shell, other.shell))) then
                seen[participant.uid] = true
                participant.faceUid = other.uid
                participant.slot = index
                members[#members + 1] = participant
            end
        end
    end
    return members
end

function Gossip.meetSlotAllows(source, slot, context)
    local want = source.g["x" .. tostring(slot)]
    if want ~= nil and context.sex ~= want then return false end
    local list = source.g["r" .. tostring(slot)]
    if list == nil then return true end
    return context.register ~= nil and list[context.register] == true
end

Gossip.meetOrders = {
    { 1, 2 }, { 2, 1 },
    { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 },
}

function Gossip.meetFit(source, subset, candidates, contexts, excluded)
    local id = "corpus:" .. source.id
    if source.min ~= #subset or (excluded and excluded[id]) then return nil end
    local data = ProjectALife.DialogueData
    for _, order in ipairs(Gossip.meetOrders) do
        if #order == #subset then
            local fits = true
            local result = {}
            for slot = 1, #order do
                local index = subset[order[slot]]
                local context = contexts[index]
                if context == nil or not data.allows(source.g, context) or not Gossip.meetSlotAllows(source, slot, context)
                        or playedBy(candidates[index].uid, id) then
                    fits = false
                    break
                end
                result[slot] = candidates[index]
            end
            if fits then return result end
        end
    end
    return nil
end

function Gossip.selectMeeting(candidates, token, excluded)
    local data, speech = ProjectALife.DialogueData, ProjectALife.Speech
    if data == nil or speech == nil then return nil, "gossip_corpus_unavailable" end
    data.load()
    local pool = data.scenesByTopic.meet
    if pool == nil or #pool == 0 then return nil, "gossip_corpus_empty" end
    local contexts = {}
    for index = 1, #candidates do
        local ok, context = pcall(speech.contextFor, candidates[index].actor, nil)
        contexts[index] = ok and context or nil
    end
    local subsets = { #candidates == 3 and { 1, 2, 3 } or { 1, 2 } }
    if #candidates == 3 then subsets[2], subsets[3], subsets[4] = { 1, 2 }, { 1, 3 }, { 2, 3 } end
    local start = stableNumber(token .. ":meet") % #pool
    for _, subset in ipairs(subsets) do
        for _, specific in ipairs({ true, false }) do
            local matches = {}
            for step = 0, #pool - 1 do
                local source = pool[(start + step) % #pool + 1]
                local slotted = source.g.r1 ~= nil or source.g.r2 ~= nil or source.g.r3 ~= nil
                if slotted == specific then
                    local order = Gossip.meetFit(source, subset, candidates, contexts, excluded)
                    if order ~= nil then
                        matches[#matches + 1] = { source = source, participants = order }
                        if #matches >= Gossip.corpusSettings.sampleMatches then break end
                    end
                end
            end
            if #matches > 0 then
                local pick = matches[Gossip.stableIndex(token, #matches)]
                local scene = Gossip.corpusScene("corpus:" .. pick.source.id)
                if scene ~= nil then return { scene = scene, participants = pick.participants } end
            end
        end
    end
    return nil, "gossip_meeting_unmatched"
end

function Gossip.finishMeeting(state, now)
    if not state.meeting then return end
    local settings = Gossip.meetSettings
    local scale = Gossip.meetScale()
    local outcome = state.outcome or "part"
    local keep = tonumber(string.match(outcome, "^stay(%d)$"))
    if keep ~= nil and state.participants[keep] == nil then keep, outcome = nil, "part" end
    Gossip.releaseMeeting(state, keep)
    if keep ~= nil then
        local talk = ProjectALife.Talk
        if talk ~= nil then
            for _, participant in ipairs(state.meetingMembers or {}) do
                if participant.slot == keep then
                    talk.writeMemory(participant.uid, function(memory)
                        if memory.gossipToken == state.token then
                            memory.gossipHoldUntilMs = now + settings.stayMs
                        end
                    end)
                end
            end
        end
        Gossip.meetNote("stays")
    elseif outcome == "walk" then
        Gossip.walkTogether(state, now)
        Gossip.meetNote("walks")
    else
        Gossip.meetNote("parts")
    end
    local groups = {}
    for _, participant in ipairs(state.meetingMembers or state.participants) do
        local key = Gossip.groupKey(participant.actor)
        if not groups[key] then
            groups[key] = true
            Gossip.setCooldown(key, "meet", now + (settings.cooldownMs
                + stableNumber(state.token .. ":" .. key) % math.max(1, settings.cooldownSpreadMs)) * scale)
        end
    end
end

function Gossip.walkTogether(state, now)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.setOrder) ~= "function" or type(getCell) ~= "function" then return false end
    local first = position(state.participants[1].shell)
    if first == nil or first.x == nil then return false end
    local sx, sy, sz, count = 0, 0, first.z, 0
    for _, speaker in ipairs(state.participants) do
        local spot = position(speaker.shell)
        if spot ~= nil and spot.x ~= nil then sx, sy, count = sx + spot.x, sy + spot.y, count + 1 end
    end
    if count == 0 then return false end
    sx, sy = sx / count, sy / count
    local tiles = Gossip.meetSettings.walkTiles
    local turn = ZombRand(8)
    local cell = getCell()
    if cell == nil then return false end
    local anchor
    for step = 0, 7 do
        local angle = ((turn + step) % 8) * math.pi / 4
        local x, y = math.floor(sx + math.cos(angle) * tiles), math.floor(sy + math.sin(angle) * tiles)
        local square = cell:getGridSquare(x, y, math.floor(sz))
        if square ~= nil and type(square.isFree) == "function" and square:isFree(false) then
            anchor = { x = x + 0.5, y = y + 0.5, z = math.floor(sz) }
            break
        end
    end
    if anchor == nil then return false end
    for _, participant in ipairs(state.meetingMembers or {}) do
        local actor = participant.actor
        if type(actor) == "table" and actor.generation ~= nil then
            pcall(decisions.setOrder, participant.uid, actor.generation, { kind = "patrol", anchor = anchor,
                untilMs = now + Gossip.meetSettings.walkMs, source = "leader", quiet = true })
        end
    end
    return true
end

function Gossip.probeMeeting(shell, options)
    options = options or {}
    local level = Gossip.meetLevel()
    if level <= 1 or Gossip.adapters.enabled == false or shell == nil then return false, "meeting_off" end
    if type(isClient) == "function" and isClient()
            and (type(isServer) ~= "function" or not isServer()) then
        return false, "gossip_server_authority_required"
    end
    local groupId = cleanId(tostring(options.groupId or variable(shell, "ALifeGroupId") or ""))
    if groupId == nil then return false, "gossip_group_invalid" end
    groupId = Gossip.canonicalGroup(shell, groupId)
    local now = math.floor(tonumber(options.now) or nowMs())
    if now < (Gossip.meetNextAt[groupId] or 0) then return false, "meeting_waiting" end
    local settings = Gossip.meetSettings
    Gossip.meetNextAt[groupId] = now + settings.probeMinMs
        + stableNumber(groupId .. ":" .. tostring(math.floor(now / 1000))) % math.max(1, settings.probeSpreadMs)
    Gossip.meetNote("scans")
    if options.blocked == true then Gossip.meetNote("blocked"); return false, "meeting_blocked" end
    if Gossip.active[groupId] ~= nil or Gossip.globalActive.ambient ~= nil then
        Gossip.meetNote("busy")
        return false, "gossip_context_busy"
    end
    if now < Gossip.cooldownAt(groupId, "meet") or now < Gossip.meetGlobalAt then
        Gossip.meetNote("cooldown")
        return false, "gossip_group_cooldown"
    end
    return Gossip.tryStart(shell, { context = "ambient", topic = "meet", groupId = groupId, now = now,
        meetingOnly = true })
end

Gossip.topicFallback = { rest = "any", scavenge = "any", after_fight = "any", checkpoint = "outpost_guard" }

function Gossip.selectCorpus(context, topic, candidates, token, excluded)
    local selected, reason = Gossip.selectCorpusTopic(context, topic, candidates, token, excluded)
    local fallback = Gossip.topicFallback[topic]
    if selected == nil and fallback ~= nil and reason ~= "gossip_corpus_unavailable" then
        return Gossip.selectCorpusTopic(context, fallback, candidates, token, excluded)
    end
    return selected, reason
end

function Gossip.selectCorpusTopic(context, topic, candidates, token, excluded)
    local data, speech = ProjectALife.DialogueData, ProjectALife.Speech
    if context ~= "ambient" or #candidates == 0 or data == nil or speech == nil then
        return nil, "gossip_corpus_unavailable"
    end
    data.load()
    local pool = data.scenesByTopic[topic]
    if topic == "any" or pool == nil or #pool == 0 then pool = data.scenesByTopic.any end
    if pool == nil or #pool == 0 then return nil, "gossip_corpus_empty" end
    local contexts = {}
    for index = 1, math.min(#candidates, 4) do
        local actor = candidates[index].actor
        contexts[index] = actor ~= nil and speech.contextFor(actor, nil) or nil
    end
    local matches = {}
    local start = stableNumber(token .. ":corpus") % #pool
    for step = 0, #pool - 1 do
        local source = pool[(start + step) % #pool + 1]
        local id = "corpus:" .. source.id
        local fits = source.min <= #candidates and (not candidates.meeting or source.min >= 2)
            and not (excluded and excluded[id])
        if fits then
            for index = 1, source.min do
                if contexts[index] == nil or not data.allows(source.g, contexts[index])
                        or playedBy(candidates[index].uid, id) then
                    fits = false
                    break
                end
            end
        end
        if fits then
            matches[#matches + 1] = source
            if #matches >= Gossip.corpusSettings.sampleMatches then break end
        end
    end
    if #matches == 0 then return nil, "gossip_corpus_unmatched" end
    local source = matches[Gossip.stableIndex(token, #matches)]
    local scene = Gossip.corpusScene("corpus:" .. source.id)
    if scene == nil then return nil, "gossip_corpus_invalid" end
    local exact = {}
    for index = 1, source.min do exact[index] = candidates[index] end
    return { scene = scene, participants = exact }
end

function Gossip.cooldownAt(groupId, context)
    local value = Gossip.cooldowns[groupId]
    return type(value) == "table" and tonumber(value[context]) or 0
end

function Gossip.setCooldown(groupId, context, expiresAt)
    local value = Gossip.cooldowns[groupId]
    if type(value) ~= "table" then value = {}; Gossip.cooldowns[groupId] = value end
    value[context] = math.floor(tonumber(expiresAt) or 0)
end

function Gossip.allowBark(groupId, suppliedNow)
    groupId = cleanId(tostring(groupId or ""))
    if groupId == nil then return false, "gossip_group_invalid" end
    local now = math.floor(tonumber(suppliedNow) or nowMs())
    if Gossip.active[groupId] ~= nil then return false, "gossip_scene_active" end
    if now < (Gossip.barkCooldown[groupId] or 0) then
        return false, "gossip_group_throttle"
    end
    if now < Gossip.globalBarkAt then return false, "gossip_global_throttle" end
    Gossip.barkCooldown[groupId] = now + Gossip.settings.groupBarkGapMs
    Gossip.globalBarkAt = now + Gossip.settings.globalBarkGapMs
    return true
end

local function broadcast(payload)
    if type(Gossip.adapters.broadcast) == "function" then
        local ok, result = pcall(Gossip.adapters.broadcast, "gossipStart", payload)
        return ok and result ~= false
    end
    if type(isServer) == "function" and isServer()
            and type(sendServerCommand) == "function" then
        local ok = pcall(sendServerCommand, "ProjectALife", "gossipStart", payload)
        return ok
    end
    return Gossip.startAuthoritative(payload) == true
end

local function sceneDuration(scene, participants, token)
    local total = 300
    for index, turn in ipairs(scene.turns) do
        local resolved = Gossip.resolveTurn(scene, participants, index, token)
        local beat = math.min(Gossip.settings.turnWatchdogMs,
            math.max(turn.textOnly and Gossip.settings.textOnlyBeatMs or 1,
                resolved and resolved.durationMs or math.floor(turn.duration * 1000)))
        total = total + beat + 280
    end
    return total
end

local function finishServer(groupId, state, now)
    if state.meeting then Gossip.finishMeeting(state, now) end
    Gossip.active[groupId] = nil
    if Gossip.globalActive[state.scene.context] == groupId then
        Gossip.globalActive[state.scene.context] = nil
    end
    local scene, token = state.scene, state.token
    Gossip.setCooldown(groupId, scene.context, math.max(Gossip.cooldownAt(groupId, scene.context), now + scene.cooldownMin
        + stableNumber(token .. ":group") % math.max(1, scene.cooldownRange + 1)))
    Gossip.globalCooldown[scene.context] = now + scene.globalCooldownMin
        + stableNumber(token .. ":global") % math.max(1, scene.globalCooldownRange + 1)
end

function Gossip.tryStart(shell, options)
    options = options or {}
    if Gossip.adapters.enabled == false or shell == nil then
        return false, "gossip_disabled"
    end
    if type(isClient) == "function" and isClient()
            and (type(isServer) ~= "function" or not isServer()) then
        return false, "gossip_server_authority_required"
    end
    local context = tostring(options.context or "ambient")
    if context ~= "ambient" and context ~= "combat" then
        return false, "gossip_context_invalid"
    end
    local groupId = cleanId(tostring(options.groupId
        or variable(shell, "ALifeGroupId") or ""))
    if groupId == nil then return false, "gossip_group_invalid" end
    groupId = Gossip.canonicalGroup(shell, groupId)
    local now = math.floor(tonumber(options.now) or nowMs())
    Gossip.tickServer(now)
    if context == "combat" then Gossip.preemptCombat(groupId, now) end
    local meetOnly = options.meetingOnly == true and context == "ambient"
    if Gossip.globalActive[context] ~= nil then return false, "gossip_context_busy" end
    if Gossip.active[groupId] ~= nil then return false, "gossip_group_busy" end
    if not meetOnly and now < (Gossip.globalCooldown[context] or 0) then
        return false, "gossip_global_cooldown"
    end
    if now < Gossip.cooldownAt(groupId, meetOnly and "meet" or context) then
        return false, "gossip_group_cooldown"
    end
    if context == "ambient" and not meetOnly then
        if Gossip.armedAt[groupId] == nil then
            Gossip.armedAt[groupId] = now + Gossip.settings.firstSightMinMs
                + stableNumber(groupId .. ":arm")
                    % math.max(1, Gossip.settings.firstSightRangeMs + 1)
            return false, "gossip_arming"
        end
        if now < Gossip.armedAt[groupId] then return false, "gossip_arming" end
    end
    local candidates = Gossip.participants(groupId, shell, context)
    if meetOnly and #candidates == 0 then
        local lone = Gossip.soloParticipant(shell)
        if lone ~= nil then candidates = { lone } end
    end
    if context == "ambient" then candidates = Gossip.meetingCandidates(groupId, shell, candidates, now) end
    if meetOnly and not candidates.meeting then
        Gossip.meetNote("alone")
        return false, "meeting_alone"
    end
    if candidates.meeting then
        local ready, readyReason = Gossip.meetingReady(candidates, now)
        if not ready then
            Gossip.meetNote("dwell")
            return false, readyReason
        end
        if now < Gossip.meetGlobalAt then return false, "gossip_global_cooldown" end
    end

    if #candidates == 0 and context == "ambient" then
        local solo = Gossip.soloParticipant(shell)
        if solo ~= nil then candidates = { solo } end
    end
    local topic = candidates.meeting and "meet" or tostring(options.topic or "any")
    local selectionKey = groupId .. ":" .. context .. ":" .. topic
        .. ":" .. tostring(math.floor(now / 1000))
    local historyKey = groupId .. ":" .. context .. ":" .. topic
    local history = Gossip.playedScenes[historyKey] or {}

    local selected, reason
    if candidates.meeting then
        selected, reason = Gossip.selectMeeting(candidates, selectionKey, history)
        if selected == nil then
            Gossip.meetNote("noScene")
            return false, reason
        end
    else
        selected, reason = Gossip.selectCorpus(context, topic, candidates, selectionKey, history)
    end

    local registryTopic = Gossip.topicFallback[topic] or topic
    if selected == nil then
        selected, reason = Gossip.selectScene(context, registryTopic, candidates, selectionKey, history)
    end
    if selected == nil then
        local avoidLast = {}
        if history.lastScene ~= nil then avoidLast[history.lastScene] = true end
        selected, reason = Gossip.selectScene(context, registryTopic, candidates, selectionKey, avoidLast)

        if selected == nil then
            selected, reason = Gossip.selectScene(context, registryTopic, candidates, selectionKey)
        end
        if selected ~= nil then history = {} end
    end
    if selected == nil then return false, reason end
    local allowed, barkReason = Gossip.allowBark(groupId, now)
    if not allowed then return false, barkReason end
    Gossip.sequence = Gossip.sequence + 1
    local token = "gossip:" .. tostring(stableNumber(selectionKey .. ":"
        .. selected.scene.id .. ":" .. tostring(Gossip.sequence)))
    local ids = {}
    for index, participant in ipairs(selected.participants) do ids[index] = participant.uid end
    local state = {
        scene = selected.scene,
        participants = selected.participants,
        token = token,
        startedAtMs = now,
        endsAtMs = now + sceneDuration(selected.scene, selected.participants, token),
        meeting = candidates.meeting == true and #selected.participants >= 2,
        outcome = candidates.meeting == true and selected.scene.gate ~= nil and selected.scene.gate.out or nil,
    }
    Gossip.active[groupId] = state
    Gossip.globalActive[context] = groupId
    Gossip.barkCooldown[groupId] = math.max(
        Gossip.barkCooldown[groupId] or 0, state.endsAtMs)
    local payload = {
        token = token,
        sceneId = selected.scene.id,
        participantUids = table.concat(ids, ","),
        startedAtMs = now,
    }
    if not broadcast(payload) then
        Gossip.active[groupId] = nil
        Gossip.globalActive[context] = nil
        Gossip.barkCooldown[groupId] = now
        return false, "gossip_broadcast_failed"
    end
    if state.meeting then
        state.visitorCount = #Gossip.visitors(shell)
        state.nextVisitorAtMs = now + 1000
        state.meetingMembers = Gossip.meetingMembers(state, now)
        Gossip.meetGlobalAt = now + Gossip.meetSettings.globalGapMs * Gossip.meetScale()
        for left = 1, #selected.participants - 1 do
            for right = left + 1, #selected.participants do
                Gossip.meetPairAt[Gossip.pairKey(Gossip.groupKey(selected.participants[left].actor),
                    Gossip.groupKey(selected.participants[right].actor))] =
                    now + Gossip.meetSettings.pairCooldownMs * Gossip.meetScale()
            end
        end
        Gossip.meetNote("starts")
        for _, participant in ipairs(state.meetingMembers) do
            Gossip.setCooldown(Gossip.groupKey(participant.actor), "ambient", state.endsAtMs + 180000)
            if ProjectALife.Talk ~= nil then
                ProjectALife.Talk.writeMemory(participant.uid, function(m)
                    m.gossipHoldUntilMs, m.gossipFaceUid, m.gossipToken = state.endsAtMs, participant.faceUid, token
                end)
            end
        end
    end
    Gossip.metrics.starts = Gossip.metrics.starts + 1
    if selected.scene.corpus == true then Gossip.notePlayed(selected.participants, selected.scene.id) end
    history[selected.scene.id] = true
    history.lastScene = selected.scene.id
    Gossip.playedScenes[historyKey] = history
    return true, payload
end

local function stopSound(state)
    if state == nil or state.emitter == nil or state.soundId == nil then return end
    if type(Gossip.adapters.stopSound) == "function" then
        pcall(Gossip.adapters.stopSound,
            state.emitter, state.soundId, state.soundName)
    else

        pcall(function()
            ProjectALife.AudioPolicy.stopOwned(
                state.emitter, state.soundId, state.soundName)
        end)
    end
    state.emitter, state.soundId, state.soundName = nil, nil, nil
end

local function stopPlaybackContext(context)
    local token = Gossip.playbackByContext[context]
    local state = token and Gossip.playbacks[token] or nil
    if state ~= nil then stopSound(state); Gossip.playbacks[token] = nil end
    Gossip.playbackByContext[context] = nil
end

function Gossip.preemptCombat(groupId, suppliedNow)
    local now = math.floor(tonumber(suppliedNow) or nowMs())
    local ambientGroup = Gossip.globalActive.ambient
    local state = ambientGroup and Gossip.active[ambientGroup] or nil
    local interrupted = state ~= nil
    if state ~= nil then
        Gossip.releaseMeeting(state)
        Gossip.active[ambientGroup] = nil
        Gossip.globalActive.ambient = nil
        Gossip.setCooldown(ambientGroup, "ambient", now + Gossip.settings.ambientRefundMs)
        Gossip.globalCooldown.ambient = now + Gossip.settings.ambientRefundMs
    end
    if Gossip.playbackByContext.ambient ~= nil then
        stopPlaybackContext("ambient")
        interrupted = true
    end
    if interrupted then
        Gossip.metrics.preemptions = Gossip.metrics.preemptions + 1
        if state ~= nil then
            broadcast({
                token = state.token .. ":preempt",
                sceneId = "",
                participantUids = "",
                startedAtMs = now,
                cancelContext = "ambient",
            })
        end
    end
    return interrupted
end

function Gossip.combatEvent(event, specification, options)
    if type(options) == "table" and options.combat == true then return true end
    local category = specification and specification.category or nil
    if category == "combat" or category == "infected" or category == "tactics" then
        return true
    end
    return event == "CONTACT_HOSTILE" or event == "CONTACT_INFECTED"
        or event == "HURT" or event == "ALLY_DOWN" or event == "RETREAT"
        or event == "SURRENDER" or event == "RELOAD" or event == "OUT_OF_AMMO"
        or event == "WEAPON_JAM" or event == "BREACH" or event == "KILL_CONFIRMED"
end

function Gossip.tickServer(suppliedNow)
    local now, processed = math.floor(tonumber(suppliedNow) or nowMs()), 0
    local preempt = false
    for groupId, state in pairs(Gossip.active) do
        if state.scene.context == "ambient" then
            for _, participant in ipairs(state.meetingMembers or state.participants) do
                local reg = ProjectALife.ActorRegistry
                if reg ~= nil and type(reg.read) == "function" then participant.actor = reg.read(participant.uid) or participant.actor end
                if not alive(participant.shell) or inCombat(participant, now) then
                    preempt = true
                    break
                end
                if (tonumber((participant.actor or {}).memory and participant.actor.memory.talkHoldUntilMs) or 0) > now then
                    preempt = true
                    break
                end
            end
        end
        if state.meeting and not preempt and now >= (state.nextVisitorAtMs or 0) then
            state.nextVisitorAtMs = now + 1000
            local first = state.participants[1]
            local visitors = Gossip.visitors(first.shell)
            if #visitors > (state.visitorCount or 0) and ProjectALife.Talk ~= nil then
                local context = ProjectALife.Speech.contextFor(first.actor, visitors[1])
                context.stance = ProjectALife.Talk.stance(first.actor, visitors[1])
                ProjectALife.Talk.bark(first.actor, first.shell, visitors[1],
                    #visitors > 1 and "GOSSIP_VISITORS" or "GOSSIP_VISITOR", context)
                preempt = true
            end
            state.visitorCount = #visitors
        end
        if not preempt and now >= state.endsAtMs then
            finishServer(groupId, state, now)
            processed = processed + 1
        end
    end
    if preempt and Gossip.preemptCombat(nil, now) then processed = processed + 1 end
    return processed
end

local function findParticipant(uid)
    if type(Gossip.adapters.findParticipant) == "function" then
        return Gossip.adapters.findParticipant(uid)
    end
    local bound = shellFor(uid)
    if bound ~= nil then return bound end
    if type(getCell) ~= "function" then return nil end
    local ok, cell = pcall(getCell)
    if not ok or cell == nil then return nil end
    local listOk, list = pcall(function() return cell:getZombieList() end)
    if not listOk or list == nil then return nil end
    local sizeOk, size = pcall(function() return list:size() end)
    if not sizeOk then return nil end
    for index = 0, size - 1 do
        local shell = list:get(index)
        if tostring(variable(shell, "ALifeUID") or "") == uid then return shell end
    end
    return nil
end

local function participantList(csv)
    local result, seen = {}, {}
    for value in string.gmatch(tostring(csv or ""), "[^,]+") do
        local uid = cleanId(value)
        if uid == nil or seen[uid] then return nil end
        seen[uid] = true
        local shell = findParticipant(uid)
        if not alive(shell) then return nil end
        result[#result + 1] = { uid = uid, shell = shell }
    end
    return #result > 0 and result or nil
end

function Gossip.startAuthoritative(payload)
    if type(payload) ~= "table" then return false, "gossip_payload_invalid" end
    local token = cleanId(payload.token)
    if token == nil or Gossip.seenTokens[token] ~= nil then
        return false, token and "gossip_duplicate" or "gossip_token_invalid"
    end
    local now = nowMs()
    Gossip.seenTokens[token] = now + 300000
    if payload.cancelContext == "ambient" or payload.cancelContext == "combat" then
        stopPlaybackContext(payload.cancelContext)
        return true, "gossip_preempted"
    end
    local scene = Gossip.scenes[tostring(payload.sceneId or "")]
        or Gossip.corpusScene(payload.sceneId)
    if scene == nil or tonumber(payload.startedAtMs) == nil then
        return false, "gossip_scene_invalid"
    end
    if Gossip.playbackByContext[scene.context] ~= nil then
        return false, "gossip_context_busy"
    end
    local participants = participantList(payload.participantUids)
    if participants == nil or #participants < scene.minParticipants
            or not sceneSupports(scene, participants) then
        Gossip.metrics.missingParticipants = Gossip.metrics.missingParticipants + 1
        return false, "gossip_participant_missing"
    end
    local state = {
        token = token,
        scene = scene,
        participants = participants,
        turn = 1,
        nextAtMs = now + 300,
        startedAtMs = now,
    }
    Gossip.playbacks[token] = state
    Gossip.playbackByContext[scene.context] = token
    return true, state
end

function Gossip.colorFor(shell)
    local uid = Gossip.speakerField(shell, "ALifeUID")
    local factionId = nil
    if uid == nil then factionId = Gossip.speakerField(shell, "ALifeFactionId") end
    local voice, speech = ProjectALife.Voice, ProjectALife.Speech
    if voice ~= nil and type(voice.speakerColor) == "function" then
        return voice.speakerColor(uid, factionId)
    end
    if speech ~= nil and type(speech.colorFor) == "function" then
        return speech.colorFor(uid, factionId)
    end
    return { 0.80, 0.80, 0.80 }
end

function Gossip.speakerField(shell, name)
    local kind = type(shell)
    if shell == nil or kind == "number" or kind == "string" or kind == "boolean" then return nil end
    local value = nil
    if type(shell.getModData) == "function"
            and (type(shell.hasModData) ~= "function" or shell:hasModData() == true) then
        local ok, data = pcall(Gossip.readModData, shell)
        if ok and type(data) == "table" then value = data["Project" .. name] end
    end
    if (value == nil or value == "") and type(shell.GetVariable) == "function" then
        local ok, read = pcall(Gossip.readVariable, shell, name)
        if ok then value = read end
    end
    if value == nil or value == "" then return nil end
    return value
end

function Gossip.readModData(shell) return shell:getModData() end
function Gossip.readVariable(shell, name) return shell:GetVariable(name) end

local function showText(shell, text, event, profile)
    text = ProjectALife.AudioPolicy.caption(text)
    if type(text) ~= "string" or text == "" or Gossip.adapters.textEnabled == false then
        return false
    end
    local speech = ProjectALife.Speech
    if type(speech.refusedDead) == "function" and speech.refusedDead(shell) then return false end
    local color = Gossip.colorFor(shell)
    if type(Gossip.adapters.showText) == "function" then
        local ok, result = pcall(Gossip.adapters.showText,
            shell, text, color, event, profile)
        return ok and result ~= false
    end
    if type(speech.display) == "function" then
        return speech.display(shell, text, color, "ambient", nil) == true
    end
    local ok = pcall(function() shell:addLineChatElement(text, color[1], color[2], color[3]) end)
    return ok
end

local function playSound(shell, sound)
    if not ProjectALife.AudioPolicy.allowsNPC() then return nil, nil end
    if type(sound) ~= "string" or sound == "" or Gossip.adapters.audioEnabled == false then
        return nil, nil
    end
    if type(Gossip.adapters.playSound) == "function" then
        local ok, emitter, soundId = pcall(Gossip.adapters.playSound, shell, sound)
        if ok and emitter ~= false then return emitter, soundId end
        return nil, nil
    end
    local ok, emitter, soundId = pcall(function()
        local value = shell:getEmitter()
        return value, value:playSound(sound)
    end)
    return ok and emitter or nil, ok and soundId or nil
end

function Gossip.liveFace(uid, token)
    local state = token ~= nil and Gossip.playbacks[token] or nil
    if state == nil or state.lastSpeakerUid == nil then return nil end
    if uid == state.lastSpeakerUid then return state.prevSpeakerUid end
    return state.lastSpeakerUid
end

function Gossip.gesturePreset(register, armed, text, speaking, roll)
    text = string.lower(tostring(text or ""))
    local official = register == "law" or register == "swat" or register == "military" or register == "elite"
    if not speaking then
        if armed then return nil end
        if roll < 30 then return "yes" end
        return nil
    end
    local bang = string.find(text, "!", 1, true) ~= nil
    local ask = string.find(text, "?", 1, true) ~= nil
    local hold = string.find(text, "stay", 1, true) or string.find(text, "inside", 1, true)
        or string.find(text, "back off", 1, true) or string.find(text, "hold", 1, true)
        or string.find(text, "step back", 1, true) or string.find(text, "stand", 1, true)
    if official or armed then
        if hold and roll < 70 then return "stop" end
        if bang and roll < 40 then return "stop" end
        if not ask and roll < 12 then return "stop" end
        return nil
    end
    local plead = string.find(text, "please", 1, true) or string.find(text, "help", 1, true)
        or string.find(text, "my ", 1, true)
    if bang and plead and roll < 55 then return "come_here" end
    if bang and roll < 60 then return "shout" end
    if ask and roll < 50 then return "shrug" end
    if (string.find(text, "can't", 1, true) or string.find(text, "don't", 1, true)
            or string.find(text, "no ", 1, true)) and roll < 45 then return "no_thanks" end
    if roll < 25 then return "undecided" end
    return nil
end

function Gossip.gestureCue(uid, token, shell, now)
    local state = token ~= nil and Gossip.playbacks[token] or nil
    if state == nil or state.lastTurnNo == nil or shell == nil then return nil end
    state.cued = state.cued or {}
    if state.cued[uid] == state.lastTurnNo then return nil end
    state.cued[uid] = state.lastTurnNo
    local roll = stableNumber(tostring(token) .. ":" .. tostring(uid) .. ":" .. tostring(state.lastTurnNo)) % 100
    local register
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.read) == "function" and registry.read(uid) or nil
    if record ~= nil then register = Gossip.registerOf({ actor = record }) end
    local armed = false
    if type(shell.getPrimaryHandItem) == "function" then
        local ok, held = pcall(shell.getPrimaryHandItem, shell)
        armed = ok and held ~= nil
    end
    return Gossip.gesturePreset(register, armed, state.lastText, uid == state.lastSpeakerUid, roll)
end

Gossip.playbackIntervalMs = 100
function Gossip.tickPlaybackThrottled()
    local now = nowMs()
    if now < (Gossip.nextPlaybackAtMs or 0) then return 0 end
    Gossip.nextPlaybackAtMs = now + Gossip.playbackIntervalMs
    return Gossip.tickPlayback(now)
end

function Gossip.tickPlayback(suppliedNow)
    local now, processed = math.floor(tonumber(suppliedNow) or nowMs()), 0
    for token, expiresAt in pairs(Gossip.seenTokens) do
        if now >= expiresAt then Gossip.seenTokens[token] = nil end
    end
    for token, state in pairs(Gossip.playbacks) do
        local interrupted = false
        for _, participant in ipairs(state.participants) do
            if not alive(participant.shell)
                    or (state.scene.context == "ambient" and inCombat(participant, now)) then
                interrupted = true
                break
            end
        end
        if interrupted then
            stopSound(state)
            Gossip.playbacks[token] = nil
            Gossip.playbackByContext[state.scene.context] = nil
            processed = processed + 1
        elseif now >= state.nextAtMs then
            stopSound(state)
            local turn = state.scene.turns[state.turn]
            if turn == nil then
                Gossip.playbacks[token] = nil
                Gossip.playbackByContext[state.scene.context] = nil
            else
                local resolved = Gossip.resolveTurn(
                    state.scene, state.participants, state.turn, token)
                if resolved ~= nil then
                    showText(resolved.shell, resolved.text, resolved.event, resolved.profile)
                    if state.lastSpeakerUid ~= nil and state.lastSpeakerUid ~= resolved.uid then
                        state.prevSpeakerUid = state.lastSpeakerUid
                    end
                    state.lastSpeakerUid, state.lastTurnNo, state.lastText = resolved.uid, state.turn, resolved.text
                    state.emitter, state.soundId = playSound(resolved.shell, resolved.sound)
                    state.soundName = resolved.sound
                    state.nextAtMs = now + math.min(Gossip.settings.turnWatchdogMs,
                        resolved.durationMs or Gossip.settings.textOnlyBeatMs) + 280
                else
                    state.nextAtMs = now + Gossip.settings.textOnlyBeatMs + 280
                end
                state.turn = state.turn + 1
            end
            processed = processed + 1
        end
    end
    return processed
end

function Gossip.tick(suppliedNow)
    local now = math.floor(tonumber(suppliedNow) or nowMs())
    return Gossip.tickServer(now) + Gossip.tickPlayback(now)
end

function Gossip.onServerCommand(module, command, arguments)
    if module == "ProjectALife" and command == "gossipStart" then
        return Gossip.startAuthoritative(arguments)
    end
end

for index, lines in ipairs({
    { "Let's move out- how's your day going?", "Shit, same as always- you?",
      "Could be better, y'know", "Still here though... that counts for something" },
    { "Ready? Next block's ours- anybody sleep last night?", "About an hour, then somebody started snoring",
      "That was a chainsaw, man", "Yeah, the chainsaw in the next sleeping bag" },
    { "Let's go, anything you want us watching for?", "Coffee... I'd kill for a real cup",
      "Just find water, I'll settle for that", "Water, then coffee... a guy can dream" },
    { "We'll go together- you holding up alright?", "Ask me again when we're back",
      "Yeah, ok, I'll take the first corner", "And I'll watch behind us" },
    { "Time to move- same route or the next block?", "Next block, that house yesterday was picked clean",
      "There was a shed behind it we never checked", "Let's look on the way back" },
    { "Come on, daylight's wasting! What's for dinner if we find squat?", "Beans... again",
      "Never thought I'd miss burnt toast", "Keep talking food and I'm turning around", gate = "hour=7,17" },
    { "Let's head out- you look like you got something on your mind", "I used to drive this way to work",
      "You want to take another way?", "Nah, I'm alright... just feels strange" },
    { "Everybody ready? Take a minute if you need it", "I'm good. Just give me a second to get going",
      "Mine snapped halfway home yesterday", "I used to mend mine with tape. Never looked pretty" },
}) do
    local turns = {}
    for _, line in ipairs(lines) do
        turns[#turns + 1] = { text = line, duration = math.max(3, #line / 17), textOnly = true }
    end
    Gossip.register("patrol_departure_" .. tostring(index), turns,
        { context = "ambient", topic = "patrol_departure", voiceProfile = "*", minParticipants = 2, gate = lines.gate })
end

Gossip.register("camp_watch_rotation", {
    { event = "CHECK_IN", duration = 2.8 },
    { event = "STATUS_OK", duration = 2.4 },
    { event = "SAFE_MOMENT", duration = 3.0 },
}, { context = "ambient", topic = "any", voiceProfile = "*" })

Gossip.register("road_memory", {
    { event = "LONG_WALK", duration = 3.1 },
    { event = "LOCATION_COMMENT", duration = 3.0 },
    { event = "HOME_MEMORY", duration = 3.4 },
}, { context = "ambient", topic = "any", voiceProfile = "*" })

Gossip.register("quiet_shift", {
    { event = "TENSE_SILENCE", duration = 2.8 },
    { event = "JOKE", duration = 3.2 },
    { event = "MORALE_HIGH", duration = 2.8 },
}, { context = "ambient", topic = "any", voiceProfile = "*" })

Gossip.register("camp_stories", {
    { event = "CAMP_CHATTER", duration = 5.0 },
    { event = "HOME_MEMORY", duration = 3.4 },
    { event = "CAMP_CHATTER", duration = 5.0 },
}, { context = "ambient", topic = "any", voiceProfile = "*", minParticipants = 2 })

Gossip.register("supplies_caption", {
    { text = "We oughta count the food before we move", duration = 2.2, textOnly = true },
    { text = "Count the water jugs, cans can wait", duration = 2.2, textOnly = true },
    { text = "Fine, but leave one bag packed in case we have to run", duration = 2.2, textOnly = true },
}, { context = "ambient", topic = "any", voiceProfile = "*" })

Gossip.register("weather_caption", {
    { text = "I keep wondering what the weather's going to do", duration = 2.2, textOnly = true },
    { text = "We ought to think about keeping things dry", duration = 2.2, textOnly = true },
    { text = "Yeah. I'd rather think about it now than when we're soaked", duration = 2.2, textOnly = true },
}, { context = "ambient", topic = "any", voiceProfile = "*", gate = "world=fire|hour=15,22" })

Gossip.register("route_caption", {
    { text = "We take the side road, stay off the junction", duration = 2.2, textOnly = true },
    { text = "Might take longer. We don't know what the way through is like", duration = 2.2, textOnly = true },
    { text = "I'll take a longer walk over a stupid chance", duration = 2.2, textOnly = true },
}, { context = "ambient", topic = "any", voiceProfile = "*", gate = "world=road" })

for topic, pack in pairs({
    outpost_guard = {
        { "Anything moving out there?", "Nothing I'm willing to stop looking over",
          "Keep looking anyway, that's when they show up" },
        { "How long is your shift?", "Long enough that I'd rather not keep count",
          "I'll bring you something warm before then" },
        { "Did you hear that, out past the wire?", "I keep hoping it's branches. Makes a change from expecting the worst",
          "One of these days it won't be, and I'll be the one who warned you" },
        { "What do you want us watching for?", "Anybody coming close. I'd rather get a warning than a surprise",
          "Good. Same goes for me if you see me nodding off" },
    },
    outpost_farm = {
        { "I miss having a garden to worry about", "I'd like to try growing something again",
          "Something besides another damn argument, I hope" },
        { "My old garden got eaten almost as fast as I planted it", "Rabbits?",
          "Sometimes. Mostly I blamed them because I didn't know what I was doing" },
        { "My dad could tell you all about soil. I mostly remember carrying the bags", "Mine handed me a shovel and called that a lesson",
          "Well, if we ever get a garden, you can do the digging" },
        { "What would you plant first?", "Beans, probably. I might actually keep those alive",
          "Beans it is then... I'm sick of 'em just thinking about it" },
    },
    outpost_mechanic = {
        { "Will it start?", "I couldn't tell you till I've had a look",
          "Then we look before deciding what's wrong. I hate guessing with engines" },
        { "If we're relying on that generator, somebody ought to check it", "You volunteering, or telling me?",
          "I'm asking. I'd like to know before we're relying on it", gate = "world=generator" },
        { "I'd want a look at the tires before we take that thing anywhere", "You know what to look for?",
          "Enough to ask somebody who knows more than me", gate = "world=vehicle" },
    },
    outpost_fire = {
        { "Sit down, you been up since before light", "If I sit down I won't get up again",
          "That's sorta the idea" },
        { "What'd you do before all this?", "Nothing useful, I sold insurance",
          "You'd be surprised what turns out useful" },
        { "I could murder a cup of coffee", "Even the stuff we used to make?", "I'd drink yours at this point. That's how bad it's got" },
        { "Quiet tonight", "Don't say that out loud!",
          "Too late, already said it... guess we deal with it", gate = "hour=16,5" },
    },
    outpost_medic = {
        { "Do you ever stop worrying about people?", "For a little while. Then I remember somebody else",
          "If you need a minute, ask. You don't have to do all the worrying at once" },
        { "I miss opening a clean packet and not thinking twice about it", "Hospital laundry smell? I never thought I'd miss it",
          "Me neither. Funny what stays with you" },
    },
}) do
    for index, lines in ipairs(pack) do
        local turns = {}
        for _, line in ipairs(lines) do
            turns[#turns + 1] = { text = line, duration = math.max(2.4, #line / 17), textOnly = true }
        end
        Gossip.register(topic .. "_" .. tostring(index), turns,
            { context = "ambient", topic = topic, voiceProfile = "*", minParticipants = 2, gate = lines.gate })
    end
end

for topic, pack in pairs({
    crash_talk = {
        { "SHIT- you just crashed the car!", "I didn't see it, I swear to God I didn't see that car!",
          "Now what?", "I dunno, let me think... maybe we walk to the next town up the road", gate = "world=vehicle,road" },
        { "I keep wanting to check the car again", "For something you forgot?",
          "For an excuse not to start walking, mostly", "Then it stays, nobody's dying over a bag", gate = "world=vehicle" },
        { "Is everyone alright? Anyone bleeding?", "I can't think straight. Give me a second",
          "Sit down a sec, nobody's driving anything today", "Let's have a look before we decide what we're doing" },
        { "Which way is the nearest town?", "I'd rather check the route than guess how long it'll take",
          "Great, more walking and wondering", "So we hug the edge and keep our mouths shut", gate = "world=road" },
    },
    breakdown_talk = {
        { "Well?", "I don't know what's wrong yet", "Fuel?", "Could be. I'm not calling it before we've looked" },
        { "How long?", "Give me a little time to look", "That's what you said before!",
          "And I'll say it again in ten, watch the road", gate = "world=road" },
        { "Anyone coming?", "I keep expecting to see somebody", "Keep watching. I'd rather you said you weren't sure than told me it's clear",
          "Yeah. I wasn't going to promise you anything" },
        { "If it won't start we push it off the road and walk", "We're not leaving the car!",
          "We're not sleeping in it either", "Ten more minutes, then we talk about walking", gate = "world=vehicle,road" },
    },
}) do
    for index, lines in ipairs(pack) do
        local turns = {}
        for _, line in ipairs(lines) do
            turns[#turns + 1] = { text = line, duration = math.max(2.4, #line / 17), textOnly = true }
        end
        Gossip.register(topic .. "_" .. tostring(index), turns,
            { context = "ambient", topic = topic, voiceProfile = "*", minParticipants = 2, gate = lines.gate })
    end
end

if not ProjectALife.GossipEventsRegistered and type(Events) == "table" then
    ProjectALife.GossipEventsRegistered = true
    if Events.OnServerCommand ~= nil
            and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(Gossip.onServerCommand)
    end
    if Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then

        Events.OnTick.Add(Gossip.tickPlaybackThrottled)
    end
end

return Gossip
