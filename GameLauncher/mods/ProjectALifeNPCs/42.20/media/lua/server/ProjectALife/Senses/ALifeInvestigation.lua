require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Senses/ALifeSight"
require "ProjectALife/Core/ALifeActorRegistry"

ProjectALife = ProjectALife or {}

local Investigation = {
    marks = {},
    maximumMarks = 12,
    enabled = true,
    shoutEnabled = true,
    contactEnabled = true,

    metrics = { shoutAnswers = 0 },
}
ProjectALife.Investigation = Investigation

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Investigation.configure(options)
    options = options or {}
    if options.enabled ~= nil then Investigation.enabled = options.enabled ~= false end
    if options.shout ~= nil then Investigation.shoutEnabled = options.shout ~= false end
    if options.contact ~= nil then Investigation.contactEnabled = options.contact ~= false end
    return true
end

function Investigation.reset()
    Investigation.marks = {}
    Investigation.metrics = { shoutAnswers = 0 }
end

function Investigation.number(name, default, minimum, maximum)
    return ProjectALife.FeatureGate.number(name, default, minimum, maximum)
end

function Investigation.hearingOn()
    return Investigation.enabled and ProjectALife.FeatureGate.flag("Hearing_Enabled", true)
end

function Investigation.region(x, y)
    return tostring(math.floor((tonumber(x) or 0) / 100)) .. ":" .. tostring(math.floor((tonumber(y) or 0) / 100))
end

function Investigation.alert(actor, level, now)
    if not Investigation.hearingOn() or actor == nil then return end
    actor.memory = actor.memory or {}
    local old = actor.memory.hearingAlert
    if old ~= nil and old.untilMs > now and old.level == "red" then level = "red" end
    local value = { level = level, untilMs = now + Investigation.number("Hearing_AlertSeconds", 20, 1, 60) * 1000 }
    actor.memory.hearingAlert = value
    local registry = ProjectALife.ActorRegistry
    local current = registry ~= nil and type(registry.peek) == "function" and registry.peek(actor.uid) or nil
    if current ~= nil and current.generation == actor.generation and type(registry.updateTransient) == "function" then
        registry.updateTransient(current.uid, current.revision, function(record)
            record.memory = record.memory or {}
            record.memory.hearingAlert = value
        end, true)
    end
end

function Investigation.audible(shell, mark)
    local radius = math.sqrt(mark.radiusSquared or 0)
    if mark.kind == "contact" then return radius end
    local floors = 0
    if type(shell.getZ) == "function" then floors = math.abs(shell:getZ() - mark.z) end
    radius = radius * (Investigation.number("Hearing_FloorPercent", 50, 0, 100) / 100) ^ floors
    local sight = ProjectALife.Sight
    if sight ~= nil and type(sight.between) == "function" then
        local answer = sight.between(shell:getX(), shell:getY(), type(shell.getZ) == "function" and shell:getZ() or mark.z, mark.x, mark.y, mark.z)
        if sight.hides(answer) then
            radius = radius * Investigation.number("Hearing_WallPercent", 50, 0, 100) / 100
        end
    end
    return radius
end

function Investigation.onWorldSound(x, y, z, radius, volume, source)
    if tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil then return false end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    if not Investigation.hearingOn() or (tonumber(volume) or 0) <= 0 or (tonumber(radius) or 0) < 4 then return false end
    if type(source) == "userdata" and not (type(instanceof) == "function" and instanceof(source, "IsoGameCharacter")) then source = nil end
    if type(source) ~= "table" and type(source) ~= "userdata" then source = nil end
    local group
    if source ~= nil and type(source.isOutside) == "function" and source:isOutside() == false then radius = radius * 0.5 end
    if source ~= nil and type(source.getModData) == "function" then group = source:getModData().ProjectALifeGroupId end
    return Investigation.note(x, y, z, radius, 20000, group, "noise", nil, source)
end

