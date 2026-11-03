require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Shells/ALifeGait"
require "ProjectALife/Shells/ALifeShellSimulation"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Catalog = ProjectALife.Catalog
local Sim = ProjectALife.ShellSimulation
local defaults = ProjectALife.BehaviorSettings.endurance
local Endurance = { adapters = {}, settings = {}, states = {} }
ProjectALife.Endurance = Endurance

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function nowMs()
    if type(Endurance.adapters.nowMs) == "function" then return Endurance.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function shellHealth(shell)
    if shell == nil or type(shell.getHealth) ~= "function" or type(Sim.trueHealth) ~= "function" then return nil end
    local ok, health = pcall(Sim.trueHealth, shell)
    if ok then return tonumber(health) end
    return nil
end

local function profileFitness(actor)
    local profile = actor and Catalog.npc(actor.profileId) or nil
    local score = profile and profile.general and tonumber(profile.general.endurance) or 5
    return clamp(score / 10, 0.35, 1.25)
end

local function stateFor(actor, shell, now)
    if actor == nil or type(actor.uid) ~= "string" then return nil end
    local existing = Endurance.states[actor.uid]
    if existing ~= nil and existing.generation == actor.generation then return existing end

    local memory = type(actor.memory) == "table" and actor.memory or {}
    local stored = type(memory.enduranceState) == "table" and memory.enduranceState or {}

    local maximum = math.max(1, tonumber(Endurance.settings.maximum) or 100)

    local value = tonumber(stored.value) or tonumber(memory.endurance)
        or math.min(maximum, tonumber(Endurance.settings.initial) or maximum)
    local state = {
        uid = actor.uid,
        generation = actor.generation,
        value = clamp(value, 0, maximum),
        maximum = maximum,
        fitness = profileFitness(actor),

        drainScale = ProjectALife.Gait ~= nil and ProjectALife.Gait.drainScale(actor.uid) or 1,
        recoveryScale = ProjectALife.Gait ~= nil and ProjectALife.Gait.recoveryScale(actor.uid) or 1,
        lastAtMs = now,
        lastPersistAtMs = now,
        lastPersistedValue = value,
        lastHealth = shellHealth(shell),
        lastDamageAtMs = tonumber(stored.lastDamageAtMs) or -math.huge,
        damagedUntilMs = tonumber(stored.damagedUntilMs) or 0,
        retreatUntilMs = tonumber(stored.retreatUntilMs) or 0,
        dirty = false,
        mode = "idle",
    }
    Endurance.states[actor.uid] = state
    return state
end

local function stampShell(shell, state)
    if shell == nil or state == nil or shell.getModData == nil then return end
    local data = shell:getModData()
    if type(data) ~= "table" then return end
    data.ProjectALifeEndurance = state.value
    data.ProjectALifeEnduranceMaximum = state.maximum
    data.ProjectALifeEnduranceMode = state.mode
end

local function persist(actor, state, now, force)
    if actor == nil or state == nil or not state.dirty then return true end
    if not force and now - state.lastPersistAtMs < Endurance.settings.persistenceIntervalMs
            and math.abs(state.value - (state.lastPersistedValue or state.value)) < 1 then
        return true
    end

    local current = Registry.peek(actor.uid)
    if current == nil or current.generation ~= state.generation then return false end
    local updated = Registry.updateTransient(current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        record.memory.endurance = state.value
        record.memory.enduranceState = {
            value = state.value,
            maximum = state.maximum,
            lastDamageAtMs = state.lastDamageAtMs,
            damagedUntilMs = state.damagedUntilMs,
            retreatUntilMs = state.retreatUntilMs,
            updatedAtMs = now,
        }
    end, true)
    if updated == nil then return false end
    state.lastPersistAtMs = now
    state.lastPersistedValue = state.value
    state.dirty = false
    return true
end

