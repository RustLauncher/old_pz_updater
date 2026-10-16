require "ProjectALife/Records/ALifeFunnel"

ProjectALife = ProjectALife or {}

local PartyPolicy = {}
ProjectALife.PartyPolicy = PartyPolicy

PartyPolicy.bounds = {

    loneCeiling = 3,

    groupSpread = 2,

    largestGroup = 24,

    newFactionWeight = 0.5,
    weightCeiling = 10,

    splitWeightCeiling = 20,
    sandboxLoneWeight = 3,
    sandboxGroupWeight = 1,
}

local function bounded(value, fallback, low, high)
    value = tonumber(value)
    if value == nil or value ~= value then value = fallback end
    return math.max(low, math.min(high, value))
end

function PartyPolicy.groupFloor()
    return PartyPolicy.bounds.loneCeiling + 1
end

function PartyPolicy.groupCeiling()
    local top = PartyPolicy.bounds.largestGroup
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    local budget = type(current) == "table" and tonumber(current.maximumHostileActors) or nil
    if budget ~= nil and budget >= PartyPolicy.groupFloor() then
        top = math.min(top, math.floor(budget))
    end
    return top
end

function PartyPolicy.weight(value)
    local bounds = PartyPolicy.bounds
    return bounded(value, bounds.newFactionWeight, 0, bounds.weightCeiling)
end

function PartyPolicy.config(faction)
    local spawn = type(faction) == "table" and faction.spawn or nil
    spawn = type(spawn) == "table" and spawn or {}
    local settings = ProjectALife.Settings and ProjectALife.Settings.current or {}
    local bounds = PartyPolicy.bounds
    local loneTop = bounds.loneCeiling
    local groupLow, groupTop = PartyPolicy.groupFloor(), PartyPolicy.groupCeiling()
    local mode = spawn.partyMode
    if mode ~= "lone" and mode ~= "group" then mode = "both" end

    local authoredMax = tonumber(spawn.most)
    local authoredLone = spawn.partyMode == nil and authoredMax ~= nil and authoredMax <= loneTop
    if authoredLone then mode = "lone" end
    local loneMin = math.floor(bounded(spawn.loneMin,
        authoredLone and (tonumber(spawn.fewest) or 1) or 1, 1, loneTop))
    local groupMin = math.floor(bounded(spawn.partyGroupMin, groupLow, groupLow, groupTop))
    local splitTop = bounds.splitWeightCeiling
    return {
        mode = mode,
        loneMin = loneMin,
        loneMax = math.floor(bounded(spawn.loneMax,
            authoredLone and authoredMax or loneTop, loneMin, loneTop)),
        groupMin = groupMin,
        groupMax = math.floor(bounded(spawn.partyGroupMax,
            groupLow + bounds.groupSpread, groupMin, groupTop)),
        loneWeight = bounded(spawn.loneWeight,
            bounded(settings.partyLoneWeight, bounds.sandboxLoneWeight, 0, splitTop), 0, splitTop),
        groupWeight = bounded(spawn.groupWeight,
            bounded(settings.partyGroupWeight, bounds.sandboxGroupWeight, 0, splitTop), 0, splitTop),
    }
end

function PartyPolicy.funnelSplit(faction)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.loneScale) ~= "function" then return 1 end
    return tonumber(funnel.loneScale(faction)) or 1
end

function PartyPolicy.funnelClamp(faction, size)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.clampSize) ~= "function" then return size end
    return funnel.clampSize(faction, size)
end

function PartyPolicy.choose(faction, roll, multiplier, available)
    local config = PartyPolicy.config(faction)

    available = math.floor(bounded(available, PartyPolicy.groupCeiling(), 0, 400))
    multiplier = bounded(multiplier, 1, 0.25, 8)
    config.loneWeight = config.loneWeight * PartyPolicy.funnelSplit(faction)
    local loneWeight = config.mode ~= "group" and available >= config.loneMin
        and config.loneWeight or 0
    local groupWeight = config.mode ~= "lone" and available >= config.groupMin
        and config.groupWeight or 0
    local total = loneWeight + groupWeight
    if total <= 0 then return 0, "none" end
    local unit = bounded(type(roll) == "function" and roll() or roll, 0.5, 0, 0.999999999)
    local needle = unit * total
    local kind, minimum, maximum, within
    if needle < loneWeight then
        kind, minimum, maximum = "lone", config.loneMin, config.loneMax
        within = needle / loneWeight
    else
        kind, minimum, maximum = "group", config.groupMin, config.groupMax
        within = (needle - loneWeight) / groupWeight
    end
    local size = minimum + math.floor(within * (maximum - minimum + 1))
    local ceiling = kind == "lone" and PartyPolicy.bounds.loneCeiling or PartyPolicy.groupCeiling()
    size = math.max(minimum, math.min(ceiling, math.floor(size * multiplier + 0.5)))
    size = PartyPolicy.funnelClamp(faction, size)
    return math.min(size, available), kind
end

return PartyPolicy