function Investigation.peripheral(actor, shell, player, distance, now)
    if not Investigation.hearingOn() or shell == nil or player == nil then return false end
    if type(shell.getZ) == "function" and type(player.getZ) == "function" and math.abs(shell:getZ() - player:getZ()) > 0.5 then return false end
    local noisy = (type(player.isRunning) == "function" and player:isRunning())
        or (type(player.isSprinting) == "function" and player:isSprinting())
    local data = type(player.getModData) == "function" and player:getModData() or nil
    local shot = data and tonumber(data.ProjectALifeLastShotAtMs) or nil
    if shot ~= nil and now >= shot and now - shot <= 1500 then noisy = true end
    if not noisy then
        for index = #Investigation.marks, 1, -1 do
            local mark = Investigation.marks[index]
            if mark.source == player and now - mark.atMs <= 1500 and now < mark.untilMs and distance * distance <= mark.radiusSquared then noisy = true break end
        end
    end
    if not noisy then return false end
    return distance <= Investigation.number("Hearing_PeripheralTiles", 8, 0, 12)
end

Investigation.passiveIntents = { patrol = true, travel = true, roam = true }
function Investigation.canInterrupt(state)
    return Investigation.hearingOn() and state.kind == "movement" and Investigation.passiveIntents[tostring(state.intent)] == true
end

function Investigation.note(x, y, z, radius, holdMs, sourceGroup, kind, target, source)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.noteMark) == "function" then pcall(first.noteMark, x, y, z, radius, kind, source) end
    if not Investigation.enabled then return false end
    kind = kind or "noise"
    if kind ~= "contact" and not Investigation.hearingOn() then return false end
    if kind == "shout" and not Investigation.shoutEnabled then return false end
    if kind == "contact" and not Investigation.contactEnabled then return false end

    local marks = Investigation.marks
    local now, region = nowMs(), Investigation.region(x, y)
    local count = 0
    for index = #marks, 1, -1 do
        local old = marks[index]
        if now >= old.untilMs then table.remove(marks, index)
        elseif kind ~= "contact" and kind ~= "shout" and old.kind ~= "contact" and old.kind ~= "shout"
                and old.x == x and old.y == y and old.z == z and now - old.atMs < 500 then
            table.remove(marks, index)
        else
            if old.region == region then count = count + 1 end
        end
    end
    if count >= Investigation.maximumMarks then
        for index = 1, #marks do
            if marks[index].region == region then table.remove(marks, index) break end
        end
    end
    if #marks >= 768 then return false end
    marks[#marks + 1] = { region = region,
        kind = kind,
        atMs = nowMs(),
        x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0,
        radiusSquared = (math.max(0, tonumber(radius) or 12) * (kind == "contact" and 1 or Investigation.number("Hearing_RadiusPercent", 100, 25, 200) / 100)) ^ 2,
        untilMs = nowMs() + (tonumber(holdMs) or 20000),
        group = sourceGroup,

        consumed = {},

        target = kind == "contact" and target or nil,

        source = kind ~= "contact" and source or nil,
    }
    return true
end

function Investigation.reportContact(actor, target, x, y, z, radius)
    local group = actor and actor.memory and actor.memory.groupId or nil
    if type(group) ~= "string" then return false end

    return Investigation.note(x, y, z, radius or 20, 25000, group, "contact",
        target)
end

local function markTargetDead(mark)
    local target = mark.target
    local kind = type(target)
    return (kind == "table" or kind == "userdata") and target.isDead ~= nil
        and target:isDead() == true
end

local function addressedTo(mark, actor, ownGroup)
    if mark.consumed ~= nil and mark.consumed[actor.uid] then return false end
    if mark.kind == "shout" then return true end
    if mark.kind == "contact" then
        if ownGroup == nil or mark.group ~= ownGroup then return false end

        return mark.consumed[actor.uid] ~= true
    end

    return mark.group == nil or mark.group ~= ownGroup
end