local function rateFor(mode, state, sprinting)
    local settings = Endurance.settings
    local drain = state.drainScale or 1
    local recover = state.recoveryScale or 1
    if ProjectALife.Cold ~= nil then
        drain = drain * ProjectALife.Cold.drainScale(state.uid)
        recover = recover * ProjectALife.Cold.recoveryScale(state.uid)
    end

    if mode == "running" or mode == "pursuit_run" or mode == "flank_run" or mode == "panic_run" then
        local base = sprinting and tonumber(settings.sprintDrainPerSecond)
            or settings.runDrainPerSecond
        if mode == "panic_run" then base = base * (tonumber(settings.fearDrainScale) or 1.8) end
        return -base * drain / state.fitness
    end
    if mode == "retreat" then return -settings.retreatDrainPerSecond * drain / state.fitness end

    if mode == "pursuit" then
        return -settings.walkDrainPerSecond * drain / state.fitness
    end
    if mode == "combat" then
        return -settings.combatDrainPerSecond / state.fitness
    end
    if mode == "moving" or mode == "patrol" or mode == "scavenging" then
        return -settings.walkDrainPerSecond / state.fitness
    end
    if mode == "warning" then return settings.cautiousRecoveryPerSecond * recover * state.fitness end
    return settings.idleRecoveryPerSecond * recover * state.fitness
end

function Endurance.activityMode(state, shell, pressured)
    state = type(state) == "table" and state or {}
    local data = shell ~= nil and type(shell.getModData) == "function" and shell:getModData() or nil
    local pace = type(data) == "table" and data.ProjectALifePace or nil
    if state.kind == "retreat" then
        if state.intent ~= "fear_flee" and state.intent ~= "gun_flee" then return "retreat" end
        return (pace == "run" or pace == "sprint") and "panic_run" or "moving"
    end
    if state.kind == "combat" then
        if pace == "run" or pace == "sprint" then
            local tactic = state.action and state.action.tactic or "direct"
            return tactic ~= "direct" and "flank_run" or "pursuit_run"
        end
        local phase = type(data) == "table" and data.ProjectALifeCombatPhase or nil
        if phase == "windup" or phase == "recovery" then return "combat" end
        return "pursuit"
    end
    if state.kind == "scavenging" then return "scavenging" end
    if state.kind == "movement" then
        if pace == "run" or pace == "sprint" then return "running" end
        return state.intent == "patrol" and "patrol" or "moving"
    end
    if pressured == true or state.intent == "hold_pressure" then return "combat" end
    return "idle"
end

function Endurance.configure(adapters)
    Endurance.adapters = adapters or {}
    Endurance.settings = {}
    for name, value in pairs(defaults) do
        Endurance.settings[name] = tonumber(Endurance.adapters[name]) or value
    end
end

function Endurance.reset()
    Endurance.states = {}
end

function Endurance.damageCost(shell, loss)
    local pool = nil
    if shell ~= nil and type(Sim.maximumFor) == "function" then
        local ok, value = pcall(Sim.maximumFor, shell)
        if ok then pool = tonumber(value) end
    end
    if pool == nil or pool <= 0 then pool = 50 end
    local share = clamp((tonumber(loss) or 0) / pool, 0, 1)
    local cost = tonumber(Endurance.settings.damageCost) or 10
    return cost + share * cost * (tonumber(Endurance.settings.damageShareScale) or 10)
end

