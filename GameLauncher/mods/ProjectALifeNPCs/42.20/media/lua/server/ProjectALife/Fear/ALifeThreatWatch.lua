require "ProjectALife/Combat/ALifeLineOfFire"

ProjectALife = ProjectALife or {}

local Watch = {
    settings = {
        enabled = true,
        tickMs = 400,

        aimRange = 16,

        aimSlackDegrees = 16,
        bodyHalfWidth = 0.35,

        pointBlank = 2,

        drawRange = 10,

        stowedMemoryMs = 120000,

        reactCooldownMs = 20000,

        friendlyGraceMs = 20000,

        reportMs = 2500,

        fightAimFilter = true,
        fightAimSlackDegrees = 4,
        fightAimHoldMs = 1200,
        fightLineCooldownMs = 10000,

        relaxEnabled = true,
        relaxRange = 30,
        aimMatchTiles = 2,
        coneDegrees = 25,
        lowerDelayMs = 1500,
        noAimMs = 6000,
        carefulAimMs = 14000,
        episodeGapMs = 3000,
    },
    metrics = { aimed = 0, drew = 0, turned = 0, warned = 0, scans = 0, fightIgnored = 0, fightLines = 0,
        lowered = 0, keptHostile = 0, keptAggressor = 0, keptCareful = 0, carefulExpired = 0 },
    aimSince = {},
    aimSeen = {},

    hands = {},

    reacted = {},

    held = {},
    fightLineCount = 0,
    lastTickAtMs = 0,
    nextPruneAtMs = 0,
}
ProjectALife.ThreatWatch = Watch

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function position(object)
    local x, y, z
    pcall(function() x, y, z = object:getX(), object:getY(), object:getZ() end)
    return x, y, z
end

local function alive(object)
    if object == nil then return false end
    local ok, dead = pcall(function() return object:isDead() end)
    return ok and dead ~= true
end

function Watch.weaponOf(player)
    local fullType, ranged = nil, false
    pcall(function()
        local hands = { player:getPrimaryHandItem(), player:getSecondaryHandItem() }
        for index = 1, 2 do
            local item = hands[index]
            if item ~= nil and instanceof(item, "HandWeapon") then
                local id = tostring(item:getFullType())
                if id ~= "Base.BareHands" then
                    fullType = id
                    if item:isRanged() == true then ranged = true end
                end
            end
        end
    end)
    return fullType, ranged
end

function Watch.aiming(player, entry, now)

    if entry ~= nil and entry.reportAtMs ~= nil and now - entry.reportAtMs <= Watch.settings.reportMs then
        return entry.aiming == true
    end
    local aiming = false
    pcall(function() aiming = player:isAiming() == true end)
    return aiming
end

function Watch.onPlayerState(player, args)
    local speech = ProjectALife.Speech
    if speech == nil or type(args) ~= "table" then return false end
    local key = speech.playerKey(player)
    if key == nil then return false end
    local entry = Watch.hands[key] or {}
    entry.aiming = args.aiming == true
    entry.reportAtMs = nowMs()
    Watch.hands[key] = entry
    return true
end

function Watch.aimedAt(player, shell, range, slackDegrees, pointBlank)
    local px, py, pz = position(player)
    local sx, sy, sz = position(shell)
    if px == nil or sx == nil then return false end
    if math.abs((sz or 0) - (pz or 0)) > 0.5 then return false end
    local dx, dy = sx - px, sy - py
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.1 or distance > (tonumber(range) or Watch.settings.aimRange) then return false end
    if distance > (tonumber(pointBlank) or 0) then
        local laid = false
        pcall(function()
            local facing = player:getForwardDirection()
            local fx, fy = facing:getX(), facing:getY()
            local length = math.sqrt(fx * fx + fy * fy)
            if length < 0.001 then return end
            local body = math.deg(math.atan(Watch.settings.bodyHalfWidth / distance))
            local allowed = math.min(180, (tonumber(slackDegrees) or Watch.settings.aimSlackDegrees) + body)
            laid = (dx * fx + dy * fy) / (distance * length) >= math.cos(math.rad(allowed))
        end)
        if not laid then return false end
    end
    local line = ProjectALife.LineOfFire
    local ray
    if line ~= nil and type(line.tileRayClear) == "function" then ray = line.tileRayClear(shell, player) end
    if ray ~= nil then return ray end

    local watcher = ProjectALife.Perception
    if watcher ~= nil and type(watcher.engineCanSee) == "function" then
        return watcher.engineCanSee(shell, player) == true
    end
    local ok, seen = pcall(shell.CanSee, shell, player)
    return ok and seen == true