function Investigation.destinationFor(actor, shell, now)
    if not Investigation.enabled then return nil end
    local marks = Investigation.marks
    if #marks == 0 then return nil end
    now = tonumber(now) or nowMs()
    if shell == nil or shell.getX == nil or shell.getY == nil then return nil end
    local x, y = shell:getX(), shell:getY()
    local ownGroup = actor and actor.memory and actor.memory.groupId or nil
    local presence = ProjectALife.ModuleTalkPresence
    local refuses = presence ~= nil and type(presence.refusesLead) == "function" and presence.refusesLead or nil
    local best, bestFlat
    local first = ProjectALife.FirstDays
    local frightened = first ~= nil and type(first.refusesLead) == "function" and first.refusesLead or nil
    for index = #marks, 1, -1 do
        local mark = marks[index]
        if now >= mark.untilMs then
            table.remove(marks, index)
        elseif mark.kind == "contact" and mark.target ~= nil
                and markTargetDead(mark) then

            table.remove(marks, index)
        elseif (mark.kind == "contact" or Investigation.hearingOn()) and addressedTo(mark, actor, ownGroup) then
            local dx, dy = mark.x - x, mark.y - y
            local flat = dx * dx + dy * dy

            if flat <= mark.radiusSquared and flat <= Investigation.audible(shell, mark) ^ 2 and flat >= 9
                    and (bestFlat == nil or flat < bestFlat)
                    and (refuses == nil or not refuses(actor, shell, mark, now)) then
                if frightened == nil or not frightened(actor, shell, mark, now) then
                    best, bestFlat = mark, flat
                end
            end
        end
    end
    if best == nil then return nil end
    local lead = { x = best.x, y = best.y, z = best.z, kind = best.kind, mark = best }
    local policy = ProjectALife.DoorPolicy
    if best.kind ~= "contact" and policy ~= nil and type(policy.clueLead) == "function" then
        local step = policy.clueLead(actor, shell, lead)
        if step == false then
            best.consumed[actor.uid] = true
            return nil
        elseif type(step) == "table" then
            lead.x, lead.y, lead.z = step.x, step.y, step.z
        end
    end
    Investigation.alert(actor, best.kind == "contact" and "red" or "yellow", now)
    return lead
end

function Investigation.facingFor(x, y, now)
    if not Investigation.enabled then return nil end
    local marks = Investigation.marks
    local best, bestAt
    for index = 1, #marks do
        local mark = marks[index]
        if now < mark.untilMs and (mark.kind == "contact" or Investigation.hearingOn()) then
            local dx, dy = mark.x - x, mark.y - y
            if dx * dx + dy * dy <= mark.radiusSquared
                    and (bestAt == nil or mark.untilMs > bestAt) then
                best, bestAt = mark, mark.untilMs
            end
        end
    end
    return best
end

function Investigation.consume(actor, destination)
    if type(destination) ~= "table" then return false end
    local mark = destination.mark
    if type(mark) ~= "table" or mark.consumed == nil then return false end
    mark.consumed[actor.uid] = true
    return true
end

local function onWeaponSwing(character, weapon)
    pcall(function()
        if not instanceof(character, "IsoPlayer") then return end
        local radius = 10
        pcall(function()
            if weapon ~= nil and weapon:isAimedFirearm() then
                radius = tonumber(weapon:getSoundRadius()) or 60
            end
        end)
        if not Investigation.hearingOn() then return end
        if type(character.getModData) == "function" and weapon ~= nil and type(weapon.isAimedFirearm) == "function" and weapon:isAimedFirearm() then
            character:getModData().ProjectALifeLastShotAtMs = nowMs()
        end
        Investigation.onWorldSound(character:getX(), character:getY(), character:getZ(), radius, 20, character)
    end)
end

if type(Events) == "table" and Events.OnWeaponSwing ~= nil
        and type(Events.OnWeaponSwing.Add) == "function" then
    Events.OnWeaponSwing.Add(onWeaponSwing)
end

Investigation.shoutReactRadius = 30

