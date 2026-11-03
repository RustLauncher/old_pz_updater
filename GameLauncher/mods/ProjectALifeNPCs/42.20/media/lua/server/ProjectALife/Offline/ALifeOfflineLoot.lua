require "ProjectALife/Loot/ALifeStashRoom"
require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Records/ALifeLootRarity"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Loot = {
    id = "offline_loot",
    settings = { housePoints = 100, housesMinimum = 1, housesSpan = 3, jitter = 0.3, perMemberCap = 12, guard = 24 },
    table = {
        { type = "Base.Bandage", value = 6, weight = 10 },
        { type = "Base.Disinfectant", value = 8, weight = 5 },
        { type = "Base.Pills", value = 6, weight = 6 },
        { type = "Base.TinnedBeans", value = 4, weight = 14 },
        { type = "Base.CannedCorn", value = 4, weight = 12 },
        { type = "Base.CannedChili", value = 5, weight = 8 },
        { type = "Base.Crisps", value = 2, weight = 12 },
        { type = "Base.Cereal", value = 3, weight = 8 },
        { type = "Base.Chocolate", value = 2, weight = 8 },
        { type = "Base.PeanutButter", value = 4, weight = 6 },
        { type = "Base.Matches", value = 2, weight = 8 },
        { type = "Base.Lighter", value = 3, weight = 5 },
        { type = "Base.Battery", value = 3, weight = 6 },
        { type = "Base.Hammer", value = 8, weight = 4 },
        { type = "Base.Screwdriver", value = 5, weight = 5 },
        { type = "Base.Nails", value = 4, weight = 6 },
        { type = "Base.Bullets9mmBox", value = 12, weight = 2 },
        { type = "Base.ShotgunShellsBox", value = 12, weight = 2 },
    },
    metrics = { arrivals = 0, houses = 0, items = 0, overflow = 0 },
}
ProjectALife.OfflineLoot = Loot

local Stash = { metrics = { deposits = 0, items = 0, offline = 0 } }
ProjectALife.Stash = Stash

function Loot.percent()
    return Gate.number("Offline_LootPercent", 25, 0, 100)
end