end

function Watch.underTheGun(player, shell, now)
    return Watch.aimedAt(player, shell, Watch.settings.aimRange,
        Watch.settings.aimSlackDegrees, Watch.settings.pointBlank)
end

function Watch.shellFor(uid)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.shellFor) == "function" then return talk.shellFor(uid) end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    return binding ~= nil and binding.shell or nil
end

local function groupKey(record)
    local memory = type(record.memory) == "table" and record.memory or {}
    return tostring(memory.groupId or memory.outpostId or record.uid)
end

function Watch.fightingOther(record, playerKey, now)
    if type(record) ~= "table" then return false end
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.inFight) == "function" and talk.inFight(record, now) == true then
        local memory = type(record.memory) == "table" and record.memory or {}
        if memory.combatTargetKind ~= "player" then return true end
        return memory.combatTargetPlayerKey ~= nil and memory.combatTargetPlayerKey ~= playerKey
    end
    local loop = ProjectALife.DecisionLoop
    local states = loop ~= nil and type(loop.states) == "table" and loop.states or nil
    local state = states ~= nil and record.uid ~= nil and states[record.uid] or nil
    return type(state) == "table" and state.threatKind == "zombie"
end

function Watch.fightFiltered(record, player, now)
    if Watch.settings.fightAimFilter ~= true or player == nil then return false end
    local speech = ProjectALife.Speech
    local key = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(player) or nil
    return Watch.fightingOther(record, key, tonumber(now) or nowMs())
end

Watch.fightLines = {
    "Don't aim at me, aim at them!",
    "Not me! Shoot them!",
    "Hey! Point that at the dead, not at me!",
    "Watch your muzzle! They're over there!",
}