Investigation.shoutHeardCap = 1
function Investigation.shoutReactions(x, y, z, player)
    if type(isClient) == "function" and isClient() then return 0 end
    local Watchdog, Registry, Relations = ProjectALife.Watchdog, ProjectALife.ActorRegistry, ProjectALife.Relations
    if Watchdog == nil or Registry == nil or Relations == nil or player == nil then return 0 end

    local robbery = ProjectALife.ModuleRobbery
    if robbery ~= nil and type(robbery.onShout) == "function" then
        local ok, handled = pcall(robbery.onShout, player)
        if ok and handled == true then return 0 end
    end
    local radiusSquared = Investigation.shoutReactRadius ^ 2
    local spoken, count = {}, 0
    local heard = 0
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    for uid, binding in pairs(Watchdog.bindings) do
        local shell = binding and binding.shell or nil
        local record = shell ~= nil and Registry.read(uid) or nil
        if record ~= nil and record.lifecycle == "active" then
            local ok, d2 = pcall(function()
                local dx, dy = shell:getX() - x, shell:getY() - y
                return dx * dx + dy * dy
            end)
            if ok and d2 <= radiusSquared then
                local memory = type(record.memory) == "table" and record.memory or {}

                local group = memory.groupId
                    or (memory.outpostId ~= nil and ("outpost:" .. tostring(memory.outpostId)))
                    or ("solo:" .. uid)
                if not spoken[group] then
                    spoken[group] = true
                    local stance = type(Relations.playerStance) == "function"
                        and Relations.playerStance(record, player) or "neutral"
                    local handled = false
                    if stance == "careful" or stance == "neutral" then
                        local careful = ProjectALife.ModuleCareful
                        if careful ~= nil and type(careful.noteShout) == "function" then
                            local ok, result = pcall(careful.noteShout, record, shell, player)
                            handled = ok and result == true
                        end
                    end
                    local voice = ProjectALife.Voice
                    if not handled and voice ~= nil and type(voice.play) == "function" then
                        pcall(voice.play, shell, "SHOUT_" .. string.upper(tostring(stance)), { force = true })
                    end
                    count = count + 1
                    Investigation.metrics.shoutAnswers =
                        (tonumber(Investigation.metrics.shoutAnswers) or 0) + 1
                elseif talk ~= nil and speech ~= nil and heard < Investigation.shoutHeardCap
                        and not talk.inCombat(record) then
                    heard = heard + 1
                    local stance = type(Relations.playerStance) == "function"
                        and Relations.playerStance(record, player) or "neutral"
                    if stance == "allied" then stance = "friendly" end
                    pcall(talk.later, 200 + heard * 160 + (ZombRand and ZombRand(500) or 0), function()
                        local context = speech.contextFor(record, player)
                        context.stance = stance
                        talk.bark(record, shell, player, "SHOUT_HEARD_" .. string.upper(tostring(stance)), context)
                    end)
                end
                if speech ~= nil then pcall(speech.face, shell, { x = x, y = y }) end
            end
        end
    end
    return count
end

function Investigation.noteShout(x, y, z, player)
    if not Investigation.hearingOn() then return false end
    local noted = Investigation.note(x, y, z, 45, 25000, nil, "shout", nil, player)
    if player ~= nil then pcall(Investigation.shoutReactions, x, y, z, player) end
    return noted
end

Investigation.shoutIntervalMs = 1500
Investigation.lastShoutAtMs = {}

function Investigation.handleClientCommand(module, command, player)
    if module ~= "ProjectALife" or command ~= "shout" or player == nil then
        return false
    end
    local key = "0"
    pcall(function()
        key = tostring(player:getUsername() or player:getOnlineID() or "0")
    end)
    local now = nowMs()
    if now - (Investigation.lastShoutAtMs[key] or -math.huge)
            < Investigation.shoutIntervalMs then
        return false
    end
    Investigation.lastShoutAtMs[key] = now
    local handled = false
    pcall(function()
        handled = Investigation.noteShout(player:getX(), player:getY(), player:getZ(), player)
    end)
    return handled
end

if type(Events) == "table" and Events.OnClientCommand ~= nil
        and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Investigation.handleClientCommand)
end

if type(Events) == "table" and Events.OnWorldSound ~= nil and type(Events.OnWorldSound.Add) == "function" then
    Events.OnWorldSound.Add(Investigation.onWorldSound)
end

return Investigation
