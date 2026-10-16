require "ProjectALife/Audio/ALifeVoiceCatalog"
require "ProjectALife/Audio/ALifeGossip"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Audio/ALifeFactionVoiceStyles"
require "ProjectALife/Audio/ALifeVoiceTextFallback"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Shells/ALifeWounds"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.VoiceCatalog
local Gossip = ProjectALife.Gossip
local FactionStyles = ProjectALife.FactionVoiceStyles
local Voice = {
    adapters = {},
    eventCooldowns = {},
    actorLocks = {},
    groupLocks = {},
    lastEntries = {},
    recentLines = {},
    recentBarks = {},
    nextAmbientAt = {},
    metrics = { ambientChecks = 0, ambientAttempts = 0, ambientPlayed = 0 },
}
ProjectALife.Voice = Voice

local function nowMs()
    if type(Voice.adapters.nowMs) == "function" then return Voice.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function variable(shell, name)
    local dataOk, data = pcall(function() return shell:getModData() end)
    if dataOk and type(data) == "table" then
        local value = data["Project" .. name]
        if value ~= nil then return value end
    end
    local ok, value = pcall(function() return shell:GetVariable(name) end)
    return ok and value or nil
end

local function percent()
    if type(Voice.adapters.choosePercent) == "function" then
        return math.max(0, math.min(99, tonumber(Voice.adapters.choosePercent()) or 0))
    end
    if type(ZombRand) == "function" then return ZombRand(100) end
    return math.random(0, 99)
end

local function choose(maximum)
    if maximum <= 1 then return 1 end
    if type(Voice.adapters.chooseIndex) == "function" then
        return math.max(1, math.min(maximum,
            math.floor(tonumber(Voice.adapters.chooseIndex(maximum)) or 1)))
    end
    if type(ZombRandBetween) == "function" then return ZombRandBetween(1, maximum + 1) end
    return math.random(1, maximum)
end

local function stableNumber(value)
    local result = 0
    value = tostring(value or "")
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function truthy(value)
    return value == true or value == 1 or value == "true"
end

local function clean(value)
    local result = tostring(value or "")
    result = string.gsub(result, "[%c{}]", " ")
    result = string.gsub(result, "%s+", " ")
    result = string.gsub(result, "^%s+", "")
    result = string.gsub(result, "%s+$", "")
    if #result > 48 then result = string.sub(result, 1, 48) end
    return result
end

local function render(text, context)
    if type(text) ~= "string" then return nil end
    context = type(context) == "table" and context or {}
    return (string.gsub(text, "{([%w_]+)}", function(key)
        local speech = ProjectALife.Speech
        if context[key] == nil and speech ~= nil and type(speech.addressForms) == "table"
                and speech.addressForms[string.lower(key)] ~= nil then
            return "{" .. key .. "}"
        end
        return clean(context[key])
    end))
end

local function matches(entry, context)
    if type(entry.when) ~= "table" then return true end
    for key, expected in pairs(entry.when) do
        local actual = context and context[key] or nil
        if type(expected) == "table" then
            local accepted = false
            for _, value in ipairs(expected) do
                if actual == value then accepted = true; break end
            end
            if not accepted then return false end
        elseif actual ~= expected then
            return false
        end
    end
    return true
end

function Voice.attackFits(profile, event, entry, context)
    local attack = type(context) == "table" and context.attack or nil
    if attack == nil then return true end
    local text = entry.text
    if (text == nil or text == "") and type(Catalog.captionFor) == "function" then
        text = Catalog.captionFor(profile, event, entry)
    end
    return ProjectALife.Wounds.textFits(text, attack)
end

