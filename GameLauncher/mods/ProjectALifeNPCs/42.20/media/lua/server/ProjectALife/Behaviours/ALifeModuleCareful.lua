require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Senses/ALifeSight"
require "ProjectALife/Outposts/ALifeOutpostRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Careful = {
    id = "careful",
    settings = {
        warnRadius = 14,
        closeRadius = 9,
        contactRadius = 6,
        contactHoldMs = 1500,
        warningGraceMs = 4000,
        advanceTiles = 0.75,

        forgetMs = 45000,

        nagMs = 12000,

        sightRequired = true,
    },
    metrics = { warnings = 0, lastWarnings = 0, turned = 0, shouts = 0 },

    ladders = {},
}
ProjectALife.ModuleCareful = Careful

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function groupOf(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) == "table" then

        if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
        if memory.groupId ~= nil then return memory.groupId end
    end
    return "solo:" .. tostring(actor and actor.uid)
end

function Careful.playerKey(player)
    local reputation, speech = ProjectALife.Reputation, ProjectALife.Speech
    if reputation and type(reputation.playerKey) == "function" then return reputation.playerKey(player) end
    if speech and type(speech.playerKey) == "function" then return speech.playerKey(player) end
    return nil
end

function Careful.ladderKey(actor, player)
    return tostring(groupOf(actor)) .. ":player:" .. tostring(Careful.playerKey(player))
end

local function ladderFor(actor, now, player)
    if now >= (Careful.nextPruneMs or 0) then
        Careful.nextPruneMs = now + Careful.settings.forgetMs
        for oldKey, old in pairs(Careful.ladders) do
            if now - (old.lastInsideAtMs or old.atMs or 0) > Careful.settings.forgetMs then
                Careful.ladders[oldKey] = nil
            end
        end
    end
    local key = Careful.ladderKey(actor, player)
    local ladder = Careful.ladders[key]

    if ladder == nil or now - (ladder.lastInsideAtMs or ladder.atMs or 0) > Careful.settings.forgetMs then
        ladder = { step = 0, atMs = now, contactSinceMs = nil, lastInsideAtMs = now }
        Careful.ladders[key] = ladder
    end
    return ladder, key
end

local function players()
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then return locator.list() end
    return {}
end

local function visible(player)
    if player == nil then return false end
    local hidden = false
    pcall(function()
        if type(player.isDead) == "function" and player:isDead() then
            hidden = true
        elseif type(player.isInvisible) == "function" and player:isInvisible() == true then
            hidden = true
        elseif type(player.isGhostMode) == "function" and player:isGhostMode() == true then
            hidden = true
        end
    end)
    return not hidden
end

Careful.visible = visible

function Careful.distanceRaw(shell, player)
    if shell.getZ and player.getZ and math.floor(shell:getZ()) ~= math.floor(player:getZ()) then return math.huge end
    local dx, dy = shell:getX() - player:getX(), shell:getY() - player:getY()
    return math.sqrt(dx * dx + dy * dy)
end

local function distanceTo(shell, player)
    local ok, d = pcall(Careful.distanceRaw, shell, player)
    return ok and d or math.huge
end

Careful.sightCache = setmetatable({}, { __mode = "k" })
local function sees(shell, player, distance)
    if not Careful.settings.sightRequired then return true end
    if distance <= 3 then return true end
    local now = nowMs()
    local cached = Careful.sightCache[shell]
    if cached ~= nil and cached.player == player and now - cached.atMs < 700 then return cached.seen end
    local seen = Careful.lineOfSight(shell, player)
    Careful.sightCache[shell] = { player = player, atMs = now, seen = seen }
    return seen
end

function Careful.lineOfSight(shell, player)

    if not visible(player) then return false end

    local watcher = ProjectALife.Perception
    if watcher ~= nil and type(watcher.playerInSightRange) == "function" then
        local actor = type(watcher.activeActorForShell) == "function" and watcher.activeActorForShell(shell) or nil
        if not watcher.playerInSightRange(actor, player, distanceTo(shell, player)) then return false end
    end
    if watcher ~= nil and type(watcher.engineCanSee) == "function" then
        if watcher.engineCanSee(shell, player) == true then return true end
    else
        local ok, seen = pcall(shell.CanSee, shell, player)
        if ok and seen == true then return true end
    end
    local sight = ProjectALife.Sight
    if sight == nil then return false end
    local answer
    pcall(function()
        answer = sight.between(shell:getX(), shell:getY(), shell:getZ(),
            player:getX(), player:getY(), player:getZ())
    end)
    return answer == "clear"
end

