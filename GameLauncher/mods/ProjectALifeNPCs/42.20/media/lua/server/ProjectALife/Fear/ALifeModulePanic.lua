ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Fear/ALifeModuleGunFear"

local Registry = ProjectALife.ModuleRegistry

local Panic = {
    settings = {
        panicMs = 1600,
        engagementMemoryMs = 45000,
        squadCooldownMs = 60000,
        pinnedMs = 1500,
        steadyDelayMs = 1500,
        coverHoldMs = 2500,
        freezeHoldMs = 1200,
        coverPercent = 45,
        freezePercent = 35,
        steadyRange = 20,

        fearMemoryMs = 45000,

        fearHoldsPost = true,
    },

    squads = {},
    metrics = { contacts = 0, panics = 0, refused = 0, covers = 0, freezes = 0, pins = 0, steadies = 0,
        fears = 0, fearsRefused = 0 },
}
ProjectALife.ModulePanic = Panic

Panic.lines = {
    PANIC = {
        trained = { "Someone there!", "Get down!", "Cover! Cover!", "Stay back!" },
        plain = { "Someone's out there!", "Hey! Hey, who is that?!", "Oh God, get down!", "Back up, back up!",
            "Stay behind me!", "Is that a person? Get inside!", "Don't let them see you!", "Jesus, they're right there!",
            "Down! Get down!", "Who's that? Who is that?!", "Everybody quiet, quiet!", "Keep your distance!" },
        rough = { "Eyes up, somebody's there!", "Hey! Who the hell is that?", "Heads up, we got company!",
            "Shit, spread out!", "Get your piece up, get it up!", "Who's that? Look!", "Down, get down, down!",
            "Don't just stand there, move!", "Somebody tell me that's one of ours", "Trouble, right there!",
            "Watch the stranger, watch the stranger!", "Back up, don't crowd me!" },
    },
    STEADY = {
        trained = { "Steady!", "Hold the line!", "Eyes up, on me!" },
        plain = { "Steady, steady!", "Easy now, easy", "Stay together, nobody run!", "Breathe, we're all right!",
            "Eyes up, stay with me!" },
        rough = { "Steady, damn it!", "Nobody runs!", "Eyes up, stay on me!", "Settle down, settle down!",
            "Stay together, stay together!" },
    },
}
Panic.defaultStyle = "plain"

function Panic.linesFor(event, record)
    local roles = ProjectALife.DialogueRoles
    local style = Panic.defaultStyle
    if roles ~= nil and type(roles.callStyle) == "function" then style = roles.callStyle(record, nil) end
    local set = Panic.lines[event]
    return set[style] or set.plain
end

function Panic.recordOfShell(shell)
    local uid
    pcall(function() uid = shell:getModData().ProjectALifeUID end)
    local registry = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or registry == nil or type(registry.peek) ~= "function" then return nil end
    local ok, record = pcall(registry.peek, uid)
    if ok then return record end
    return nil
end

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function stableHash(value)
    local text, hash = tostring(value or ""), 0
    for index = 1, #text do hash = (hash * 31 + string.byte(text, index)) % 2147483647 end
    return hash
end

function Panic.exempt(conduct)
    return conduct == "leader" or conduct == "sniper" or conduct == "ambusher"
end

function Panic.mayPanic(memory, targetKey, squad, now, conduct)
    if Panic.exempt(conduct) then return false, "calm_by_identity" end
    memory = type(memory) == "table" and memory or {}
    now = tonumber(now) or 0
    if memory.panicSpentFor ~= nil and memory.panicSpentFor == targetKey
            and now - (tonumber(memory.panicSpentAtMs) or -1e12) < Panic.settings.engagementMemoryMs then
        return false, "spent"
    end
    if type(squad) == "table" and now - (tonumber(squad.panicAtMs) or -1e12) < Panic.settings.squadCooldownMs then
        return false, "squad_cooldown"
    end
    return true
end

function Panic.scrambleFor(uid, coverPercent, freezePercent)
    local roll = stableHash(uid) % 100
    if roll < (tonumber(coverPercent) or Panic.settings.coverPercent) then return "cover" end
    if roll < (tonumber(coverPercent) or Panic.settings.coverPercent) + (tonumber(freezePercent) or Panic.settings.freezePercent) then return "freeze" end
    return "fire"
end

function Panic.windowLive(untilMs, now)
    local limit = tonumber(untilMs)
    return limit ~= nil and (tonumber(now) or 0) < limit
end

local function targetKeyOf(target, kind)
    if target == nil then return tostring(target) end
    local key
    if kind == "player" and type(target.getUsername) == "function" then
        local ok, name = pcall(target.getUsername, target)
        if ok then key = "player:" .. tostring(name) end
    end
    if key == nil and type(target.getModData) == "function" then
        local ok, data = pcall(target.getModData, target)
        if ok and type(data) == "table" and data.ProjectALifeUID ~= nil
                and tostring(data.ProjectALifeUID) ~= "" then
            key = "actor:" .. tostring(data.ProjectALifeUID)
        end
    end
    return key or tostring(target)