function Loot.pick(roll)
    local total = 0
    for index = 1, #Loot.table do total = total + Loot.table[index].weight end
    local ticket = roll() * total
    for index = 1, #Loot.table do
        ticket = ticket - Loot.table[index].weight
        if ticket <= 0 then return Loot.table[index] end
    end
    return Loot.table[#Loot.table]
end

function Loot.rollHouse(roll)
    local settings = Loot.settings
    local budget = settings.housePoints * Loot.percent() / 100
    budget = budget * (1 - settings.jitter + 2 * settings.jitter * roll())
    local entries, spent, guard = {}, 0, 0
    while spent < budget and guard < settings.guard do
        guard = guard + 1
        local row = Loot.pick(roll)
        if ProjectALife.LootRarity.allowedItem(row.type) then entries[#entries + 1] = row.type end
        spent = spent + row.value
    end
    return entries, spent
end

function Loot.carriedOf(member, create)
    if type(member) ~= "table" then return nil end
    if type(member.shellState) ~= "table" then
        if not create then return nil end
        member.shellState = { version = 1, health = tonumber(member.health) or 100, maximumHealth = 100 }
    end
    if type(member.shellState.carried) ~= "table" then
        if not create then return nil end
        member.shellState.carried = {}
    end
    return member.shellState.carried
end

function Loot.count(record)
    local total = 0
    for _, member in ipairs(type(record) == "table" and record.members or {}) do
        local carried = Loot.carriedOf(member, false)
        if carried ~= nil then total = total + #carried end
    end
    return total
end

function Loot.give(record, types, roll)
    local members = type(record.members) == "table" and record.members or {}
    if #members == 0 then return 0, #types end
    local cap = Loot.settings.perMemberCap
    local given, start = 0, math.floor(roll() * #members)
    for index = 1, #types do
        local placed = false
        for step = 0, #members - 1 do
            local member = members[(start + index + step) % #members + 1]
            local carried = Loot.carriedOf(member, true)
            if carried ~= nil and #carried < cap then
                carried[#carried + 1] = { type = types[index], scavenged = true }
                placed = true
                break
            end
        end
        if placed then given = given + 1 end
    end
    return given, #types - given
end

function Loot.onArrive(record, roll)
    local task = type(record) == "table" and record.task or nil
    if type(task) == "table" and task.kind == "scavenge" and Loot.percent() > 0 then
        local settings = Loot.settings
        local houses = settings.housesMinimum + math.floor(roll() * settings.housesSpan)
        local types = {}
        for _ = 1, houses do
            local entries = Loot.rollHouse(roll)
            for index = 1, #entries do types[#types + 1] = entries[index] end
        end
        local given, overflow = Loot.give(record, types, roll)
        record.lootHouses = (tonumber(record.lootHouses) or 0) + houses
        record.lootGathered = (tonumber(record.lootGathered) or 0) + given
        Loot.metrics.arrivals = Loot.metrics.arrivals + 1
        Loot.metrics.houses = Loot.metrics.houses + houses
        Loot.metrics.items = Loot.metrics.items + given
        Loot.metrics.overflow = Loot.metrics.overflow + overflow
    end
    return Stash.depositHome(record)
end

function Stash.inventoryOf(record)
    local list = {}
    for index, member in ipairs(type(record) == "table" and record.members or {}) do
        local carried = Loot.carriedOf(member, false)
        for slot = 1, carried ~= nil and #carried or 0 do
            list[#list + 1] = { member = index, slot = slot, type = carried[slot].type, saved = carried[slot] }
        end
    end
    return list
end

function Stash.count(record)
    return Loot.count(record)
end

function Stash.homeTarget(record)
    if type(record) ~= "table" then return nil end
    local at = record.nodeId
    if record.homeNodeId == nil or at ~= record.homeNodeId then return nil end
    local havens = ProjectALife.Havens
    if type(havens) ~= "table" or type(havens.stashFor) ~= "function" then return nil end
    local ok, target = pcall(havens.stashFor, record)
    if ok then return target end
    return nil
end

function Stash.isContainer(target)
    local kind = type(target)
    return (kind == "userdata" or kind == "table") and type(target.AddItem) == "function"
end

function Stash.depositFrom(record, container, maximum)
    if type(record) ~= "table" or container == nil then return 0 end
    if type(isClient) == "function" and isClient() == true then return 0 end
    local limit = tonumber(maximum) or 1000
    local live = Stash.isContainer(container)
    if not live and type(container) ~= "table" then return 0 end
    local shellState = ProjectALife.ShellState
    local moved = 0
    for _, member in ipairs(type(record.members) == "table" and record.members or {}) do
        local carried = Loot.carriedOf(member, false)
        if carried ~= nil then
            for slot = #carried, 1, -1 do
                if moved >= limit then break end
                local saved = carried[slot]
                local placed = false
                if live then
                    local item = shellState ~= nil and type(shellState.createItem) == "function"
                        and shellState.createItem(saved) or nil
                    if item ~= nil then
                        local ok = ProjectALife.StashRoom.place(container, item)
                        if ok then placed = true end
                    end
                else
                    container.items = type(container.items) == "table" and container.items or {}
                    container.items[#container.items + 1] = { type = saved.type, scavenged = saved.scavenged }
                    placed = true
                    Stash.metrics.offline = Stash.metrics.offline + 1
                end
                if placed then
                    table.remove(carried, slot)
                    moved = moved + 1
                end
            end
        end
    end
    if moved > 0 then
        Stash.metrics.deposits = Stash.metrics.deposits + 1
        Stash.metrics.items = Stash.metrics.items + moved
        record.lootStashed = (tonumber(record.lootStashed) or 0) + moved
    end
    return moved
end

function Stash.depositHome(record)
    if Loot.count(record) == 0 then return 0 end
    local target = Stash.homeTarget(record)
    if target == nil then return 0 end
    return Stash.depositFrom(record, target)
end

return Loot