local function say(shell, event)
    local voice = ProjectALife.Voice
    if voice == nil or type(voice.play) ~= "function" then return end

    pcall(voice.play, shell, event, { force = true, ignoreBarkThrottle = true })
end

local function face(shell, player)
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then
            guard.faceAimPoint(shell, player:getX(), player:getY(), nowMs())
        else
            shell:faceThisObject(player)
        end
    end)
end

local function challenge(shell)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" then return false end

    if type(animations.active) == "table" and animations.active[shell] ~= nil then
        return false
    end
    return pcall(animations.apply, shell, "stop") == true
end

function Careful.radiiFor(actor)
    local s = Careful.settings
    local r = type(actor) == "table" and type(actor.memory) == "table" and actor.memory.carefulRadii or nil

    local scripted = ProjectALife.ScriptedEncounter
    local warn, close, contact, hold = s.warnRadius, s.closeRadius, s.contactRadius, s.contactHoldMs
    if type(r) == "table" then
        warn = tonumber(r.warnRadius) or warn
        close = tonumber(r.closeRadius) or close
        contact = tonumber(r.contactRadius) or contact
        hold = tonumber(r.contactHoldMs) or hold
    end
    if scripted ~= nil and type(scripted.value) == "function" then
        warn = tonumber(scripted.value(actor, "warnRadius", warn)) or warn
        close = tonumber(scripted.value(actor, "closeRadius", close)) or close
        contact = tonumber(scripted.value(actor, "contactRadius", contact)) or contact
        hold = tonumber(scripted.value(actor, "contactHoldMs", hold)) or hold
    end
    return warn, close, contact, hold, type(r) == "table" and type(r.horn) == "table" and r.horn or nil
end

Careful.hornKey = { CAREFUL_KEEP_BACK = "keepBack", CAREFUL_LAST_WARNING = "lastWarning",
    CAREFUL_HOSTILE = "hostile" }
function Careful.hornFor(horn, event)
    if type(horn) ~= "table" then return nil end
    local name = horn[Careful.hornKey[event] or ""]
    return type(name) == "string" and name or nil
end

Careful.settings.relayBeyond = 24
Careful.fallbackWords = {
    CAREFUL_KEEP_BACK = "This area's closed, go back out the way you came",
    CAREFUL_KEEP_BACK_FIGHTING = "We're busy here, stay back till it's over",
    CAREFUL_LAST_WARNING = "Last warning, get out of here, NOW",
    CAREFUL_HOSTILE = "Back off!",
}

Careful.heardWords = {
    CAREFUL_KEEP_BACK = "You hear people up ahead shouting at you to turn back",
    CAREFUL_KEEP_BACK_FIGHTING = "You hear fighting ahead, and somebody in it yelling at you to keep away",
    CAREFUL_LAST_WARNING = "They're shouting again, sounds like the last warning",
    CAREFUL_HOSTILE = "They're shouting at you to back off, get away from there",
}

function Careful.sayOutLoud(shell, text, radius)
    if shell == nil or type(text) ~= "string" or text == "" then return false end
    if type(isServer) == "function" and isServer() then
        local speech = ProjectALife.Speech
        return speech ~= nil and type(speech.say) == "function"
            and speech.say(shell, text, { earshot = radius }) == true
    end
    if type(shell.Say) ~= "function" then return false end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.mayVoice) == "function" and not speech.mayVoice(shell, false) then return false end
    if speech ~= nil and type(speech.sayLine) == "function" then return speech.sayLine(shell, text, "directed") == true end
    local said = false
    pcall(function()
        shell:Say(text)
        said = true
    end)
    return said
end

function Careful.relay(shell, player, text)
    if player == nil or type(text) ~= "string" or text == "" then return false end
    if distanceTo(shell, player) <= Careful.settings.relayBeyond then return false end
    local shown = false
    pcall(function()
        if player.isLocalPlayer ~= nil and player:isLocalPlayer() ~= true then return end

        if type(player.setHaloNote) == "function" then
            player:setHaloNote(text, 255, 96, 64, 420)
            shown = true
        elseif HaloTextHelper ~= nil and type(HaloTextHelper.addBadText) == "function" then
            HaloTextHelper.addBadText(player, text)
            shown = true
        end
    end)
    if shown then Careful.metrics.relayed = (Careful.metrics.relayed or 0) + 1 end
    return shown
end