function Endurance.tick(actor, shell, mode, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return nil end
    local elapsed = clamp((now - state.lastAtMs) / 1000, 0, 2)
    state.lastAtMs = now
    state.mode = mode or "idle"

    local boosted = state.boostUntilMs ~= nil and now < state.boostUntilMs
    if state.boostUntilMs ~= nil and not boosted then state.boostUntilMs, state.boostFloor = nil, nil end

    if elapsed > 0 then
        local previous = state.value
        local data = shell ~= nil and shell.getModData ~= nil and shell:getModData() or nil
        local sprinting = type(data) == "table" and data.ProjectALifePace == "sprint"
        local rate = rateFor(state.mode, state, sprinting)
        if boosted and rate < 0 then rate = 0 end
        state.value = clamp(state.value + rate * elapsed, 0, state.maximum)
        if math.abs(previous - state.value) > 0.001 then state.dirty = true end
    end

    local health = shellHealth(shell)
    if health ~= nil and state.lastHealth ~= nil and health < state.lastHealth - 0.001 then
        state.value = clamp(state.value - Endurance.damageCost(shell, state.lastHealth - health), 0, state.maximum)
        state.lastDamageAtMs = now
        state.damagedUntilMs = now + Endurance.settings.damageRetreatMs
        state.retreatUntilMs = math.max(state.retreatUntilMs,
            now + Endurance.settings.minimumRetreatMs)
        state.dirty = true
    end
    if health ~= nil then state.lastHealth = health end
    if boosted and state.value < (state.boostFloor or 0) then
        state.value = state.boostFloor
        state.dirty = true
    end

    stampShell(shell, state)
    persist(actor, state, now, false)
    return state
end

function Endurance.consume(actor, shell, amount, reason, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return false end
    state.value = clamp(state.value - math.max(0, tonumber(amount) or 0), 0, state.maximum)
    state.dirty = true
    state.lastReason = reason
    stampShell(shell, state)
    return true, state.value
end

function Endurance.consumeAttack(actor, shell, suppliedNow)
    return Endurance.consume(actor, shell, Endurance.settings.attackCost, "attack", suppliedNow)
end

Endurance.boostFraction = 0.8
Endurance.boostMs = 10000

function Endurance.boost(actor, shell, durationMs, fraction, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return false end
    local floor = state.maximum * clamp(fraction or Endurance.boostFraction, 0, 1)
    state.boostFloor = math.max(floor, state.boostFloor or 0)
    state.boostUntilMs = math.max(now + (tonumber(durationMs) or Endurance.boostMs), state.boostUntilMs or 0)
    if state.value < state.boostFloor then
        state.value = state.boostFloor
        state.dirty = true
    end
    state.winded = false
    stampShell(shell, state)
    return true, state.value
end

function Endurance.release(actor)
    local state = type(actor) == "table" and Endurance.states[actor.uid] or nil
    if state == nil or state.boostUntilMs == nil then return false end
    state.boostUntilMs, state.boostFloor = nil, nil
    return true
end

function Endurance.boosted(actor, suppliedNow)
    local state = type(actor) == "table" and Endurance.states[actor.uid] or nil
    return state ~= nil and state.boostUntilMs ~= nil and (tonumber(suppliedNow) or nowMs()) < state.boostUntilMs
end

function Endurance.value(actor, shell, suppliedNow)
    local state = stateFor(actor, shell, tonumber(suppliedNow) or nowMs())
    return state and state.value or Endurance.settings.maximum
end

function Endurance.canSprint(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return true end
    if state.boostUntilMs ~= nil and now < state.boostUntilMs then return true end
    local settings = Endurance.settings
    local resume = tonumber(settings.sprintResume) or settings.sprintMinimum
    if state.value < settings.sprintMinimum then
        state.winded = true
    elseif state.value >= resume then
        state.winded = false
    end
    return state.value >= (state.winded and resume or settings.sprintMinimum)
end

function Endurance.tempoScale(shell)
    local settings = Endurance.settings
    local top = clamp(settings.tiredTempoMax, 1, 2)
    if top <= 1 or shell == nil or shell.getModData == nil then return 1 end
    local data = shell:getModData()
    if type(data) ~= "table" then return 1 end
    local value = tonumber(data.ProjectALifeEndurance)
    if value == nil then return 1 end
    local maximum = math.max(1, tonumber(data.ProjectALifeEnduranceMaximum) or tonumber(settings.maximum) or 100)
    local below = clamp(settings.tiredTempoBelow, 0.05, 1)
    local fraction = clamp(value / maximum, 0, 1)
    if fraction >= below then return 1 end
    return 1 + (top - 1) * (1 - fraction / below)
end

function Endurance.shouldRetreat(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return false end
    return state.value <= Endurance.settings.retreatThreshold or now < state.damagedUntilMs
end

function Endurance.beginRetreat(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    if state == nil then return 0 end
    state.retreatUntilMs = math.max(state.retreatUntilMs,
        now + Endurance.settings.minimumRetreatMs)
    state.dirty = true
    return state.retreatUntilMs
end

function Endurance.canReengage(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local state = stateFor(actor, shell, now)
    return state ~= nil and now >= state.retreatUntilMs
        and state.value >= Endurance.settings.reengageThreshold
end

function Endurance.forget(uid, generation)
    local state = Endurance.states[uid]
    if state == nil or generation ~= nil and state.generation ~= generation then return false end
    local actor = Registry.read(uid)
    if actor ~= nil then persist(actor, state, nowMs(), true) end
    Endurance.states[uid] = nil
    if ProjectALife.Cold ~= nil then ProjectALife.Cold.forget(uid) end
    return true
end

function Endurance.snapshot(uid)
    local state = Endurance.states[uid]
    if state == nil then return nil end
    return {
        value = state.value,
        maximum = state.maximum,
        mode = state.mode,
        damagedUntilMs = state.damagedUntilMs,
        retreatUntilMs = state.retreatUntilMs,
    }
end

Endurance.configure()

return Endurance