local function candidates(profile, event, context, styleId)
    local result = {}
    for _, entry in ipairs(Catalog.entries(profile, event, styleId)) do
        if matches(entry, context) and Voice.attackFits(profile, event, entry, context) then
            local weight = math.max(1, math.floor(tonumber(entry.weight) or 1))
            for _ = 1, math.min(weight, 20) do result[#result + 1] = entry end
        end
    end
    return result
end

local function chooseEntry(profile, event, context, actorKey, styleId)
    local entries = candidates(profile, event, context, styleId)
    if #entries == 0 then return nil end
    local history = Voice.recentLines[actorKey] or {}
    local fresh = {}
    for _, entry in ipairs(entries) do
        local key = entry.sound or entry.text
        local recent = false
        for _, used in ipairs(history) do if key == used then recent = true; break end end
        if not recent then fresh[#fresh + 1] = entry end
    end
    if #fresh > 0 then entries = fresh end
    local index = choose(#entries)
    local last = Voice.lastEntries[actorKey .. ":" .. event]
    if #entries > 1 and entries[index] == last then index = index % #entries + 1 end
    local entry = entries[index]
    history[#history + 1] = entry.sound or entry.text
    if #history > 6 then table.remove(history, 1) end
    Voice.recentLines[actorKey] = history
    Voice.lastEntries[actorKey .. ":" .. event] = entry
    return entry
end

local function groupKey(shell, options)
    if options.groupKey ~= nil then return tostring(options.groupKey) end
    local registry = ProjectALife.ActorRegistry
    local uid = variable(shell, "ALifeUID")
    local actor = registry and type(registry.peek) == "function" and uid and registry.peek(uid) or nil
    local memory = actor and actor.memory or {}

    if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
    if memory.groupId ~= nil then return "group:" .. tostring(memory.groupId) end
    local stamped = variable(shell, "ALifeGroupId") or variable(shell, "ALifeOperationId")
    if stamped ~= nil and tostring(stamped) ~= "" then return tostring(stamped) end
    local faction = variable(shell, "ALifeFactionId")
    local ok, x, y = pcall(function() return shell:getX(), shell:getY() end)
    if faction ~= nil and ok then
        return tostring(faction) .. ":" .. tostring(math.floor(x / 12))
            .. ":" .. tostring(math.floor(y / 12))
    end
    return nil
end

Voice.captionGrey = { 0.80, 0.80, 0.80 }

function Voice.colorForKey(key)
    local hue = stableNumber(key) % 360
    local s, v = 0.55, 0.95
    local c = v * s
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if hue < 60 then r, g, b = c, x, 0 elseif hue < 120 then r, g, b = x, c, 0
    elseif hue < 180 then r, g, b = 0, c, x elseif hue < 240 then r, g, b = 0, x, c
    elseif hue < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
    return { r + m, g + m, b + m }
end

function Voice.colorForUid(uid)
    return Voice.colorForKey("colour:" .. tostring(uid))
end

function Voice.colorForFaction(factionId)
    return Voice.colorForKey("faction:" .. tostring(factionId))
end

function Voice.speakerColor(uid, factionId)
    if uid ~= nil and tostring(uid) ~= "" then return Voice.colorForUid(uid) end
    if factionId ~= nil and tostring(factionId) ~= "" then return Voice.colorForFaction(factionId) end
    local grey = Voice.captionGrey
    return { grey[1], grey[2], grey[3] }
end

local function captionColor(options, uid, factionId)
    if type(options.color) == "table" then return options.color end
    return Voice.speakerColor(uid, factionId)
end

local function captionFor(profileId, event, entry, context)
    return render(Catalog.captionFor(profileId, event, entry), context)
end

local function showText(shell, text, color, event, profile)
    text = ProjectALife.AudioPolicy.caption(text)
    if text == nil or text == "" then return false end
    local speech = ProjectALife.Speech
    if type(speech.refusedDead) == "function" and speech.refusedDead(shell) then return false end
    if type(Voice.adapters.showText) == "function" then
        local ok, result = pcall(Voice.adapters.showText,
            shell, text, color, event, profile)
        return ok and result ~= false
    end
    if type(speech.display) == "function" then
        return speech.display(shell, text, color, speech.kindFor(event), nil) == true
    end
    local ok = pcall(function()
        shell:addLineChatElement(text, color[1], color[2], color[3])
    end)
    return ok
end

local function playSound(shell, sound)
    if not ProjectALife.AudioPolicy.allowsNPC() then return false end
    if type(sound) ~= "string" or sound == "" then return false end
    if type(Voice.adapters.playSound) == "function" then
        local ok, result = pcall(Voice.adapters.playSound, shell, sound)
        return ok and result ~= false
    end
    if type(isServer) == "function" and isServer()
            and type(sendPlaySound) == "function" then
        local ok, result = pcall(sendPlaySound, sound, false, shell)
        return ok and result ~= false
    end
    local ok, result = pcall(function() return shell:playSound(sound) end)
    return ok and result ~= false
end

function Voice.configure(adapters)
    Voice.adapters = adapters or {}
    Gossip.configureVoice(Voice.adapters)
end

function Voice.reset()
    Voice.eventCooldowns = {}
    Voice.actorLocks = {}
    Voice.groupLocks = {}
    Voice.lastEntries = {}
    Voice.recentLines = {}
    Voice.recentBarks = {}
    Voice.nextAmbientAt = {}
    Voice.metrics = { ambientChecks = 0, ambientAttempts = 0, ambientPlayed = 0 }
    Gossip.reset()
end

function Voice.forget(uid)
    local prefix = tostring(uid or "") .. ":"
    Voice.actorLocks[tostring(uid or "")] = nil
    Voice.recentLines[tostring(uid or "")] = nil
    Voice.nextAmbientAt[tostring(uid or "")] = nil
    for key in pairs(Voice.eventCooldowns) do
        if string.sub(key, 1, #prefix) == prefix then Voice.eventCooldowns[key] = nil end
    end
    for key in pairs(Voice.lastEntries) do
        if string.sub(key, 1, #prefix) == prefix then Voice.lastEntries[key] = nil end
    end
end

local function scheduleAmbient(uid, now)
    local minimum = math.max(10000,
        math.floor(tonumber(Voice.adapters.ambientMinimumMs) or 35000))
    local maximum = math.max(minimum,
        math.floor(tonumber(Voice.adapters.ambientMaximumMs) or 70000))
    local span = math.max(1, maximum - minimum + 1)
    Voice.nextAmbientAt[uid] = now + minimum
        + stableNumber(uid .. ":" .. tostring(math.floor(now / 1000))) % span
end

function Voice.tickAmbient(shell, options)

    if Voice.adapters.enabled ~= true or Voice.adapters.ambientEnabled == false then
        return false, "ambient_disabled"
    end
    options = options or {}
    Voice.metrics.ambientChecks = Voice.metrics.ambientChecks + 1
    if shell == nil then return false, "ambient_actor_missing" end
    local uid = tostring(variable(shell, "ALifeUID") or shell)
    local now = nowMs()
    local due = Voice.nextAmbientAt[uid]
    if due == nil then
        scheduleAmbient(uid, now)
        return false, "ambient_scheduled"
    end
    if options.meetings ~= false then
        Gossip.probeMeeting(shell, { groupId = groupKey(shell, options), blocked = options.blocked == true, now = now })
    end
    if now < due then return false, "ambient_waiting" end
    scheduleAmbient(uid, now)
    Gossip.tick(now)
    local director = ProjectALife.ChatterDirector
    local owned = director ~= nil and type(director.ownsAmbient) == "function" and director.ownsAmbient(shell) == true
    local gossipStarted, gossipResult = false, nil
    if not owned then
        gossipStarted, gossipResult = Gossip.tryStart(shell, {
            context = "ambient",
            topic = options.topic or "any",
            groupId = groupKey(shell, options),
            now = now,
        })
    end
    if gossipStarted then
        return true, gossipResult
    end
    local pool = options.pool
        or (Catalog.ambientPools and Catalog.ambientPools[options.state or "idle"])
    if type(pool) ~= "table" or #pool == 0 then return false, "ambient_pool_empty" end
    Voice.metrics.ambientAttempts = Voice.metrics.ambientAttempts + 1
    local played, result = Voice.play(shell, pool[choose(#pool)], {
        context = options.context,
    })
    if played then Voice.metrics.ambientPlayed = Voice.metrics.ambientPlayed + 1 end
    return played, result
end

function Voice.snapshot()
    local scheduled = 0
    for _ in pairs(Voice.nextAmbientAt) do scheduled = scheduled + 1 end
    return {
        profiles = #Catalog.profileIds(),
        events = (function()
            local count = 0
            for _ in pairs(Catalog.events) do count = count + 1 end
            return count
        end)(),
        scheduledActors = scheduled,
        ambientChecks = Voice.metrics.ambientChecks,
        ambientAttempts = Voice.metrics.ambientAttempts,
        ambientPlayed = Voice.metrics.ambientPlayed,
    }
end

function Voice.preview(profile, event, context, female)
    local resolvedEvent = Catalog.resolveEvent(event)
    if resolvedEvent == nil then return nil, "voice_event_missing" end
    local resolvedProfile = Catalog.resolveProfile(profile, female == true)
    local entry = chooseEntry(resolvedProfile, resolvedEvent, context or {}, "preview",
        type(context) == "table" and context.factionStyle or nil)
    if entry == nil then return nil, "voice_entry_missing" end
    return {
        event = resolvedEvent,
        profile = resolvedProfile,
        text = captionFor(resolvedProfile, resolvedEvent, entry, context),
        sound = entry.sound,
    }
end

function Voice.action(shell, action, phase, options)
    options = options or {}
    local contract = Catalog.contract(action)
    local event = contract and contract[phase] or nil
    if event == nil then return false, "voice_action_contract_missing" end
    return Voice.play(shell, event, options)
end

function Voice.repeatedBark(shell, event, group, text, now, remember)
    local x, y, z
    if shell.getX ~= nil and shell.getY ~= nil and shell.getZ ~= nil then
        x, y, z = shell:getX(), shell:getY(), shell:getZ()
    end
    local contact = string.sub(event, 1, 8) == "CONTACT_"
    for index = #Voice.recentBarks, 1, -1 do
        local previous = Voice.recentBarks[index]
        local age = now - previous.atMs
        if age < 0 or age >= 90000 then
            table.remove(Voice.recentBarks, index)
        elseif contact and previous.contact and group ~= nil and previous.group == group and age < 60000 then
            return true
        elseif text ~= nil and text == previous.text and x ~= nil and previous.x ~= nil
                and math.abs(z - previous.z) < 2
                and (x - previous.x)^2 + (y - previous.y)^2 <= 30^2 then
            return true
        end
    end
    if remember then
        Voice.recentBarks[#Voice.recentBarks + 1] = { atMs = now, contact = contact,
            group = group, text = text, x = x, y = y, z = z }
        if #Voice.recentBarks > 64 then table.remove(Voice.recentBarks, 1) end
    end
    return false
end

Voice.woundFamily = { HURT = true, ALLY_HIT = true, HIT_CONFIRMED = true }

Voice.woundFamilyMs = 5000

Voice.commandEvents = { LEADER_ORDER = true, STACK_UP = true, STEADY = true }

function Voice.commandFits(shell, event)
    if Voice.commandEvents[event] ~= true then return true end
    local registry, roles = ProjectALife.ActorRegistry, ProjectALife.DialogueRoles
    local uid = variable(shell, "ALifeUID")
    local read = registry and (registry.peek or registry.read)
    local actor = type(read) == "function" and uid and read(tostring(uid)) or nil
    if type(actor) ~= "table" or actor.lifecycle ~= "active" then return false end
    if roles == nil or type(roles.callStyle) ~= "function" or roles.callStyle(actor) ~= "trained" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.person) == "table" and memory.person.id ~= nil then return false end
    local hours
    pcall(function()
        local clock = getGameTime()
        if clock ~= nil and type(clock.getWorldAgeHours) == "function" then hours = clock:getWorldAgeHours() end
    end)
    for _, key in ipairs({ "visit", "guest" }) do
        local lease = memory[key]
        if type(lease) == "table" and lease.pendingId ~= nil
                and (hours == nil or tonumber(lease.untilHours) == nil or tonumber(lease.untilHours) > hours) then return false end
    end
    if event ~= "LEADER_ORDER" then return true end
    local held
    if type(shell.getPrimaryHandItem) == "function" then
        pcall(function() held = shell:getPrimaryHandItem() end)
    end
    if held == nil or ProjectALife.Wounds.weaponKind(held) ~= "firearm" then return false end
    local tactics = ProjectALife.SquadTactics
    local contact = tactics and type(tactics.contacts) == "table" and tactics.contacts[memory.groupId] or nil
    if type(contact) ~= "table" or (contact.kind ~= "actor" and contact.kind ~= "player")
            or not ProjectALife.Speech.alive(contact.target)
            or nowMs() - (tonumber(contact.atMs) or 0) > 12000 then return false end
    if type(tactics.livingMembers) ~= "function" or type(shell.getX) ~= "function"
            or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function" then return false end
    local _, members = tactics.livingMembers(memory.groupId, actor.uid, shell:getX(), shell:getY(), 25)
    for _, mate in ipairs(members) do
        local binding = ProjectALife.Watchdog and ProjectALife.Watchdog.bindings[mate.uid]
        if binding ~= nil and binding.generation == mate.actor.generation
                and ProjectALife.Speech.alive(mate.shell) and type(mate.shell.getZ) == "function"
                and mate.shell:getZ() == shell:getZ() then return true end
    end
    return false
end

function Voice.play(shell, event, options)

    if Voice.adapters.enabled ~= true then return false, "voice_disabled" end
    options = options or {}
    if shell == nil or type(event) ~= "string" then return false, "voice_request_invalid" end

    if not ProjectALife.Speech.alive(shell) then return false, "voice_dead" end
    local resolvedEvent = Catalog.resolveEvent(event)
    local specification = resolvedEvent and Catalog.events[resolvedEvent] or nil
    if specification == nil then return false, "voice_event_missing" end
    if not Voice.commandFits(shell, resolvedEvent) then return false, "voice_context_mismatch" end
    if not ProjectALife.Speech.allows(shell, nil, resolvedEvent, specification.category, nil) then
        return false, "voice_quiet"
    end

    local female = truthy(variable(shell, "ALifeFemale"))
    local profile = Catalog.resolveProfile(
        options.profile or variable(shell, "ALifeVoiceProfile"), female)
    local speaker = variable(shell, "ALifeUID")
    local uid = tostring(speaker or shell)
    local eventKey = uid .. ":" .. resolvedEvent
    local group = groupKey(shell, options)
    local now = nowMs()
    local priority = math.floor(tonumber(options.priority) or specification.priority or 50)
    local interrupt = options.urgent == true or specification.interrupt == true

    Gossip.tick(now)

    if resolvedEvent == "PATROL_START" then
        if Voice.adapters.ambientEnabled == false then return false, "ambient_disabled" end
        return Gossip.tryStart(shell, { context = "ambient", topic = "patrol_departure",
            groupId = group, now = now })
    end
    if not options.ignoreCooldown and now < (Voice.eventCooldowns[eventKey] or 0) then
        return false, "voice_cooldown"
    end

    local woundKey = Voice.woundFamily[resolvedEvent] == true
        and ((group or uid) .. ":wound") or nil
    if woundKey ~= nil and not options.ignoreCooldown
            and now < (Voice.eventCooldowns[woundKey] or 0) then
        return false, "voice_wound_family"
    end
    if Voice.repeatedBark(shell, resolvedEvent, group, nil, now) then return false, "voice_contact_repeat" end
    local actorLock = Voice.actorLocks[uid]
    if actorLock ~= nil and now < actorLock.untilMs
            and not (interrupt and priority > actorLock.priority) then
        return false, "voice_actor_busy"
    end
    local groupLock = group and Voice.groupLocks[group] or nil
    if groupLock ~= nil and now < groupLock.untilMs
            and not (interrupt and priority > groupLock.priority) then
        return false, "voice_group_busy"
    end
    local chance = math.max(0, math.min(100,
        tonumber(options.chance) or specification.chance or 100))
    if options.force ~= true and percent() >= chance then return false, "voice_chance" end

    local factionId = options.factionId or variable(shell, "ALifeFactionId")
    local styleId = nil
    if FactionStyles ~= nil then
        styleId = FactionStyles.styleFor(factionId)
    end
    local entry = chooseEntry(profile, resolvedEvent, options.context or {}, uid, styleId)
    if entry == nil then return false, "voice_entry_missing" end
    if group ~= nil and options.ignoreBarkThrottle ~= true then
        local allowed = Gossip.allowBark(group, now)
        if not allowed then return false, "voice_bark_throttle" end
    end
    local text = captionFor(profile, resolvedEvent, entry, options.context)
    if entry.text ~= nil and entry.text ~= "" then text = render(entry.text, options.context) end
    local textEnabled = Voice.adapters.textEnabled ~= false and options.textEnabled ~= false

    local audioEnabled = ProjectALife.AudioPolicy.allowsNPC()
        and Voice.adapters.audioEnabled == true and options.audioEnabled ~= false
        and not (actorLock and now < (actorLock.audioUntilMs or 0))

    if textEnabled and (entry.sound == nil or not audioEnabled) then
        local corpusText = nil
        local speech = ProjectALife.Speech
        if speech ~= nil and type(speech.corpusCaption) == "function" then
            local ok, corpus = pcall(speech.corpusCaption, shell, resolvedEvent, uid,
                type(options.context) == "table" and options.context.attack or nil,
                type(options.context) == "table" and options.context.psex or nil)
            if ok and type(corpus) == "string" and corpus ~= "" then corpusText = corpus end
        end
        text = corpusText or ProjectALife.VoiceTextFallback.caption(resolvedEvent, specification)
    end
    if ProjectALife.Speech ~= nil and type(ProjectALife.Speech.gendered) == "function" then
        text = ProjectALife.Speech.gendered(text, type(options.context) == "table" and options.context.psex or nil, shell)
    end
    if Voice.repeatedBark(shell, resolvedEvent, group, text, now) then return false, "voice_caption_repeat" end
    if Gossip.combatEvent(resolvedEvent, specification, options) then Gossip.preemptCombat(group, now) end
    local textPlayed = textEnabled and showText(shell, text,
        captionColor(options, speaker, factionId), resolvedEvent, profile) or false

    local soundPlayed = entry.sound ~= nil and audioEnabled
        and playSound(shell, entry.sound) or false
    if not textPlayed and not soundPlayed then return false, "voice_output_failed" end
    Voice.repeatedBark(shell, resolvedEvent, group, text, now, true)

    Voice.eventCooldowns[eventKey] = now + math.max(0,
        math.floor(tonumber(options.cooldownMs) or specification.cooldownMs or 2500))
    if woundKey ~= nil then
        Voice.eventCooldowns[woundKey] = now
            + math.max(0, math.floor(tonumber(Voice.woundFamilyMs) or 5000))
    end
    local audioUntil = soundPlayed and (now + math.max(0,
        tonumber(entry.durationMs) or specification.actorLockMs or 1200) + 200)
        or actorLock and actorLock.audioUntilMs or 0
    Voice.actorLocks[uid] = {
        untilMs = math.max(audioUntil, now + math.max(0, math.floor(specification.actorLockMs or 1200))),
        audioUntilMs = audioUntil,
        priority = priority,
    }
    local groupCooldown = math.max(0,
        math.floor(tonumber(options.groupCooldownMs)
            or specification.groupCooldownMs or 0))
    if group ~= nil and groupCooldown > 0 then
        Voice.groupLocks[group] = { untilMs = math.max(audioUntil, now + groupCooldown), priority = priority }
    end
    return true, {
        event = resolvedEvent,
        profile = profile,
        text = textPlayed and text or nil,
        sound = soundPlayed and entry.sound or nil,
        captionOnly = entry.sound == nil and textPlayed,
    }
end

Voice.react = Voice.play
return Voice