function Watch.sayFightLine(record, shell, now)
    local key = "line:" .. tostring(record.uid)
    if now < (Watch.reacted[key] or 0) then return false end
    Watch.reacted[key] = now + Watch.settings.fightLineCooldownMs
    local careful = ProjectALife.ModuleCareful
    if careful == nil or type(careful.sayOutLoud) ~= "function" then return false end
    Watch.fightLineCount = Watch.fightLineCount + 1
    local lines = Watch.fightLines
    local text = lines[(Watch.fightLineCount - 1) % #lines + 1]
    if careful.sayOutLoud(shell, text, 20) ~= true then return false end
    Watch.metrics.fightLines = (Watch.metrics.fightLines or 0) + 1
    return true
end

function Watch.fightAim(record, shell, player, playerKey, now)
    local s = Watch.settings
    local holdKey = tostring(playerKey) .. ":" .. tostring(record.uid)
    if not Watch.aimedAt(player, shell, s.aimRange, s.fightAimSlackDegrees, 0) then
        Watch.held[holdKey] = nil
        Watch.metrics.fightIgnored = (Watch.metrics.fightIgnored or 0) + 1
        return false
    end
    local held = Watch.held[holdKey]
    if held == nil or now - held.seenMs > s.tickMs * 2 + 200 then
        held = { sinceMs = now, seenMs = now }
        Watch.held[holdKey] = held
    end
    held.seenMs = now
    if now - held.sinceMs < s.fightAimHoldMs then return false end
    return Watch.sayFightLine(record, shell, now)
end

function Watch.react(record, shell, player, kind, now)
    local relations, careful = ProjectALife.Relations, ProjectALife.ModuleCareful
    if relations ~= nil and type(relations.hostileToPlayer) == "function" then
        local hostile
        pcall(function() hostile = relations.hostileToPlayer(record, player) end)
        if hostile == true then return false end
    end
    local speech = ProjectALife.Speech
    local key = speech ~= nil and speech.playerKey(player) or nil
    if key == nil then return false end
    local crewKey = tostring(key) .. ":" .. groupKey(record)
    if now < (Watch.reacted[crewKey] or 0) then return false end
    Watch.reacted[crewKey] = now + Watch.settings.reactCooldownMs
    local talk = ProjectALife.Talk
    local stance = talk ~= nil and type(talk.stance) == "function" and talk.stance(record, player) or "careful"
    local warnedKey = crewKey .. ":warned"

    if now >= (Watch.reacted[warnedKey] or 0) then

        Watch.reacted[warnedKey] = now + Watch.settings.friendlyGraceMs
        Watch.metrics.warned = Watch.metrics.warned + 1
        if talk ~= nil and type(talk.bark) == "function" then
            local context = ProjectALife.Speech.contextFor(record, player)
            context.stance = stance
            pcall(talk.bark, record, shell, player, "AIMED_AT", context)
        end
        return true
    end

    if stance ~= "careful" then return true end

    local memory = type(record.memory) == "table" and record.memory or nil
    if memory == nil or type(memory.robbery) ~= "table" then return true end
    if careful == nil or type(careful.turnGroup) ~= "function" then return false end
    pcall(careful.turnGroup, record, shell, player)
    Watch.metrics.turned = Watch.metrics.turned + 1
    if kind == "aim" then Watch.metrics.aimed = Watch.metrics.aimed + 1 else Watch.metrics.drew = Watch.metrics.drew + 1 end
    return true
end

function Watch.scan(player, kind, radius, now)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    local px, py = position(player)
    if px == nil then return 0 end
    Watch.metrics.scans = Watch.metrics.scans + 1
    local reach = radius * radius
    local reacted = 0
    local speech = ProjectALife.Speech
    local playerKey = Watch.settings.fightAimFilter == true and speech ~= nil
        and type(speech.playerKey) == "function" and speech.playerKey(player) or nil
    registry.each(function(record)
        if record.lifecycle ~= "active" then return end

        local where = record.worldPosition
        if type(where) == "table" and where.x ~= nil then
            local wx, wy = tonumber(where.x) or 0, tonumber(where.y) or 0
            if (wx - px) ^ 2 + (wy - py) ^ 2 > (radius + 12) ^ 2 then return end
        end
        local shell = Watch.shellFor(record.uid)
        if shell == nil or not alive(shell) then return end
        local sx, sy = position(shell)
        if sx == nil or (sx - px) ^ 2 + (sy - py) ^ 2 > reach then return end

        if playerKey ~= nil and Watch.fightingOther(record, playerKey, now) then
            if kind == "aim" then Watch.fightAim(record, shell, player, playerKey, now) end
            return
        end
        if kind == "aim" then
            if not Watch.underTheGun(player, shell, now) then return end

            local panic = ProjectALife.ModulePanic
            if panic ~= nil and type(panic.onAimedAt) == "function" then
                pcall(panic.onAimedAt, record, shell, player, now)
            end
            local gunFear = ProjectALife.ModuleGunFear
            if gunFear ~= nil and type(gunFear.flights) == "table" and gunFear.flights[record.uid] ~= nil then return end
        end
        if kind == "draw" then

            local watcher = ProjectALife.Perception
            local seen
            if watcher ~= nil and type(watcher.engineCanSee) == "function" then
                seen = watcher.engineCanSee(shell, player) == true
            else
                local ok, answer = pcall(shell.CanSee, shell, player)
                seen = ok and answer == true
            end
            if not seen then return end
        end
        if Watch.react(record, shell, player, kind, now) then reacted = reacted + 1 end
    end)
    return reacted
end

function Watch.players()
    local presence = ProjectALife.ModuleTalkPresence
    if presence ~= nil and type(presence.players) == "function" then
        local ok, list = pcall(presence.players)
        if ok and type(list) == "table" then return list end
    end
    return {}
end

function Watch.aimTarget(shell, data, now)
    local settings = Watch.settings
    local sx, sy = position(shell)
    if sx == nil then return nil end
    local ax, ay = tonumber(data.ProjectALifeAimAtX), tonumber(data.ProjectALifeAimAtY)
    local reach = settings.relaxRange ^ 2
    local fx, fy
    if ax == nil then
        local ok = pcall(function()
            local forward = shell:getForwardDirection()
            fx, fy = forward:getX(), forward:getY()
        end)
        if not ok then fx = nil end
    end
    for _, player in ipairs(Watch.players()) do
        if alive(player) then
            local px, py = position(player)
            if px ~= nil and (px - sx) ^ 2 + (py - sy) ^ 2 <= reach then
                if ax ~= nil then
                    if (px - ax) ^ 2 + (py - ay) ^ 2 <= settings.aimMatchTiles ^ 2 then return player end
                elseif fx ~= nil then
                    local dx, dy = px - sx, py - sy
                    local length, face = math.sqrt(dx * dx + dy * dy), math.sqrt(fx * fx + fy * fy)
                    if length > 0.1 and face > 0.001
                            and (dx * fx + dy * fy) / (length * face) >= math.cos(math.rad(settings.coneDegrees)) then
                        return player
                    end
                end
            end
        end
    end
    return nil
end

function Watch.aggressor(record, shell, player, now)
    local held = ProjectALife.Perception
    held = type(held) == "table" and type(held.attackers) == "table" and held.attackers[record.uid] or nil
    if type(held) == "table" and held.attacker == player and now < (tonumber(held.untilMs) or -1e12) then
        return true
    end
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear == nil or type(gunFear.armedState) ~= "function" then return false end
    local ok, armed = pcall(gunFear.armedState, player, "player", shell, now)
    return ok and armed == "aimed"
end

function Watch.holdsIntent(record, state)
    local intent = type(state) == "table" and tostring(state.intent or "") or ""
    if string.find(intent, "robbery", 1, true) or string.find(intent, "standoff", 1, true)
            or string.find(intent, "warn", 1, true) or string.find(intent, "frisk", 1, true) then return true end
    local memory = type(record.memory) == "table" and record.memory or nil
    return memory ~= nil and type(memory.robbery) == "table"
end

function Watch.mayAim(record, shell, player, state, now)
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.hostileToPlayer) == "function" then
        local ok, hostile = pcall(relations.hostileToPlayer, record, player)
        if ok and hostile == true then return true, "hostile" end
    end
    if Watch.aggressor(record, shell, player, now) then return true, "aggressor" end
    local stance
    if relations ~= nil and type(relations.playerStance) == "function" then
        local ok, found = pcall(relations.playerStance, record, player)
        if ok then stance = found end
    end
    if stance == "careful" or Watch.holdsIntent(record, state) then
        local since = Watch.aimSince[record.uid] or now
        if now - since <= Watch.settings.carefulAimMs then return true, "careful" end
        return false, "careful_expired"
    end
    return false, "peaceful"