function Careful.speak(actor, shell, event, player)
    local _w, _c, _t, _h, horn = Careful.radiiFor(actor)
    local name = Careful.hornFor(horn, event)
    local text, textShown
    local server = type(isServer) == "function" and isServer()
    if name == nil and not server then
        pcall(function()
            local voice = ProjectALife.Voice
            if voice == nil or type(voice.play) ~= "function" then return end
            local ok, info = voice.play(shell, event, { force = true, ignoreBarkThrottle = true, textEnabled = false })
            if ok and type(info) == "table" then text = info.text; textShown = text ~= nil end
        end)
    elseif name ~= nil and ProjectALife.AudioPolicy.allowsNPC() then
        Careful.metrics.horn = (Careful.metrics.horn or 0) + 1
        pcall(function()
            if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
                sendPlaySound(name, false, shell)
            else
                shell:getEmitter():playSound(name)
            end
        end)
    end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.corpusCaption) == "function" then
        text = speech.corpusCaption(shell, event, actor.uid)
    end

    text = text or Careful.fallbackWords[event]
    if not textShown and Careful.sayOutLoud(shell, text, math.max(40, _w)) then
        Careful.metrics.said = (Careful.metrics.said or 0) + 1
    end

    Careful.relay(shell, player, Careful.heardWords[event] or text)
end

