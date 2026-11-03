require "ProjectALife/Core/ALifeCleanupLock"
require "ProjectALife/Admin/ALifeCleanup"
require "ProjectALife/Admin/ALifeCleanupWorld"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup
local World = Cleanup.World
local Lock = ProjectALife.CleanupLock

local State = {
    fixed = {
        "ProjectALife.World.v1", "ProjectALife.Outposts.v1", "ProjectALife.Squads.v1", "ProjectALife.WarDead",
        "ProjectALife.PickedOver", "ProjectALifeJimmy.PickedOver", "ProjectALife.Populate.v1",
        "ProjectALife.Rumors.v1", "ProjectALife.RoadGraph.v1", "ProjectALife.Campfires.v1",
        "ProjectALife.GroupPlans.v1", "ProjectALife.RegionLocks.v1", "ProjectALife.Mirror.v1",
    },
    reputation = {
        "ProjectALife.Reputation.v1", "ProjectALife.PersonalRep.v1", "ProjectALife.Standing.v1",
        "ProjectALife.Characters.v1",
    },
    creator = { "ProjectALife.CustomProfiles.v1", "ProjectALife.CustomFactions.v1" },
    never = { ["ProjectALifeSpawnPresets"] = true },
    playerKeys = { "palHumansKilled", "palHumanRing", "repReachedMin", "repReachedMax", "ProjectALifeCharId",
        "ProjectALifeAirRaid", "ProjectALifeLastShotAtMs" },
}
Cleanup.State = State

function State.has(name)
    if type(ModData) ~= "table" or type(ModData.exists) ~= "function" then return false end
    local ok, found = pcall(ModData.exists, name)
    return ok and found == true
end

function State.table(name)
    if not State.has(name) or type(ModData.get) ~= "function" then return nil end
    local ok, value = pcall(ModData.get, name)
    if ok and type(value) == "table" then return value end
    return nil
end

function State.listed()
    local names = {}
    if type(ModData) ~= "table" or type(ModData.getTableNames) ~= "function" then return names end
    local ok, list = pcall(ModData.getTableNames)
    if not ok or list == nil then return names end
    for _, name in ipairs(World.items(list, 512)) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    return names
end

function State.owned(name)
    return string.sub(name, 1, 11) == "ProjectALif"
end

function State.worldTag()
    local persistence = ProjectALife.Persistence
    return persistence ~= nil and persistence.TAG or "ProjectALife.World.v1"
end

function State.keepsWorld(job)
    return (tonumber(job.counts["npcs.companions_kept"]) or 0) > 0
end