end

function Watch.lower(record, shell, data, now)
    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
    data.ProjectALifeNoAimUntilMs = now + Watch.settings.noAimMs
    data.ProjectALifeDangerPosture = "relaxed"
    local combat = ProjectALife.Combat
    if combat ~= nil then
        if type(combat.setAimWalk) == "function" then combat.setAimWalk(shell, false, "relaxed_aim") end
        if type(combat.postureUntilMs) == "table" then combat.postureUntilMs[shell] = nil end
        if type(combat.aimHoldUntilMs) == "table" then combat.aimHoldUntilMs[shell] = nil end
    end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.setCombatHold) == "function" then
        pcall(animations.setCombatHold, shell, false)
    end
    if type(shell.isAiming) == "function" and shell:isAiming() == true and type(shell.setIsAiming) == "function" then
        shell:setIsAiming(false)
    end
    Watch.metrics.lowered = Watch.metrics.lowered + 1
    return true
end

function Watch.relax(record, shell, state, now)
    local settings = Watch.settings
    if settings.relaxEnabled ~= true or type(record) ~= "table" or record.uid == nil or shell == nil then return false end
    if type(state) == "table" and (state.kind == "combat" or state.threatKind == "zombie") then return false end
    local data = type(shell.getModData) == "function" and shell:getModData() or nil
    if type(data) ~= "table" then return false end
    now = tonumber(now) or nowMs()
    local blocked = now < (tonumber(data.ProjectALifeNoAimUntilMs) or 0)
    local raised = data.ProjectALifeAimWalk == true or data.ProjectALifeAimAtX ~= nil
    if not raised then return false end
    local player = Watch.aimTarget(shell, data, now)
    if player == nil then return false end
    local seen = Watch.aimSeen[record.uid]
    if Watch.aimSince[record.uid] == nil or seen == nil or now - seen > settings.episodeGapMs then
        Watch.aimSince[record.uid] = now
    end
    Watch.aimSeen[record.uid] = now
    local allowed, why = Watch.mayAim(record, shell, player, state, now)
    if allowed then
        local key = why == "hostile" and "keptHostile" or why == "aggressor" and "keptAggressor" or "keptCareful"
        Watch.metrics[key] = Watch.metrics[key] + 1
        return false
    end
    if why == "careful_expired" and not blocked then Watch.metrics.carefulExpired = Watch.metrics.carefulExpired + 1 end
    if not blocked and now - Watch.aimSince[record.uid] < settings.lowerDelayMs then return false end
    return Watch.lower(record, shell, data, now)
