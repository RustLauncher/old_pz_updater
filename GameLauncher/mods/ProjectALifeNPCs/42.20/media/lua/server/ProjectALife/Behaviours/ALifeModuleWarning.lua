require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Gate = ProjectALife.FeatureGate

local Warning = {
    id = "warning",
    options = {
        enabled = "Warning_Enabled",
        chance = "Warning_ChancePercent",
        raidChance = "Warning_RaidChancePercent",
        holdSeconds = "Warning_HoldSeconds",
    },
    defaults = { chance = 15, raidChance = 10, holdSeconds = 8 },
    kosEncounters = { raid = true, fullscale_raid = true, assassination = true, highway_ambush = true },
    kosModes = { hunt = true, manhunt = true, assault = true, full_raid = true },
    ceilingScale = 4,
    idleMs = 15000,
    limit = 512,
    seen = {},
    seenSize = 0,
    clocks = {},
    clockSize = 0,
    metrics = {
        warningGiven = 0, warningSkippedKos = 0, warningForcedByChance = 0, raidKosEngaged = 0,
        holdTimeouts = 0, givenBy = {}, skippedBy = {}, timedOutBy = {},
    },
}
ProjectALife.ModuleWarning = Warning

function Warning.reset()
    Warning.seen, Warning.seenSize = {}, 0
    Warning.clocks, Warning.clockSize = {}, 0
    Warning.metrics = {
        warningGiven = 0, warningSkippedKos = 0, warningForcedByChance = 0, raidKosEngaged = 0,
        holdTimeouts = 0, givenBy = {}, skippedBy = {}, timedOutBy = {},
    }
end

function Warning.master()
    return Gate.flag(Warning.options.enabled, true)
end

function Warning.percent(name)
    return Gate.number(Warning.options[name], Warning.defaults[name], 0, 100)
end

function Warning.holdMs()
    return Gate.number(Warning.options.holdSeconds, Warning.defaults.holdSeconds, 2, 60) * 1000
end

function Warning.groupKey(actor)
    local memory = type(actor.memory) == "table" and actor.memory or nil
    local key = memory ~= nil and (memory.groupId or memory.outpostId) or nil
    return tostring(key or actor.uid)
end

function Warning.playerKey(player)
    if type(player) == "string" then return player end
    if player == nil then return nil end
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.keyOf) == "function" then return fair.keyOf(player) end
    return nil
end

function Warning.roll(actor, salt)
    return Gate.hash01(Warning.groupKey(actor) .. "|" .. salt) * 100
end

function Warning.rolled(actor, salt, percent)
    if percent <= 0 then return false end
    if percent >= 100 then return true end
    return Warning.roll(actor, salt) < percent
end

function Warning.raid(actor)
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or memory.revengeKey ~= nil then return false end
    local kinds = Warning.kosEncounters
    if kinds[string.lower(tostring(memory.encounterKind or ""))] == true then return true end
    if kinds[string.lower(tostring(memory.encounter or ""))] == true then return true end
    return Warning.kosModes[string.lower(tostring(memory.adminMode or ""))] == true
end

function Warning.decide(actor)
    if type(actor) ~= "table" then return true, "unknown", false end
    local raid = Warning.raid(actor)
    if not Warning.master() then return false, "master_off", raid end
    if raid then
        if Warning.rolled(actor, "raid", Warning.percent("raidChance")) then return true, "raid_chance", true end
        return false, "raid", true
    end
    local forced = Registry.override(actor, Warning.id)
    if forced == "on" then return true, "forced_on", false end
    if forced ~= "off" and (Registry.get(Warning.id) == nil or Registry.allows(actor, Warning.id) == true) then
        return true, "module", false
    end
    if Warning.rolled(actor, "kos", Warning.percent("chance")) then return true, "chance", false end
    return false, "kos", false
end

function Warning.once(key)
    if Warning.seen[key] == true then return false end
    if Warning.seenSize >= Warning.limit then Warning.seen, Warning.seenSize = {}, 0 end
    Warning.seen[key] = true
    Warning.seenSize = Warning.seenSize + 1
    return true
end

function Warning.warns(actor, now)
    local warns, reason, raid = Warning.decide(actor)
    if (reason == "chance" or reason == "raid_chance") and Warning.once("chance|" .. Warning.groupKey(actor)) then
        Warning.metrics.warningForcedByChance = Warning.metrics.warningForcedByChance + 1
    end
    return warns, reason, raid
end

function Warning.skipped(actor, hook, player)
    local group, key = Warning.groupKey(actor), tostring(Warning.playerKey(player))
    local metrics = Warning.metrics
    if Warning.once("skip|" .. group .. "|" .. key) then metrics.warningSkippedKos = metrics.warningSkippedKos + 1 end
    if Warning.once("skip|" .. group .. "|" .. key .. "|" .. tostring(hook)) then
        metrics.skippedBy[hook] = (metrics.skippedBy[hook] or 0) + 1
    end
end

function Warning.kos(actor, hook, player, now)
    if type(actor) ~= "table" then return false end
    if Warning.warns(actor, now) ~= false then return false end
    Warning.skipped(actor, hook, player)
    return true
end

function Warning.given(kind)
    local metrics = Warning.metrics
    metrics.warningGiven = metrics.warningGiven + 1
    metrics.givenBy[kind] = (metrics.givenBy[kind] or 0) + 1
end

function Warning.timedOut(kind)
    local metrics = Warning.metrics
    metrics.holdTimeouts = metrics.holdTimeouts + 1
    metrics.timedOutBy[kind] = (metrics.timedOutBy[kind] or 0) + 1
end

function Warning.engaged(actor, player)
    if type(actor) ~= "table" then return false end
    local warns, _, raid = Warning.decide(actor)
    if warns ~= false or raid ~= true then return false end
    if not Warning.once("engaged|" .. tostring(actor.uid) .. "|" .. tostring(Warning.playerKey(player))) then
        return false
    end
    Warning.metrics.raidKosEngaged = Warning.metrics.raidKosEngaged + 1
    return true
end

function Warning.since(id, now)
    now = tonumber(now) or Gate.nowMs()
    local entry = Warning.clocks[id]
    if entry == nil or now < entry.lastMs or now - entry.lastMs > Warning.idleMs then
        if Warning.clockSize >= Warning.limit then Warning.clocks, Warning.clockSize = {}, 0 end
        entry = { sinceMs = now }
        Warning.clocks[id] = entry
        Warning.clockSize = Warning.clockSize + 1
    end
    entry.lastMs = now
    return entry.sinceMs
end

function Warning.expired(startedMs, progressMs, now)
    startedMs = tonumber(startedMs)
    if startedMs == nil then return false end
    now = tonumber(now) or Gate.nowMs()
    local limit = Warning.holdMs()
    if now - startedMs >= limit * Warning.ceilingScale then return true end
    return now - math.max(startedMs, tonumber(progressMs) or startedMs) >= limit
end

local function passive() return nil end

Registry.register({
    id = "warning",
    kind = "reaction",
    label = "Warn first",
    summary = "A hostile crew shouts a warning and holds fire for a moment before it strikes, and may open a short standoff with questions. Off means kill on sight. Raid crews, assassins and ambushers ship Off; a sandbox chance lets an Off crew warn anyway.",
    defaultEnabled = true,
    evaluate = passive,
})

return Warning