function State.prune(job)
    local data = State.table(State.worldTag())
    if data == nil or type(data.stores) ~= "table" then return 0 end
    local keys = {}
    for key in pairs(data.stores) do
        if key ~= "party" then keys[#keys + 1] = key end
    end
    for _, key in ipairs(keys) do data.stores[key] = nil end
    Cleanup.count(job, "world.pruned", #keys)
    return #keys
end

function State.setOf(list)
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set
end

function State.names(job, scope)
    local result, seen = {}, {}
    local repSet, creatorSet = State.setOf(State.reputation), State.setOf(State.creator)
    local function add(name)
        if not seen[name] then
            seen[name] = true
            result[#result + 1] = name
        end
    end
    if scope == "worldState" then
        local worldTag = State.worldTag()
        for _, name in ipairs(State.fixed) do
            if not (name == worldTag and State.keepsWorld(job)) then add(name) end
        end
    elseif scope == "reputation" then
        for _, name in ipairs(State.reputation) do add(name) end
    elseif scope == "creatorStore" then
        for _, name in ipairs(State.creator) do add(name) end
    end
    return result
end

function State.rowsOf(table_)
    local rows = 0
    for _, value in pairs(table_) do
        if type(value) == "table" then
            for _ in pairs(value) do rows = rows + 1 end
        else
            rows = rows + 1
        end
    end
    return rows
end

function State.purge(job, name)
    local data = State.table(name)
    local rows = 0
    if data ~= nil then rows = State.rowsOf(data) end
    if type(ModData) == "table" and type(ModData.remove) == "function" and State.has(name) then
        local ok = pcall(ModData.remove, name)
        if not ok then Cleanup.fail(job, "modata_remove", name) end
    end
    return rows, not State.has(name)
end

function State.make(id, scope, key)
    local collector = { id = id, scopes = { scope }, terminal = true }
    function collector.begin(job)
        job.stateNames = job.stateNames or {}
        job.stateNames[id] = State.names(job, scope)
        job.cursor[id] = 1
    end
    function collector.step(job)
        local names = job.stateNames[id] or {}
        if scope == "worldState" and job.run and State.keepsWorld(job) and job.cursor.pruned ~= true then
            job.cursor.pruned = true
            State.prune(job)
        end
        while Cleanup.open(job) do
            local name = names[job.cursor[id]]
            if name == nil then return true end
            job.cursor[id] = job.cursor[id] + 1
            if State.has(name) then
                Cleanup.count(job, key .. ".tables")
                if job.run then
                    local rows, gone = State.purge(job, name)
                    Cleanup.count(job, key .. ".rows", rows)
                    if gone then Cleanup.count(job, key .. ".removed") else Cleanup.count(job, key .. ".stuck") end
                else
                    local data = State.table(name)
                    Cleanup.count(job, key .. ".rows", data ~= nil and State.rowsOf(data) or 0)
                end
            end
            Cleanup.spend(job, 0.5)
        end
        return names[job.cursor[id]] == nil
    end
    function collector.finish(job)
        if scope ~= "worldState" or not job.run then return end
        local residual = {}
        for _, name in ipairs(State.listed()) do
            if State.owned(name) and name ~= Lock.TAG and not State.never[name] then residual[#residual + 1] = name end
        end
        job.residual = residual
        if State.keepsWorld(job) then
            residual[#residual + 1] = State.worldTag() .. " (kept for " .. tostring(job.counts["npcs.companions_kept"])
                .. " companions; run again with the companions scope to remove it)"
        end
        Cleanup.count(job, "world.residual", #residual)
    end
    if scope == "worldState" then
        function collector.guard(job)
            local removed = 0
            for _, name in ipairs(State.names(job, "worldState")) do
                if State.has(name) then
                    local _, gone = State.purge(job, name)
                    if gone then removed = removed + 1 end
                end
            end
            if removed > 0 then Cleanup.log("[ALIFE-CLEANUP] guard purged " .. tostring(removed) .. " recreated tables") end
            return removed
        end
    end
    return collector
end

Cleanup.add(State.make("worldState", "worldState", "world"))
Cleanup.add(State.make("reputation", "reputation", "reputation"))
Cleanup.add(State.make("creatorStore", "creatorStore", "creator"))

local Markers = { id = "markers", scopes = { "markers" } }
Cleanup.Markers = Markers

function Markers.rows()
    local rows = {}
    local persistence = ProjectALife.Persistence
    local tag = persistence ~= nil and persistence.TAG or "ProjectALife.World.v1"
    local data = State.table(tag)
    local havens = type(data) == "table" and type(data.stores) == "table" and data.stores.havens or nil
    if type(havens) == "table" and type(havens.byId) == "table" then
        for id, haven in pairs(havens.byId) do
            if type(haven) == "table" and tonumber(haven.x) ~= nil and tonumber(haven.y) ~= nil
                    and #rows < Cleanup.settings.skipCap then
                rows[#rows + 1] = { id = tostring(id), x = math.floor(haven.x), y = math.floor(haven.y) }
            end
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

function Markers.step(job)
    local rows = Markers.rows()
    Cleanup.count(job, "markers.havens", #rows)
    if not job.run then return true end
    local sent = false
    if type(Cleanup.adapters.broadcast) == "function" then
        local ok = pcall(Cleanup.adapters.broadcast, "cleanupMarkers", { rows = rows })
        sent = ok
    end
    if sent then
        Cleanup.count(job, "markers.removed", #rows)
        Cleanup.count(job, "markers.broadcast")
    else
        Cleanup.fail(job, "markers", "no_broadcast")
    end
    return true
end

Cleanup.add(Markers)

function State.clearPlayers(job)
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return 0 end
    local ok, players = pcall(locator.list)
    if not ok or type(players) ~= "table" then return 0 end
    local cleared = 0
    for _, player in ipairs(players) do
        local data = World.dataOf(player)
        if data ~= nil then
            for _, key in ipairs(State.playerKeys) do
                if data[key] ~= nil then
                    data[key] = nil
                    cleared = cleared + 1
                end
            end
        end
    end
    return cleared
end

local Players = { id = "playerData", scopes = { "reputation" }, terminal = true }

function Players.step(job)
    if job.run then
        Cleanup.count(job, "reputation.player_keys", State.clearPlayers(job))
    end
    return true
end

Cleanup.add(Players)

return State