function Careful.speakFromSite(actor, shell, event, player, ladder)
    local now = nowMs()
    ladder = ladder or Careful.ladders[Careful.ladderKey(actor, player)]
    local speakerActor, speakerShell = actor, shell
    pcall(function()
        local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
        if registry == nil or type(registry.each) ~= "function" or watchdog == nil
                or type(watchdog.bindings) ~= "table" then
            return
        end
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local groupId, outpostId = memory.groupId, memory.outpostId
        if groupId == nil and outpostId == nil then return end
        local candidates = {}
        registry.each(function(record)
            local m = type(record.memory) == "table" and record.memory or {}
            if record.lifecycle ~= "active" then return end
            if not ((groupId ~= nil and m.groupId == groupId)
                    or (outpostId ~= nil and m.outpostId == outpostId)) then
                return
            end
            local binding = watchdog.bindings[record.uid]
            local other = binding ~= nil and binding.shell or nil
            if other == nil then return end
            if player ~= nil and not sees(other, player, distanceTo(other, player)) then return end
            candidates[#candidates + 1] = { uid = tostring(record.uid), actor = record, shell = other }
        end)
        if #candidates == 0 then return end
        table.sort(candidates, function(a, b) return a.uid < b.uid end)
        local turn = (ladder ~= nil and tonumber(ladder.turn) or 0) + 1
        if ladder ~= nil then ladder.turn = turn end
        local pick = nil
        if ladder ~= nil and ladder.speakerUid ~= nil then
            for _, candidate in ipairs(candidates) do
                if candidate.uid == ladder.speakerUid then pick = candidate break end
            end
        end
        if pick == nil then
            pick = candidates[((turn - 1) % #candidates) + 1]
            if ladder ~= nil then ladder.speakerUid = pick.uid end
        end
        speakerActor, speakerShell = pick.actor, pick.shell
    end)
    if ladder ~= nil then ladder.nextNagAtMs = now + Careful.settings.nagMs end
    Careful.speak(speakerActor, speakerShell, event, player)
    return speakerActor
end

function Careful.alreadyTurned(memory, playerKey)
    if type(memory) ~= "table" or type(memory.hostileToPlayerKeys) ~= "table"
            or memory.hostileToPlayerKeys[playerKey] ~= true then
        return false
    end
    local truce = memory.robberyTruce
    return not truce or (type(truce) == "table" and truce[playerKey] == nil)
end

function Careful.writeTurned(registry, members, playerKey)
    local function mutation(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        if playerKey ~= nil then
            if ProjectALife.CalmDown ~= nil then ProjectALife.CalmDown.stamp(record, playerKey) end
            if record.memory.robberyTruce then record.memory.robberyTruce[playerKey] = nil end
            if type(record.memory.standoffTruce) == "table" then record.memory.standoffTruce[playerKey] = nil end
            record.memory.hostileToPlayerKeys =
                type(record.memory.hostileToPlayerKeys) == "table"
                and record.memory.hostileToPlayerKeys or {}
            record.memory.hostileToPlayerKeys[playerKey] = true
        end
        record.memory.carefulTurnedAtMs = nowMs()
    end
    if type(registry.updateMany) ~= "function" then
        for _, uid in ipairs(members) do
            local current = registry.read(uid)
            if current ~= nil then registry.update(current.uid, current.revision, mutation) end
        end
        return
    end
    local look = type(registry.peek) == "function" and registry.peek or registry.read
    local pending = {}
    for _, uid in ipairs(members) do
        local record = look(uid)
        if record ~= nil and not Careful.alreadyTurned(record.memory, playerKey) then
            pending[#pending + 1] = uid
        end
    end
    if #pending > 0 then registry.updateMany(pending, mutation) end
end

local function turnGroup(actor, shell, player, quiet)
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.isSelfDefence) == "function"
            and relations.isSelfDefence(player, actor) then return false end
    local reputation = ProjectALife.Reputation
    local playerKey = Careful.playerKey(player)

    if playerKey == nil then return false end
    local groupId = type(actor.memory) == "table" and actor.memory.groupId or nil

    local outpostId = type(actor.memory) == "table" and actor.memory.outpostId or nil
    local members = {}
    registry.each(function(record)
        local memory = type(record.memory) == "table" and record.memory or {}
        if record.lifecycle == "active" and (record.uid == actor.uid
                or (groupId ~= nil and memory.groupId == groupId)
                or (outpostId ~= nil and memory.outpostId == outpostId))
                and (record.uid == actor.uid or (relations ~= nil and type(relations.witnesses) == "function"
                    and relations.witnesses(record, actor, player))) then
            members[#members + 1] = record.uid
        end
    end)
    Careful.writeTurned(registry, members, playerKey)
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.breakTruce) == "function" then pcall(standoff.breakTruce, actor, playerKey) end

    if reputation ~= nil and type(reputation.onPlayerProvoked) == "function" then
        pcall(reputation.onPlayerProvoked, player, actor)
    end
    Careful.metrics.turned = Careful.metrics.turned + 1
    if quiet ~= true then Careful.speakFromSite(actor, shell, "CAREFUL_HOSTILE", player) end
    pcall(function()
        local perception = ProjectALife.Perception

        if perception ~= nil and type(perception.forgetIgnored) == "function" then
            for _, uid in ipairs(members) do perception.forgetIgnored(uid) end
        end
    end)

    if outpostId ~= nil then
        pcall(function()
            local radio, sites = ProjectALife.OutpostRadio, ProjectALife.OutpostRegistry
            local site = sites ~= nil and sites.read(tostring(outpostId)) or nil
            if radio == nil or type(radio.alarm) ~= "function" or site == nil then return end
            local px, py, pz = player:getX(), player:getY(), player:getZ()
            Careful.metrics.alarms = (Careful.metrics.alarms or 0)
                + radio.alarm(site, { x = px, y = py, z = pz, playerKey = playerKey }, nowMs(), true)
        end)
    end
    return true
end

Careful.turnGroup = turnGroup

function Careful.escalationAllowed(now)
    local fair = ProjectALife.Fairness
    return fair == nil or type(fair.hostileOff) ~= "function" or fair.hostileOff(now) ~= true
end

function Careful.stanceFor(actor, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return "neutral" end
    return relations.playerStance(actor, player)
end

function Careful.noteShout(actor, shell, player)

    return Careful.hearShout(actor, shell, player, nowMs())
end

Careful.noise = {}
function Careful.hearShout(actor, shell, player, now)
    if type(isClient) == "function" and isClient() then return false end
    if actor == nil or shell == nil or not visible(player) or distanceTo(shell, player) > 20 then return false end
    local stance = Careful.stanceFor(actor, player)
    if stance ~= "careful" and stance ~= "neutral" then return false end
    local speech = ProjectALife.Speech
    local playerKey = Careful.playerKey(player)
    if playerKey == nil then return false end
    now = now or nowMs()
    local count = 0
    for key, entry in pairs(Careful.noise) do
        if now - entry.atMs > 120000 then Careful.noise[key] = nil else count = count + 1 end
    end
    local key = tostring(groupOf(actor)) .. ":" .. playerKey
    local entry = Careful.noise[key]
    if entry and now - entry.atMs < 600 then return true end
    if entry == nil and count >= 256 then return false end
    entry = entry or { count = 0 }
    entry.count, entry.atMs = entry.count + 1, now
    Careful.noise[key] = entry
    Careful.metrics.shouts = Careful.metrics.shouts + 1
    local words = {
        "Keep your voice down. I don't want trouble finding us",
        "We heard you the first time, quit yelling!",
        "Seriously? You'll get us all killed, shut it!",
        "Last warning, yell again and we're done being nice",
        "That's it- you had your chances!",
    }

    if entry.count >= 5 and stance == "careful" and Careful.escalationAllowed(now) then turnGroup(actor, shell, player) end
    local line = math.min(stance == "careful" and 5 or 3, entry.count)
    if speech and speech.say then speech.say(shell, words[line], { chat = true }) end
    return true
end

function Careful.evaluateActor(actor, shell, context, now)
    return nil
end

function Careful.proximitySuspended(actor, player, now)
    local memory, key = actor.memory or {}, Careful.playerKey(player)
    if key == nil then return true end

    local robbery = memory.robbery
    if type(robbery) == "table" then
        local module = ProjectALife.ModuleRobbery
        if module ~= nil and type(module.activeFor) == "function" then
            local ok, holding = pcall(module.activeFor, actor, key)
            if ok and holding == true then return true end
        elseif robbery.playerKey == key and robbery.phase ~= "execute" then
            return true
        end
    end
    return type(memory.robberyTruce) == "table" and (tonumber(memory.robberyTruce[key]) or 0) > now
end

function Careful.territoryFor(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" or memory.outpostId == nil or memory.outpostSquadId ~= nil then return nil end
    local sites = ProjectALife.OutpostRegistry
    if sites == nil or type(sites.read) ~= "function" then return nil end
    local site = sites.read(tostring(memory.outpostId))
    if type(site) ~= "table" or site.state == "expired" or site.state == "cleared" then return nil end
    local bounds = site.bounds
    if type(bounds) ~= "table" or type(bounds.x1) ~= "number" or type(bounds.y1) ~= "number"
            or type(bounds.x2) ~= "number" or type(bounds.y2) ~= "number"
            or bounds.x2 <= bounds.x1 or bounds.y2 <= bounds.y1 then return nil end
    return bounds
end

function Careful.inTerritory(territory, player)
    if type(territory) ~= "table" or player == nil or type(player.getX) ~= "function"
            or type(player.getY) ~= "function" or type(player.getZ) ~= "function" then return false end
    local x, y, z = player:getX(), player:getY(), player:getZ()
    return type(x) == "number" and type(y) == "number" and type(z) == "number"
        and math.floor(z) == math.floor(tonumber(territory.z) or 0)
        and x >= territory.x1 and x <= territory.x2 and y >= territory.y1 and y <= territory.y2
end

function Careful.territorialFacts(actor, player, now)
    local territory = Careful.territoryFor(actor)
    if not Careful.inTerritory(territory, player) then return false, false end
    local ladder = Careful.ladders[Careful.ladderKey(actor, player)]
    now = tonumber(now) or nowMs()
    local warned = ladder ~= nil and ladder.step >= 2
        and now >= ladder.atMs + Careful.settings.warningGraceMs
        and now - (ladder.lastInsideAtMs or ladder.atMs) <= Careful.settings.forgetMs
    return true, warned
end

function Careful.rememberWarning(ladder, shell, player, now, territory)
    ladder.atMs = now
    ladder.playerX, ladder.playerY = player:getX(), player:getY()
    ladder.guardX, ladder.guardY = (territory.x1 + territory.x2) / 2, (territory.y1 + territory.y2) / 2
    ladder.warningDistance = math.sqrt((ladder.playerX-ladder.guardX)^2+(ladder.playerY-ladder.guardY)^2)
    ladder.contactSinceMs = nil

    ladder.approach, ladder.approachSinceLast, ladder.lastDistance = 0, nil, nil
    ladder.trackX, ladder.trackY = ladder.playerX, ladder.playerY
    ladder.trackGX, ladder.trackGY = ladder.guardX, ladder.guardY
end

function Careful.rememberLastWarning(ladder, player, gx, gy)
    if gx == nil or gy == nil then return end
    ladder.lastDistance = math.sqrt((player:getX()-gx)^2+(player:getY()-gy)^2)
    ladder.approachSinceLast = 0
end

function Careful.trackApproach(ladder, player, gx, gy, radius)
    if ladder.trackX == nil or gx == nil or gy == nil then return end
    local x, y = player:getX(), player:getY()
    local px, py = ladder.trackX, ladder.trackY
    local before = math.sqrt((px-gx)^2+(py-gy)^2)
    local after = math.sqrt((x-gx)^2+(y-gy)^2)
    local drift = math.sqrt((px-ladder.trackGX)^2+(py-ladder.trackGY)^2) - before
    if drift > 0 then drift = 0 end
    ladder.approach = (tonumber(ladder.approach) or 0) + before - after + drift
    if ladder.approachSinceLast ~= nil then
        if tonumber(radius) ~= nil and after <= radius then drift = 0 end
        ladder.approachSinceLast = ladder.approachSinceLast + before - after + drift
    end
    ladder.trackX, ladder.trackY, ladder.trackGX, ladder.trackGY = x, y, gx, gy
end

function Careful.xyOf(shell) return shell:getX(), shell:getY() end

function Careful.guardPoint(ladder)
    return ladder.guardX, ladder.guardY
end

function Careful.playerAdvanced(ladder)
    if ladder.playerX == nil then return false end
    return (tonumber(ladder.approach) or 0) >= Careful.settings.advanceTiles
end

function Careful.pressedOn(ladder, player, gx, gy, radius)
    if ladder.playerX == nil or gx == nil or gy == nil then return false end
    if (player:getX()-gx)^2 + (player:getY()-gy)^2 > radius^2 then return false end
    local step = Careful.settings.advanceTiles
    if (tonumber(ladder.approach) or 0)
            >= math.max(step, (tonumber(ladder.warningDistance) or 0) - radius) then
        return true
    end
    local since = ladder.approachSinceLast
    return since ~= nil and since >= math.max(step, (tonumber(ladder.lastDistance) or 0) - radius)
end

function Careful.walkingLeg(actor)
    local loop = ProjectALife.DecisionLoop
    local states = loop ~= nil and type(loop.states) == "table" and loop.states or nil
    local state = states ~= nil and type(actor) == "table" and states[actor.uid] or nil
    if type(state) ~= "table" or state.kind == "combat" then return false end
    local action = state.action
    return type(action) == "table" and action.status == "running"
end

function Careful.inCombat(actor)
    local talk = ProjectALife.Talk
    if talk == nil then return false end
    local ask = talk.inFight
    if type(ask) ~= "function" then ask = talk.inCombat end
    if type(ask) ~= "function" then return false end
    local ok, fighting = pcall(ask, actor)
    return ok and fighting == true
end

Careful.settings.fightHoldMs = 3000
Careful.settings.fightGraceMs = 4000
function Careful.fightHolds(ladder, actor, shell, player, fighting, now, territory)
    if ladder.step >= 3 then return false end
    local s = Careful.settings
    if fighting then ladder.fightUntilMs = now + s.fightHoldMs end
    local untilMs = tonumber(ladder.fightUntilMs)
    if untilMs == nil then return false end
    if now < untilMs + s.fightGraceMs then
        ladder.contactSinceMs = nil
        if fighting and ladder.coopSaid ~= true then
            ladder.coopSaid = true
            Careful.sayCoop(actor, shell)
        end
        return true
    end
    ladder.fightUntilMs, ladder.coopSaid = nil, nil
    territory = territory or Careful.territoryFor(actor)
    if ladder.step >= 1 and territory ~= nil then Careful.rememberWarning(ladder, shell, player, now, territory) end
    return false
end

function Careful.sayCoop(actor, shell)
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.coopLine) ~= "function" then return false end
    local warn = Careful.radiiFor(actor)
    if not Careful.sayOutLoud(shell, talk.coopLine(), math.max(40, warn)) then return false end
    Careful.metrics.coop = (Careful.metrics.coop or 0) + 1
    return true
end

Careful.settings.homeWarnCooldownMs = 600000
Careful.homeWarned = {}
Careful.homeNoted = {}

function Careful.homeStatus(actor, shell, player)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.insideHome) ~= "function" then return nil end
    local own = policy.insideHome(actor, shell)
    if own ~= nil then return "inside", own end
    local theirs, building = policy.insideHome(actor, player)
    if theirs ~= nil then return "home", theirs, building end
    return nil
end

function Careful.noteHome(actor, kind, now)
    local last = Careful.homeNoted[actor.uid]
    if last ~= nil and now >= last and now - last < 5000 then return end
    if last == nil then
        Careful.homeNotedSize = (Careful.homeNotedSize or 0) + 1
        if Careful.homeNotedSize > 256 then Careful.homeNoted, Careful.homeNotedSize = {}, 1 end
    end
    Careful.homeNoted[actor.uid] = now
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.note) == "function" then policy.note("warn", kind) end
end

function Careful.warnFromOutside(actor, shell, player, ladder, kind, building, now)
    local policy = ProjectALife.DoorPolicy
    local id = building ~= nil and type(policy.buildingKey) == "function" and policy.buildingKey(building) or kind
    local key = Careful.ladderKey(actor, player) .. "|" .. tostring(id)
    if now < (Careful.homeWarned[key] or 0) then return nil end
    local count = 0
    for oldKey, untilMs in pairs(Careful.homeWarned) do
        if now >= untilMs then Careful.homeWarned[oldKey] = nil else count = count + 1 end
    end
    if count >= 64 then Careful.homeWarned = {} end
    Careful.homeWarned[key] = now + Careful.settings.homeWarnCooldownMs
    ladder.step, ladder.atMs, ladder.contactSinceMs = 1, now, nil
    ladder.guardUid = actor.uid
    Careful.metrics.warnings = Careful.metrics.warnings + 1
    Careful.metrics.homeWarnings = (Careful.metrics.homeWarnings or 0) + 1
    if not Careful.walkingLeg(actor) then
        face(shell, player)
    end
    Careful.speakFromSite(actor, shell, "CAREFUL_KEEP_BACK", player, ladder)
    return nil
end

function Careful.evaluate(actor, shell, context)

    if type(isClient) == "function" and isClient() then return nil end
    if not Registry.allows(actor, "careful") then return nil end
    local now = tonumber(context and context.now) or nowMs()
    local territory = Careful.territoryFor(actor)
    if territory == nil then return nil end

    local fighting = Careful.inCombat(actor)
    local nearest, nearestDistance = nil, math.huge

    local warnRadius, closeRadius, contactRadius, contactHoldMs = Careful.radiiFor(actor)
    for _, player in ipairs(players()) do
        if not Careful.inTerritory(territory, player) or not visible(player) then
            Careful.ladders[Careful.ladderKey(actor, player)] = nil
        end
        local d = distanceTo(shell, player)
        if d <= warnRadius and d < nearestDistance and visible(player) and Careful.inTerritory(territory, player)
                and not Careful.proximitySuspended(actor, player, now)
                and Careful.stanceFor(actor, player) == "careful" then
            nearest, nearestDistance = player, d
        end
    end
    if nearest == nil or nearestDistance > warnRadius then
        return Careful.evaluateActor(actor, shell, context, now)
    end
    if not sees(shell, nearest, nearestDistance) then return nil end
    local home, homeKind, homeBuilding = Careful.homeStatus(actor, shell, nearest)
    if home == "inside" then
        Careful.noteHome(actor, homeKind, now)
        return nil
    end
    local ladder, key = ladderFor(actor, now, nearest)

    ladder.lastInsideAtMs = now
    if home == "home" then
        Careful.noteHome(actor, homeKind, now)
        return Careful.warnFromOutside(actor, shell, nearest, ladder, homeKind, homeBuilding, now)
    end
    local gx, gy = Careful.guardPoint(ladder)
    Careful.trackApproach(ladder, nearest, gx, gy, contactRadius)
    if Careful.fightHolds(ladder, actor, shell, nearest, fighting, now, territory) then return nil end

    if ladder.step >= 2 and now - ladder.atMs >= Careful.settings.warningGraceMs then
        ladder.contactSinceMs = ladder.contactSinceMs or now
        if ladder.contactSinceMs ~= nil and now - ladder.contactSinceMs >= contactHoldMs then
            if not Careful.escalationAllowed(now) then
                ladder.contactSinceMs = now
            else
                turnGroup(actor, shell, nearest)
                ladder.step, ladder.atMs = 3, now
                return nil
            end
        end
    else
        ladder.contactSinceMs = nil
    end
    if ladder.step >= 3 then return nil end

    local posed = not Careful.walkingLeg(actor)
    if posed then face(shell, nearest) end
    local spoke = false
    if ladder.step == 0 then
        ladder.step = 1
        Careful.rememberWarning(ladder, shell, nearest, now, territory)
        ladder.guardUid = actor.uid
        Careful.metrics.warnings = Careful.metrics.warnings + 1
        Careful.speakFromSite(actor, shell, "CAREFUL_KEEP_BACK", nearest, ladder)
        spoke = true
    elseif ladder.step == 1 and now - ladder.atMs >= Careful.settings.warningGraceMs then
        ladder.step = 2

        ladder.atMs, ladder.contactSinceMs = now, nil
        Careful.rememberLastWarning(ladder, nearest, gx, gy)
        Careful.metrics.lastWarnings = Careful.metrics.lastWarnings + 1
        Careful.speakFromSite(actor, shell, "CAREFUL_LAST_WARNING", nearest, ladder)
        spoke = true
    elseif ladder.step >= 1 and now >= (ladder.nextNagAtMs or math.huge) then

        Careful.metrics.nags = (Careful.metrics.nags or 0) + 1
        local script = ProjectALife.EncounterScript
        if script ~= nil and script.enabled() then
            ladder.nextNagAtMs = now + Careful.settings.nagMs
        else
            Careful.speakFromSite(actor, shell,
                ladder.step ~= 1 and "CAREFUL_LAST_WARNING" or "CAREFUL_KEEP_BACK",
                nearest, ladder)
        end
        spoke = true
    end
    if spoke and ProjectALife.Investigation ~= nil and type(ProjectALife.Investigation.alert) == "function" then
        ProjectALife.Investigation.alert(actor, ladder.step >= 2 and "red" or "yellow", now)
    end
    if spoke and posed then challenge(shell) end

    return nil
end

function Careful.authoritative()
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.authoritative) == "function" then
        return speech.authoritative() == true
    end
    return not (type(isClient) == "function" and isClient())
end

Careful.serverCursor = 1
function Careful.serverTick(now)
    if not Careful.authoritative() then return 0 end
    local watchdog, actors = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    if watchdog == nil or actors == nil then return 0 end
    local order, processed, visited, started = watchdog.order or {}, 0, 0, nowMs()
    while visited < math.min(8, #order) and processed < 4 do
        if visited > 0 and nowMs() - started >= 3 then break end
        if Careful.serverCursor > #order then Careful.serverCursor = 1 end
        local uid = order[Careful.serverCursor]
        Careful.serverCursor, visited = Careful.serverCursor + 1, visited + 1
        local binding = watchdog.bindings and watchdog.bindings[uid]
        local actor = type(actors.peek) == "function" and actors.peek(uid) or actors.read(uid)
        if actor and actor.lifecycle == "active" and binding and binding.shell then
            Careful.evaluate(actor, binding.shell, { now = now or started })
            processed = processed + 1
        end
    end
    return processed
end

function Careful.reset()
    Careful.ladders = {}
    Careful.noise = {}
    Careful.nextPruneMs = nil
    Careful.homeWarned, Careful.homeNoted, Careful.homeNotedSize = {}, {}, 0
    Careful.serverCursor = 1
    Careful.sightCache = setmetatable({}, { __mode = "k" })
    Careful.metrics = { warnings = 0, lastWarnings = 0, turned = 0, shouts = 0 }
end

Registry.register({
    id = "careful",
    kind = "orders",
    dispatch = "decision",

    priority = 5,
    label = "Careful relation",
    summary = "A faction that is careful with the player warns at range, warns again closer, and turns hostile when the warnings are walked through or shouted over.",
    defaultEnabled = true,
    evaluate = Careful.evaluate,
})

Careful.turnGroup = turnGroup

local function uidOfShell(shell)
    local uid
    pcall(function()
        local data = shell:getModData()
        uid = data ~= nil and data.ProjectALifeUID or nil
        if uid == nil then uid = shell:GetVariable("ALifeUID") end
    end)
    if uid == nil or tostring(uid) == "" then return nil end
    return tostring(uid)
end

function Careful.onHitByPlayer(player, shell, actor)
    if player == nil or shell == nil then return false end
    if type(instanceof) == "function" and not instanceof(player, "IsoPlayer") then return false end
    local registry = ProjectALife.ActorRegistry
    if type(actor) ~= "table" then
        if registry == nil then return false end
        local uid = uidOfShell(shell)
        if uid == nil then return false end
        actor = registry.read(uid)
    end
    if type(actor) ~= "table" or actor.lifecycle ~= "active" then return false end
    local key = Careful.playerKey(player)
    if key == nil then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}

    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then return false end

    if type(memory.robbery) == "table" and memory.robbery.playerKey == key then return false end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.hostileToPlayer) == "function" then
        local already
        pcall(function() already = relations.hostileToPlayer(actor, player) end)
        if already == true then return false end
    end

    local ladderKey = Careful.ladderKey(actor, player)
    if ladderKey ~= nil then Careful.ladders[ladderKey] = nil end
    turnGroup(actor, shell, player, true)
    return true
end

Careful.echoRadius = 20
Careful.echoCap = 6
function Careful.echo(actor, shell, text)
    if type(actor) ~= "table" or shell == nil or type(text) ~= "string" or text == "" then return 0 end
    local registry = ProjectALife.ActorRegistry
    local watchdog = ProjectALife.Watchdog
    if registry == nil or type(registry.each) ~= "function" or watchdog == nil
            or type(watchdog.bindings) ~= "table" then
        return 0
    end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local groupId, outpostId = memory.groupId, memory.outpostId
    if groupId == nil and outpostId == nil then return 0 end
    local sx, sy
    pcall(function() sx, sy = shell:getX(), shell:getY() end)
    if sx == nil then return 0 end
    local reach = Careful.echoRadius * Careful.echoRadius
    local said = 0
    registry.each(function(record)
        if said >= Careful.echoCap then return true end
        local m = type(record.memory) == "table" and record.memory or {}
        if record.lifecycle ~= "active" or record.uid == actor.uid then return end
        if not ((groupId ~= nil and m.groupId == groupId) or (outpostId ~= nil and m.outpostId == outpostId)) then return end
        local binding = watchdog.bindings[record.uid]
        local other = binding ~= nil and binding.shell or nil
        if other == nil or other == shell then return end
        local ox, oy
        pcall(function() ox, oy = other:getX(), other:getY() end)
        if ox == nil or (ox - sx) ^ 2 + (oy - sy) ^ 2 > reach then return end
        if Careful.sayOutLoud(other, text) then said = said + 1 end
    end)
    if said > 0 then Careful.metrics.echoed = (Careful.metrics.echoed or 0) + said end
    return said
end

return Careful
