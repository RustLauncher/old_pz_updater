ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"

local Registry = ProjectALife.ModuleRegistry

local Radioman = {
    settings = {
        arriveRadius = 1.5,     
        retryMs = 30000,        
        staticMs = 1200,        
        talkMs = 4000,          
        repeatMs = 60000,       
        legMs = 6000,           

        walkTilesPerSecond = 1.1,
        runTilesPerSecond = 2.4,
        detour = 1.4,
        giveUpGraceMs = 8000,
        giveUpMinMs = 12000,
        giveUpMaxMs = 75000,

        bareReach = 2,

        talkStaleMs = 6000,

        talkRange = 100,
    },
    metrics = { breaks = 0, aborts = 0, calls = 0, refused = 0, hangups = 0, talkSent = 0 },

    adapters = {},

    talking = {},
    talkingCount = 0,
}
ProjectALife.ModuleRadioman = Radioman

local function distance(ax, ay, bx, by)
    local dx, dy = (tonumber(ax) or 0) - (tonumber(bx) or 0), (tonumber(ay) or 0) - (tonumber(by) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function threatIsPerson(threatKind)
    return threatKind == "player" or threatKind == "actor"
end

function Radioman.anchorFor(memory, site)
    if type(memory) ~= "table" then return nil end
    local leash = memory.leash
    if type(leash) == "table" and tonumber(leash.x) ~= nil then
        return { x = tonumber(leash.x), y = tonumber(leash.y), z = tonumber(leash.z) or 0 }
    end
    if type(site) == "table" and type(site.radio) == "table" and tonumber(site.radio.x) ~= nil then
        return { x = tonumber(site.radio.x), y = tonumber(site.radio.y), z = tonumber(site.radio.z) or 0 }
    end
    local home = memory.home or memory.spawnOrigin
    if type(home) == "table" and tonumber(home.x) ~= nil then
        return { x = tonumber(home.x), y = tonumber(home.y), z = tonumber(home.z) or 0 }
    end
    return nil
end

function Radioman.paceRule(exposed, canSprint, remaining)
    local near = (tonumber(remaining) or 0) <= Radioman.settings.arriveRadius * 2
    if exposed == true and canSprint ~= false and not near then return "run" end
    return "walk"
end

function Radioman.giveUpMs(tiles, pace)
    local s = Radioman.settings
    local speed = pace == "run" and s.runTilesPerSecond or s.walkTilesPerSecond
    local travel = math.max(0, tonumber(tiles) or 0) * s.detour / math.max(0.1, speed) * 1000
    return math.floor(math.max(s.giveUpMinMs, math.min(s.giveUpMaxMs, travel + s.giveUpGraceMs)))
end

function Radioman.mayBegin(call, now)
    if call == nil then return true end
    if call.state == "walking" or call.state == "talking" then return false end
    return (tonumber(now) or 0) >= (tonumber(call.nextAtMs) or 0)
end

function Radioman.exposed(actor, shell, threat)
    if type(Radioman.adapters.exposed) == "function" then
        return Radioman.adapters.exposed(actor, shell, threat) == true
    end
    if threat == nil then return false end
    local reach, gap = Radioman.settings.bareReach, nil
    pcall(function() gap = distance(shell:getX(), shell:getY(), threat:getX(), threat:getY()) end)
    pcall(function()
        local weapon = threat.getPrimaryHandItem ~= nil and threat:getPrimaryHandItem() or nil
        if weapon ~= nil and weapon.getMaxRange ~= nil then
            reach = math.max(reach, tonumber(weapon:getMaxRange()) or reach)
        end
    end)
    if gap ~= nil and gap <= reach then return true end
    local seen = false
    pcall(function()
        local careful = ProjectALife.ModuleCareful
        if careful ~= nil and type(careful.lineOfSight) == "function" then
            seen = careful.lineOfSight(threat, shell) == true
        end
    end)
    return seen
end

local function canSprint(actor, shell, now)
    if type(Radioman.adapters.canSprint) == "function" then
        return Radioman.adapters.canSprint(actor, shell, now) ~= false
    end
    local endurance = ProjectALife.Endurance
    if endurance == nil or type(endurance.canSprint) ~= "function" then return true end
    local ok, allowed = pcall(endurance.canSprint, actor, shell, now)
    return not ok or allowed ~= false
end

function Radioman.paceFor(actor, shell, threat, remaining, now)
    return Radioman.paceRule(Radioman.exposed(actor, shell, threat), canSprint(actor, shell, now), remaining)
end

local function siteFor(memory)
    local site
    pcall(function()
        local registry = ProjectALife.OutpostRegistry
        if registry ~= nil and memory.outpostId ~= nil then site = registry.read(tostring(memory.outpostId)) end
    end)
    return site
end

local function say(shell, name)

    if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
        pcall(sendPlaySound, name, false, shell)
        return
    end
    pcall(function() shell:playSound(name) end)
end

local function stop(shell, name)
    pcall(function()
        local emitter = shell:getEmitter()
        if emitter ~= nil and emitter:isPlaying(name) then
            emitter:stopSoundByName(name)
        end
    end)
end

function Radioman.wallNow(fallback)
    if type(Radioman.adapters.wallNow) == "function" then return Radioman.adapters.wallNow() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return tonumber(fallback) or 0
end

function Radioman.positionOf(object)
    if object == nil or type(object.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if not ok or tonumber(x) == nil or tonumber(y) == nil then return nil end
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

function Radioman.broadcast(payload, range)
    if type(Radioman.adapters.broadcast) == "function" then
        return Radioman.adapters.broadcast("radioTalk", payload, range)
    end
    if type(sendServerCommand) ~= "function" or type(getOnlinePlayers) ~= "function" then return 0 end
    local sent = 0
    pcall(function()
        local players = getOnlinePlayers()
        if players == nil then return end
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            local px, py = Radioman.positionOf(player)
            if player ~= nil and (range == nil
                    or (px ~= nil and distance(px, py, payload.x, payload.y) <= range)) then
                sendServerCommand(player, "ProjectALife", "radioTalk", payload)
                sent = sent + 1
            end
        end
    end)
    return sent
end

function Radioman.remember(shell, entry)
    if shell == nil then return end
    if Radioman.talking[shell] == nil then
        if Radioman.talkingCount >= 64 then Radioman.talking, Radioman.talkingCount = {}, 0 end
        Radioman.talkingCount = Radioman.talkingCount + 1
    end
    Radioman.talking[shell] = entry
end

function Radioman.talk(shell, call, now)
    now = tonumber(now) or 0
    local untilMs = math.max(0, (tonumber(call and call.talkUntilMs) or now) - now)
    if type(isServer) == "function" and isServer() then
        local x, y, z = Radioman.positionOf(shell)
        local canSend = type(Radioman.adapters.broadcast) == "function"
            or (type(sendServerCommand) == "function" and type(getOnlinePlayers) == "function")
        if x ~= nil and canSend then
            Radioman.broadcast({ x = x, y = y, z = z, untilMs = untilMs }, Radioman.settings.talkRange)
            Radioman.remember(shell, { x = x, y = y, z = z })
            Radioman.metrics.talkSent = Radioman.metrics.talkSent + 1
            return true
        end
        say(shell, "RadioTalk")
        return false
    end
    local handle = nil
    if shell ~= nil and type(shell.playSound) == "function" then
        local ok, value = pcall(shell.playSound, shell, "RadioTalk")
        if ok then handle = value end
    end
    local emitter = nil
    if shell ~= nil and type(shell.getEmitter) == "function" then
        local ok, value = pcall(shell.getEmitter, shell)
        if ok then emitter = value end
    end
    local policy = ProjectALife.AudioPolicy
    if emitter == nil or type(policy) ~= "table" or type(policy.watchLoop) ~= "function" then return false end
    local wall = Radioman.wallNow(now)
    policy.watchLoop(emitter, handle, "RadioTalk", wall + untilMs + 250, wall)
    Radioman.remember(shell, { emitter = emitter, handle = handle })
    return true
end

function Radioman.endTalk(shell)
    local entry = shell ~= nil and Radioman.talking[shell] or nil
    if entry == nil then return false end
    Radioman.talking[shell] = nil
    Radioman.talkingCount = math.max(0, Radioman.talkingCount - 1)
    if entry.x ~= nil then
        Radioman.broadcast({ x = entry.x, y = entry.y, z = entry.z, untilMs = 0 }, nil)
        return true
    end
    local policy = ProjectALife.AudioPolicy
    if type(policy) == "table" and type(policy.stopNamed) == "function" then
        policy.stopNamed(entry.emitter, entry.handle, "RadioTalk")
        policy.forgetLoop(entry.emitter, "RadioTalk")
    end
    return true
end

function Radioman.stopRadio(shell)
    Radioman.endTalk(shell)
    stop(shell, "PALRadioStatic")
    stop(shell, "RadioTalk")
end

function Radioman.hangUp(shell, call, now)
    Radioman.stopRadio(shell)
    if type(call) == "table" then
        call.state, call.nextAtMs = "aborted", (tonumber(now) or 0) + Radioman.settings.retryMs
    end
    Radioman.metrics.hangups = Radioman.metrics.hangups + 1
    return call
end

local function contactFor(threat, shell)
    if ProjectALife.Support and ProjectALife.Support.contactFromTarget then
        local contact = ProjectALife.Support.contactFromTarget(threat)
        if contact then return contact end
    end
    local contact = { x = 0, y = 0 }
    pcall(function() contact.x, contact.y = threat:getX(), threat:getY() end)

    if threat ~= nil and threat.getUsername ~= nil then
        pcall(function() contact.playerKey = threat:getUsername() end)
    end
    return contact
end

local function openCall(actor, shell, context, doctrine, memory, now)
    local anchor = doctrine.policy == "radio" and Radioman.anchorFor(memory, siteFor(memory)) or nil
    local call = { state = "walking", startedAtMs = now, anchor = anchor }
    if anchor ~= nil then
        local tiles = 0
        pcall(function() tiles = distance(shell:getX(), shell:getY(), anchor.x, anchor.y) end)
        local pace = Radioman.paceFor(actor, shell, context.threat, tiles, now)
        call.giveUpAtMs = now + Radioman.giveUpMs(tiles, pace)
    end
    context.persistMemory(actor, "radioCall", call)
    Radioman.metrics.breaks = Radioman.metrics.breaks + 1
    return call
end

Registry.register({
    id = "radioman",

    kind = "doctrine",
    dispatch = "response",

    priority = 35,
    label = "Radio call",
    summary = "An actor allowed to call backup goes to the group's radio on contact (running while the threat can see or reach him), works it for static and a short talk, then calls the faction's support. Kill him mid-call and none comes.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or not Registry.allows(actor, "radioman") then return nil end
        if not threatIsPerson(context.threatKind) then

            local open = type(actor.memory) == "table" and actor.memory.radioCall or nil
            if type(open) == "table" and open.state == "talking" then
                Radioman.hangUp(shell, open, tonumber(context.now) or 0)
                if type(context.persistMemory) == "function" then
                    context.persistMemory(actor, "radioCall", open)
                end
            end
            return nil
        end
        local support = ProjectALife.Support
        if support == nil or type(support.request) ~= "function" then return nil end
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local faction
        pcall(function() faction = ProjectALife.Catalog and ProjectALife.Catalog.faction(actor.factionId) or nil end)
        local catalog = ProjectALife.Catalog
        local profile = catalog and catalog.npc and catalog.npc(actor.profileId) or nil
        local doctrine = support.doctrineFor(memory, faction, profile)
        if doctrine.policy == "disabled" then return nil end

        if not support.mayCallRadio(actor) then return nil end
        local group = memory.groupId or ("solo:" .. tostring(actor.uid))

        if not support.mayBegin(group, doctrine, context.now,
                doctrine.policy == "radio" and true or nil) then return nil end
        local now = tonumber(context.now) or 0
        local call = memory.radioCall
        if type(call) ~= "table" or Radioman.mayBegin(call, now) then
            if type(call) == "table" and (call.state == "walking" or call.state == "talking") then return nil end
            call = openCall(actor, shell, context, doctrine, memory, now)
        end
        local sx, sy, sz = 0, 0, 0
        pcall(function() sx, sy, sz = shell:getX(), shell:getY(), shell:getZ() end)
        if call.state == "walking" then
            local anchor = call.anchor
            local remaining = anchor ~= nil and distance(sx, sy, anchor.x, anchor.y) or 0
            local sameFloor = anchor == nil or math.floor(tonumber(anchor.z) or 0) == math.floor(tonumber(sz) or 0)
            if anchor ~= nil and (remaining > Radioman.settings.arriveRadius or not sameFloor) then
                local giveUpAt = tonumber(call.giveUpAtMs)
                    or ((tonumber(call.startedAtMs) or now) + Radioman.settings.giveUpMaxMs)
                if now >= giveUpAt then
                    call.state, call.nextAtMs = "aborted", now + Radioman.settings.retryMs
                    context.persistMemory(actor, "radioCall", call)
                    Radioman.metrics.aborts = Radioman.metrics.aborts + 1
                    return nil
                end
                return context.startMovement(actor, shell, { x = anchor.x, y = anchor.y, z = anchor.z or sz },
                    "radio_call", { pace = Radioman.paceFor(actor, shell, context.threat, remaining, now),
                        timeoutMs = Radioman.settings.legMs })
            end

            call.state, call.talkUntilMs, call.talked = "talking", now + Radioman.settings.staticMs + Radioman.settings.talkMs, false
            context.persistMemory(actor, "radioCall", call)
            say(shell, "PALRadioOpen")
            pcall(function() shell:setMoving(false) end)
            context.setActivity(actor, "idle", "radio_call")
            return { kind = "idle", intent = "radio_call", cooldownUntilMs = now + Radioman.settings.staticMs }
        end
        if call.state == "talking" then
            if now > (tonumber(call.talkUntilMs) or 0) + Radioman.settings.talkStaleMs then
                Radioman.hangUp(shell, call, now)
                context.persistMemory(actor, "radioCall", call)
                return nil
            end
            if now < (tonumber(call.talkUntilMs) or 0) then
                if call.talked ~= true then
                    call.talked = true
                    context.persistMemory(actor, "radioCall", call)
                    say(shell, "PALRadioStatic")
                    local spoken = false
                    pcall(function()
                        local voice = ProjectALife.Voice
                        if voice ~= nil then spoken = voice.play(shell, "SUPPORT_CALL") == true end
                    end)
                    if not spoken then Radioman.talk(shell, call, now) end
                end
                context.setActivity(actor, "idle", "radio_call")
                return { kind = "idle", intent = "radio_call",
                    cooldownUntilMs = math.min(tonumber(call.talkUntilMs) or now, now + 1000) }
            end

            Radioman.stopRadio(shell)
            local ok, reason = support.request(actor, shell, contactFor(context.threat, shell), now)

            if ok then
                pcall(function()
                    local meta = ProjectALife.MetaEvents
                    local name = meta and meta.sounds and meta.sounds.radioBackup
                    if type(name) ~= "string" then return end
                    if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
                        sendPlaySound(name, false, shell)
                    else
                        shell:playSound(name)
                    end
                end)
            end
            say(shell, "PALRadioClose")
            call.state, call.result, call.nextAtMs = "done", tostring(reason), now + Radioman.settings.repeatMs
            context.persistMemory(actor, "radioCall", call)
            if ok then Radioman.metrics.calls = Radioman.metrics.calls + 1
            else Radioman.metrics.refused = Radioman.metrics.refused + 1 end
            return nil
        end
        return nil
    end,
})

if type(Events) == "table" and Events.OnZombieDead ~= nil then
    Events.OnZombieDead.Add(Radioman.stopRadio)
end

return Radioman