end

local function persist(actor, key, value)
    if type(actor) ~= "table" then return end
    if type(actor.memory) ~= "table" then actor.memory = {} end
    actor.memory[key] = value
    pcall(function()
        local registry = ProjectALife.ActorRegistry
        if registry == nil then return end
        local current = registry.read(actor.uid)
        if current == nil then return end
        registry.updateTransient(current.uid, current.revision, function(record)
            record.memory = record.memory or {}
            record.memory[key] = value
        end)
    end)
end

local function say(shell, event, lines, seed, psex)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.allows) == "function" and not speech.allows(shell, nil, event, nil, nil) then return end
    pcall(function()
        local voice = ProjectALife.Voice
        if voice ~= nil then voice.play(shell, event, { urgent = true, context = { psex = psex } }) end
    end)
    if speech ~= nil and type(speech.sayLine) == "function" then
        pcall(function() speech.sayLine(shell, lines[1 + stableHash(seed) % #lines], "directed") end)
        return
    end
    pcall(function() shell:Say(lines[1 + stableHash(seed) % #lines]) end)
end

function Panic.roll100()
    if type(ZombRand) == "function" then return ZombRand(100) end
    return 0
end

function Panic.fearRoll(memory, key, now, percent, roll)
    memory = type(memory) == "table" and memory or {}
    now = tonumber(now) or 0
    if memory.fearSpentFor ~= nil and memory.fearSpentFor == key
            and now - (tonumber(memory.fearSpentAtMs) or -1e12) < Panic.settings.fearMemoryMs then
        return false, "spent"
    end
    return (tonumber(roll) or 100) < (tonumber(percent) or 0), "rolled"
end

function Panic.holdingPost(actor)
    if Panic.settings.fearHoldsPost ~= true then return false end
    if type(actor) ~= "table" then return false end
    if Registry.override(actor, "withdraw") == "off" then return true end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local stance = memory.stance
    return type(stance) == "string" and stance ~= "" and stance ~= "route"
end

function Panic.fearsThis(shell, threat)
    if threat == nil then return false end
    local of
    pcall(function() of = shell:getModData().ProjectALifeFearOf end)
    if type(of) ~= "string" or of == "" then return false end
    local key = targetKeyOf(threat, "player") .. ":"
    return string.sub(of, 1, #key) == key
end

function Panic.fearLive(shell, now)
    local live = false
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        live = Panic.windowLive(data.ProjectALifeFearUntilMs, now)
    end)
    return live
end

function Panic.frighten(actor, shell, target, now, options)
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear == nil or type(gunFear.frighten) ~= "function" then return false, "no_module" end
    return gunFear.frighten(actor, shell, target, now, options)
end

function Panic.onAimedAt(record, shell, player, now)
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear == nil or type(gunFear.onAimedAt) ~= "function" then return false, "no_module" end
    return gunFear.onAimedAt(record, shell, player, now)
end

function Panic.onShot(record, shell, attacker, ranged, now)
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear == nil or type(gunFear.onShot) ~= "function" then return false, "no_module" end
    return gunFear.onShot(record, shell, attacker, ranged, now)
end

Panic.keyOf = targetKeyOf
Panic.remember = persist

function Panic.configure(options)
    options = type(options) == "table" and options or {}
    local settings = Panic.settings
    local gunFear = ProjectALife.ModuleGunFear
    if gunFear ~= nil and type(gunFear.configure) == "function" then
        gunFear.configure({ percent = options.gunFearPercent, shotPercent = options.shotFearPercent,
            fearHoldMs = options.fearHoldMs })
    end
    if options.fearHoldsPost ~= nil then settings.fearHoldsPost = options.fearHoldsPost == true end
    return settings
end

function Panic.onFirstContact(actor, shell, target, kind, now)
    if kind ~= "player" and kind ~= "actor" then return false, "not_a_person" end
    if type(actor) ~= "table" then return false, "no_actor" end
    if not Registry.allows(actor, "panic") then return false, "module_off" end
    now = tonumber(now) or nowMsFallback()
    Panic.metrics.contacts = Panic.metrics.contacts + 1
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local groupId = memory.groupId
    local squad = groupId ~= nil and Panic.squads[groupId] or nil
    local key = targetKeyOf(target, kind)
    local ok, reason = Panic.mayPanic(memory, key, squad, now, memory.conduct)
    if not ok then
        Panic.metrics.refused = Panic.metrics.refused + 1
        return false, reason
    end
    local data
    pcall(function() data = shell:getModData() end)
    if type(data) ~= "table" then return false, "no_shell" end
    data.ProjectALifePanicUntilMs = now + Panic.settings.panicMs
    data.ProjectALifePanicRoll = Panic.scrambleFor(actor.uid, Panic.settings.coverPercent, Panic.settings.freezePercent)
    data.ProjectALifePanicActedFor = nil
    persist(actor, "panicSpentFor", key)
    persist(actor, "panicSpentAtMs", now)
    if groupId ~= nil then Panic.squads[groupId] = { panicAtMs = now, steadiedAtMs = nil } end
    Panic.metrics.panics = Panic.metrics.panics + 1
    local speech = ProjectALife.Speech
    say(shell, "PANIC", Panic.linesFor("PANIC", actor), actor.uid .. tostring(now),
        speech ~= nil and type(speech.threatSex) == "function" and speech.threatSex(target, kind) or nil)
    return true, data.ProjectALifePanicRoll
end

function Panic.pin(shell, now)
    local stamped = false
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" or data.ProjectALifeOwned ~= true then return end
        data.ProjectALifePinnedUntilMs = (tonumber(now) or nowMsFallback()) + Panic.settings.pinnedMs
        stamped = true
    end)
    if stamped then Panic.metrics.pins = Panic.metrics.pins + 1 end
    return stamped
end

function Panic.steady(groupId, leaderShell, members, now)
    local squad = groupId ~= nil and Panic.squads[groupId] or nil
    if squad == nil or squad.steadiedAtMs ~= nil then return false end
    now = tonumber(now) or nowMsFallback()
    if now - (tonumber(squad.panicAtMs) or -1e12) < Panic.settings.steadyDelayMs then return false end
    squad.steadiedAtMs = now
    local cleared = 0
    for _, member in ipairs(type(members) == "table" and members or {}) do
        pcall(function()
            local data = member.shell:getModData()
            if data.ProjectALifePanicUntilMs ~= nil or data.ProjectALifePinnedUntilMs ~= nil then cleared = cleared + 1 end
            data.ProjectALifePanicUntilMs = nil
            data.ProjectALifePinnedUntilMs = nil
        end)
    end
    Panic.metrics.steadies = Panic.metrics.steadies + 1
    say(leaderShell, "STEADY", Panic.linesFor("STEADY", Panic.recordOfShell(leaderShell)), tostring(groupId) .. tostring(now))
    return true, cleared
end

function Panic.reset()
    Panic.squads = {}
    Panic.metrics = { contacts = 0, panics = 0, refused = 0, covers = 0, freezes = 0, pins = 0, steadies = 0,
        fears = 0, fearsRefused = 0 }
    return true
end

Registry.register({
    id = "panic",
    kind = "reaction",
    priority = 34,
    label = "Panic on contact",
    summary = "The first sight of a person is a beat of disorder: a shout, a dash for cover or a freeze, near rounds pin, the leader steadies the line. Once per engagement, once per squad per minute; never zombies.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or context.threat == nil then return nil end
        if context.threatKind ~= "player" and context.threatKind ~= "actor" then return nil end
        if not Registry.allows(actor, "panic") then return nil end
        local now = tonumber(context.now) or nowMsFallback()
        local data
        pcall(function() data = shell:getModData() end)
        if type(data) ~= "table" then return nil end
        local untilMs = tonumber(data.ProjectALifePanicUntilMs)
        if not Panic.windowLive(untilMs, now) then return nil end
        if data.ProjectALifePanicActedFor == untilMs then return nil end
        data.ProjectALifePanicActedFor = untilMs
        local roll = tostring(data.ProjectALifePanicRoll or "fire")
        pcall(function()
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = context.threat:getX(), context.threat:getY()
        end)
        if roll == "cover" then
            local point
            pcall(function()
                local cover = ProjectALife.ModuleCover
                if cover ~= nil and type(cover.find) == "function" then
                    point = cover.find(shell, context.threat, { away = true, range = 0 })
                end
            end)
            if point ~= nil and type(context.startMovement) == "function" then
                Panic.metrics.covers = Panic.metrics.covers + 1
                return context.startMovement(actor, shell, { x = point.x, y = point.y, z = point.z or 0 },
                    "panic_cover", { pace = "run", timeoutMs = Panic.settings.coverHoldMs })
            end
            roll = "freeze"
        end
        if roll == "freeze" then
            data.ProjectALifeHoldFireUntilMs = now + Panic.settings.freezeHoldMs
            Panic.metrics.freezes = Panic.metrics.freezes + 1
            if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "panic_freeze") end
            return { kind = "idle", intent = "panic_freeze", cooldownUntilMs = now + Panic.settings.freezeHoldMs }
        end
        return nil
    end,
})

return Panic
