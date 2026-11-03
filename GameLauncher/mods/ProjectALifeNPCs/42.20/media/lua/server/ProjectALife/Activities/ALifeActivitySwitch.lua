require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Activities/ALifeActivityPlanner"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.ActivityCatalog
local Planner = ProjectALife.ActivityPlanner

local Switch = {
    rules = {
        broken_car = { scene = "brokenCar", to = "scavenge" },
        car_crash = { scene = "carCrash", to = "scavenge" },
    },
    reach = 6,
    metrics = { due = 0, switched = 0, carsRemoved = 0 },
}
ProjectALife.ActivitySwitch = Switch

function Switch.hours()
    return tonumber(Catalog.setting("SwitchHours", 10)) or 10
end

function Switch.clearTiles()
    return tonumber(Catalog.setting("SwitchClearTiles", 60)) or 60
end

function Switch.playerNear(point, tiles)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.playerPositions) ~= "function" or type(point) ~= "table" then return true end
    for _, at in ipairs(kit.playerPositions()) do
        local dx, dy = at.x - (tonumber(point.x) or 0), at.y - (tonumber(point.y) or 0)
        if dx * dx + dy * dy <= tiles * tiles then return true end
    end
    return false
end

function Switch.ruleFor(members)
    local leader = members[1]
    local memory = leader ~= nil and leader.memory or nil
    return type(memory) == "table" and Switch.rules[memory.encounterKind] or nil, memory
end

function Switch.holdSince(members, hours)
    local record = members[1]
    local hold = record ~= nil and record.memory.activityHold or nil
    if type(hold) ~= "table" or tonumber(hold.since) == nil then return nil end
    return hours - hold.since
end

function Switch.due(id, members, hours)
    local rule = Switch.ruleFor(members)
    if rule == nil then return false end
    local held = Switch.holdSince(members, hours)
    if held == nil or held < Switch.hours() then return false end
    if Switch.playerNear(members[1].worldPosition, Switch.clearTiles()) then return false end
    local chance = tonumber(Catalog.setting("SwitchChance", 70)) or 70
    Switch.metrics.due = Switch.metrics.due + 1
    return Planner.stableRoll(tostring(id) .. ":abandon:" .. math.floor(hours)) * 100 < chance
end

function Switch.plan(members)
    local rule, memory = Switch.ruleFor(members)
    if rule == nil then return nil end
    local anchor = memory.stanceAnchor
    if type(anchor) ~= "table" then anchor = memory.spawnOrigin end
    if type(anchor) == "table" then anchor = { x = tonumber(anchor.x), y = tonumber(anchor.y) } end
    return { to = rule.to, after = function()
        local kit = ProjectALife.SceneKit
        if kit == nil or type(kit.sceneNear) ~= "function" or type(kit.remove) ~= "function" then return end
        if type(anchor) ~= "table" or anchor.x == nil or anchor.y == nil then return end
        local key = kit.sceneNear(rule.scene, anchor.x, anchor.y, Switch.reach)
        if key ~= nil and kit.remove(key) then Switch.metrics.carsRemoved = Switch.metrics.carsRemoved + 1 end
        Switch.metrics.switched = Switch.metrics.switched + 1
    end }
end

return Switch