end

function Watch.prune(now)
    if now < Watch.nextPruneAtMs then return end
    Watch.nextPruneAtMs = now + 60000
    for key, untilMs in pairs(Watch.reacted) do
        if now >= untilMs + 60000 then Watch.reacted[key] = nil end
    end
    for key, held in pairs(Watch.held) do
        if now - held.seenMs >= 60000 then Watch.held[key] = nil end
    end
    for key, seenMs in pairs(Watch.aimSeen) do
        if now - seenMs >= 60000 then Watch.aimSeen[key], Watch.aimSince[key] = nil, nil end
    end
end

function Watch.tick(now)
    now = now or nowMs()
    if Watch.settings.enabled ~= true then return 0 end
    local speech = ProjectALife.Speech
    if speech == nil or not speech.authoritative() then return 0 end
    if now - Watch.lastTickAtMs < Watch.settings.tickMs then return 0 end
    Watch.lastTickAtMs = now
    Watch.prune(now)
    local presence = ProjectALife.ModuleTalkPresence
    local players = presence ~= nil and type(presence.players) == "function" and presence.players() or {}
    local answered = 0
    for _, player in ipairs(players) do
        if alive(player) then
            local key = speech.playerKey(player)
            if key ~= nil then
                local entry = Watch.hands[key] or {}
                local weapon, ranged = Watch.weaponOf(player)

                local drew = false
                if weapon == nil then
                    if entry.weapon ~= nil then entry.stowedAtMs = now end
                elseif entry.weapon == nil and entry.stowedAtMs ~= nil
                        and now - entry.stowedAtMs <= Watch.settings.stowedMemoryMs then
                    drew = true
                end
                entry.weapon, entry.ranged = weapon, ranged
                Watch.hands[key] = entry
                if drew then
                    answered = answered + Watch.scan(player, "draw", Watch.settings.drawRange, now)
                end

                if weapon ~= nil and ranged and Watch.aiming(player, entry, now) then
                    answered = answered + Watch.scan(player, "aim", Watch.settings.aimRange, now)
                end
            end
        end
    end
    return answered
end

function Watch.reset()
    Watch.hands, Watch.reacted, Watch.held, Watch.aimSince, Watch.aimSeen = {}, {}, {}, {}, {}
    Watch.lastTickAtMs, Watch.nextPruneAtMs, Watch.fightLineCount = 0, 0, 0
    Watch.metrics = { aimed = 0, drew = 0, turned = 0, warned = 0, scans = 0, fightIgnored = 0, fightLines = 0,
        lowered = 0, keptHostile = 0, keptAggressor = 0, keptCareful = 0, carefulExpired = 0 }
end

return Watch
