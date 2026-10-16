ProjectALife = ProjectALife or {}

local Rules = {
    entries = {
        {
            id = "caution_needs_withdraw", kind = "requires", module = "meleeCaution", needs = "withdraw",
            note = "Needs Withdraw: it only lowers the crowd size at which Withdraw backs off.",
        },
        {
            id = "intimidate_needs_warning", kind = "requires", module = "meleeIntimidate", needs = "warning",
            note = "Needs Warn first: the shout from range is the warning itself.",
        },
        {
            id = "avoid_off_keeps_the_weapon", kind = "disabledBy", module = "weaponSwitchMelee", by = "zombieAvoid",
            state = "off",
            note = "Disabled by Avoid zombies = Off: that NPC fights on sight with the weapon it holds.",
        },
        {
            id = "one_conduct", kind = "exclusive", builtin = true,
            group = { "leader", "sniper", "medic", "ambusher", "stealth" },
            note = "One primary doctrine per NPC: the others stay off.",
        },
        {
            id = "flee_world_switch", kind = "disabledBy", builtin = true, module = "flee", by = "faction",
            note = "Faction members flee only when their record says On.",
        },
        {
            id = "march_needs_leader", kind = "context", module = "groupMarch",
            note = "Needs a group with a leader: a lone NPC or a pair without a leader never marches.",
        },
        {
            id = "regroup_needs_leader", kind = "context", module = "regroup",
            note = "Needs a group with a leader: members close up on the leader.",
        },
        {
            id = "doorstack_needs_leader", kind = "context", module = "doorstack",
            note = "Driven by the squad leader's beat: needs a group with a leader.",
        },
        {
            id = "flank_needs_group", kind = "context", module = "meleeFlank",
            note = "Needs a group: one member engages and the others circle round the target.",
        },
        {
            id = "spread_needs_group", kind = "context", module = "spread",
            note = "Needs a group; members on a stance post are left alone.",
        },
        {
            id = "plan_stops_the_group", kind = "context", module = "plan",
            note = "A free group stops to discuss and rest after each plan, and holds a shelter plan until dawn.",
        },
        {
            id = "stance_holds_the_post", kind = "context", module = "stance",
            note = "Holds the assigned post until the squad changes it; garrison and blockade posts never time out.",
        },
        {
            id = "idle_life_holds_the_squad", kind = "context", module = "idleLife",
            note = "Eat, drink, smoke and night shelter beats hold the NPC still; Off also stops warming at a fire.",
        },
    },
    byModule = {},
    metrics = { asked = 0, blocked = 0, by = {} },
    optInCache = nil,
}
ProjectALife.ModuleRules = Rules

function Rules.bind(registry)
    Rules.registry = registry
    Rules.optInCache = nil
end

function Rules.index()
    Rules.byModule = {}
    for _, entry in ipairs(Rules.entries) do
        if entry.builtin ~= true and entry.kind ~= "context" and entry.module ~= nil then
            local list = Rules.byModule[entry.module]
            if list == nil then
                list = {}
                Rules.byModule[entry.module] = list
            end
            list[#list + 1] = entry
        end
    end
end
Rules.index()

function Rules.reset()
    Rules.metrics = { asked = 0, blocked = 0, by = {} }
    Rules.optInCache = nil
end

function Rules.count(entry)
    local metrics = Rules.metrics
    metrics.blocked = metrics.blocked + 1
    local key = entry.module .. "<-" .. tostring(entry.needs or entry.by or "?")
    metrics.by[key] = (metrics.by[key] or 0) + 1
end

function Rules.violates(actor, entry)
    local registry = Rules.registry
    if registry == nil then return false end
    if entry.kind == "requires" then
        if registry.modules[entry.needs] == nil then return false end
        return registry.allowsBase(actor, entry.needs) ~= true
    end
    if entry.kind == "disabledBy" then
        if registry.modules[entry.by] == nil then return false end
        return registry.override(actor, entry.by) == entry.state
    end
    return false
end

function Rules.blockedBy(actor, id)
    local list = Rules.byModule[id]
    if list == nil then return nil end
    for _, entry in ipairs(list) do
        if Rules.violates(actor, entry) then return entry end
    end
    return nil
end

function Rules.permit(actor, id)
    local metrics = Rules.metrics
    metrics.asked = metrics.asked + 1
    local entry = Rules.blockedBy(actor, id)
    if entry == nil then return true end
    Rules.count(entry)
    return false
end

function Rules.suppressed(actor)
    local result = {}
    local registry = Rules.registry
    if registry == nil or type(actor) ~= "table" then return result end
    for id, list in pairs(Rules.byModule) do
        if registry.modules[id] ~= nil and registry.allowsBase(actor, id) == true then
            for _, entry in ipairs(list) do
                if Rules.violates(actor, entry) then
                    result[#result + 1] = id .. "<-" .. tostring(entry.needs or entry.by)
                    break
                end
            end
        end
    end
    table.sort(result)
    return result
end

function Rules.optIn(id)
    local cache = Rules.optInCache
    if cache == nil then
        cache = {}
        Rules.optInCache = cache
        local profiles = ProjectALife.BehaviorProfiles
        local registry = Rules.registry
        if profiles ~= nil and registry ~= nil then
            for moduleId, module in pairs(registry.modules) do
                if module.primary ~= true then
                    local anyone = false
                    for _, definition in ipairs(profiles.definitions) do
                        if definition.id ~= "test_all" and definition.overlays[moduleId] == true then anyone = true end
                    end
                    cache[moduleId] = not anyone
                end
            end
        end
    end
    return cache[id] == true
end

function Rules.notes(id)
    local notes = {}
    for _, entry in ipairs(Rules.entries) do
        if entry.module == id and entry.note ~= nil then
            notes[#notes + 1] = entry.note
        elseif entry.kind == "exclusive" then
            for _, member in ipairs(entry.group) do
                if member == id then notes[#notes + 1] = entry.note end
            end
        end
    end
    if Rules.optIn(id) then
        notes[#notes + 1] = "Opt-in: Inherit means Off. Choose On to use it."
    end
    return notes
end

function Rules.dependents(id)
    local result = {}
    for _, entry in ipairs(Rules.entries) do
        if entry.builtin ~= true and (entry.needs == id or entry.by == id) then
            result[#result + 1] = entry
        end
    end
    return result
end

function Rules.qaLine()
    local metrics = Rules.metrics
    local parts = {}
    for key, count in pairs(metrics.by) do parts[#parts + 1] = key .. ":" .. tostring(count) end
    table.sort(parts)
    return "ModuleRules: rules=" .. tostring(#Rules.entries) .. " asked=" .. tostring(metrics.asked)
        .. " blocked=" .. tostring(metrics.blocked) .. " by={" .. table.concat(parts, ";") .. "}"
end

return Rules
