require "ProjectALife/Admin/ALifeCleanup"
require "ProjectALife/Admin/ALifeCleanupWorld"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup
local World = Cleanup.World

local Npcs = { id = "npcs", scopes = { "npcs" }, retryCap = 5 }
Cleanup.Npcs = Npcs

function Npcs.registry()
    return ProjectALife.ActorRegistry
end

function Npcs.partyGroups()
    local groups = {}
    local persistence = ProjectALife.Persistence
    local tag = persistence ~= nil and persistence.TAG or "ProjectALife.World.v1"
    if type(ModData) ~= "table" or type(ModData.exists) ~= "function" or type(ModData.get) ~= "function" then
        return groups
    end
    local ok, found = pcall(ModData.exists, tag)
    if not ok or found ~= true then return groups end
    local fine, state = pcall(ModData.get, tag)
    if not fine or type(state) ~= "table" or type(state.stores) ~= "table" then return groups end
    local party = state.stores.party
    if type(party) == "table" and type(party.byGroup) == "table" then
        for gid in pairs(party.byGroup) do groups[tostring(gid)] = true end
    end
    return groups
end

function Npcs.kind(record)
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.visit ~= nil or memory.guest ~= nil then return "visitor" end
    if memory.supportRole ~= nil or memory.support ~= nil or memory.supportCaller ~= nil
            or memory.supportForGroupId ~= nil then return "support" end
    if memory.outpostId ~= nil or memory.outpostSquadId ~= nil
            or (type(memory.encounter) == "string" and string.sub(memory.encounter, 1, 8) == "outpost:") then
        return "outpost"
    end
    if memory.havenId ~= nil then return "camp" end
    if type(memory.encounter) == "string" and string.find(memory.encounter, "raid", 1, true) ~= nil then return "raider" end
    if memory.squadId ~= nil then return "squad" end
    if type(memory.admin) == "table" then return "admin" end
    if memory.groupId ~= nil then return "group" end
    return "other"
end

function Npcs.companion(record, groups)
    local memory = type(record.memory) == "table" and record.memory or {}
    return memory.groupId ~= nil and groups[tostring(memory.groupId)] == true
end

function Npcs.begin(job)
    local registry = Npcs.registry()
    local groups = Npcs.partyGroups()
    job.npcUids = {}
    job.squadIds = {}
    job.cursor.npc = 1
    job.cursor.squad = 1
    job.failed = job.failed or {}
    job.companionRows = {}
    job.companionGroups = groups
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            job.npcUids[#job.npcUids + 1] = record.uid
            return false
        end)
    end
    local ledger = ProjectALife.SquadLedger
    if ledger ~= nil and type(ledger.ids) == "function" then
        local ok, ids = pcall(ledger.ids)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do job.squadIds[#job.squadIds + 1] = id end
        end
    end
end

function Npcs.retire(job, record)
    local service = ProjectALife.DebugService
    if service ~= nil and type(service.purgeActor) == "function" then
        local ok, done, reason = pcall(service.purgeActor, record, "cleanup")
        if ok and done == true then return true end
        return false, ok and reason or done
    end
    local spawn = ProjectALife.SpawnService
    if spawn == nil or type(spawn.retire) ~= "function" then return false, "no_spawn_service" end
    local ok, done, reason = pcall(spawn.retire, record.uid, "cleanup")
    if ok and done == true then return true end
    return false, ok and reason or done
end

function Npcs.work(job, uid)
    local registry = Npcs.registry()
    local record = registry.read(uid)
    if record == nil then return end
    local kind = Npcs.kind(record)
    local companion = Npcs.companion(record, job.companionGroups)
    if not job.run then
        Cleanup.count(job, "npcs.found")
        Cleanup.count(job, "npcs.kind." .. kind)
        if record.lifecycle == "active" or record.lifecycle == "spawning" then Cleanup.count(job, "npcs.live")
        elseif record.lifecycle == "dead" then Cleanup.count(job, "npcs.dead")
        else Cleanup.count(job, "npcs.dormant") end
        if companion then
            Cleanup.count(job, "npcs.companions")
            if #job.companionRows < Cleanup.settings.skipCap then
                job.companionRows[#job.companionRows + 1] = { uid = uid, name = record.name, profile = record.profileId,
                    group = record.memory and record.memory.groupId }
            end
        end
        return
    end
    if companion and job.scopes.companions ~= true then
        if job.companionKept == nil then job.companionKept = {} end
        if job.companionKept[uid] ~= true then
            job.companionKept[uid] = true
            Cleanup.count(job, "npcs.companions_kept")
            local at = type(record.worldPosition) == "table" and record.worldPosition or {}
            Cleanup.skip(job, "npcs", { x = at.x, y = at.y, z = at.z, what = "companion " .. tostring(record.profileId),
                why = "companion" })
        end
        return
    end
    local retries = tonumber(job.failed[uid]) or 0
    if retries >= Npcs.retryCap then return end
    local done, reason = Npcs.retire(job, record)
    Cleanup.spend(job, 1)
    if done then
        Cleanup.count(job, "npcs.removed")
        Cleanup.count(job, "npcs.removed_" .. kind)
        if record.lifecycle == "active" or record.lifecycle == "spawning" then Cleanup.count(job, "npcs.removed_live") end
    else
        job.failed[uid] = retries + 1
        Cleanup.fail(job, "npc_retire", tostring(reason))
        if retries + 1 >= Npcs.retryCap then
            local at = type(record.worldPosition) == "table" and record.worldPosition or {}
            Cleanup.skip(job, "npcs", { x = at.x, y = at.y, z = at.z, what = "npc " .. tostring(record.profileId),
                why = "remove_failed:" .. tostring(reason) })
        end
    end
end

function Npcs.squads(job)
    local ledger = ProjectALife.SquadLedger
    if ledger == nil then return true end
    while Cleanup.open(job) do
        local id = job.squadIds[job.cursor.squad]
        if id == nil then return true end
        job.cursor.squad = job.cursor.squad + 1
        local squad = ledger.peek(id)
        if squad ~= nil then
            local companion = job.companionGroups[tostring(id)] == true
            if not job.run then
                Cleanup.count(job, "npcs.squads")
                if companion then Cleanup.count(job, "npcs.companion_squads") end
            elseif companion and job.scopes.companions ~= true then
                Cleanup.count(job, "npcs.companion_squads_kept")
            else
                local ok, removed = pcall(ledger.remove, id, squad.revision, "cleanup")
                if ok and removed == true then
                    Cleanup.count(job, "npcs.squads_removed")
                else
                    Cleanup.fail(job, "squad", tostring(removed))
                end
                Cleanup.spend(job, 1)
            end
        end
    end
    return false
end

function Npcs.step(job)
    while Cleanup.open(job) do
        local uid = job.npcUids[job.cursor.npc]
        if uid == nil then break end
        job.cursor.npc = job.cursor.npc + 1
        local ok, reason = pcall(Npcs.work, job, uid)
        if not ok then Cleanup.fail(job, "npc", reason) end
        Cleanup.spend(job, 0.1)
    end
    if job.npcUids[job.cursor.npc] ~= nil then return false end
    return Npcs.squads(job) == true
end

function Npcs.pending(job)
    if not job.run then return 0 end
    local registry = Npcs.registry()
    local total = 0
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            local companion = Npcs.companion(record, job.companionGroups or {})
            if not (companion and job.scopes.companions ~= true)
                    and (tonumber((job.failed or {})[record.uid]) or 0) < Npcs.retryCap then
                total = total + 1
            end
            return false
        end)
    end
    return total
end

Cleanup.add(Npcs)

local Bodies = { id = "bodies", scopes = { "npcs" } }
Cleanup.Bodies = Bodies

function Bodies.marked(shell)
    local data = World.dataOf(shell)
    if data == nil then return false, nil end
    if data.ProjectALifeOwned == true or type(data.ProjectALifeUID) == "string" then
        return true, data.ProjectALifeUID
    end
    return false, nil
end

function Bodies.savedSquares()
    local persistence = ProjectALife.Persistence
    local tag = persistence ~= nil and persistence.TAG or "ProjectALife.World.v1"
    if type(ModData) ~= "table" or type(ModData.exists) ~= "function" or type(ModData.get) ~= "function" then return {} end
    local ok, found = pcall(ModData.exists, tag)
    if not ok or found ~= true then return {} end
    local fine, data = pcall(ModData.get, tag)
    if not fine or type(data) ~= "table" or type(data.stores) ~= "table" then return {} end
    local store = data.stores.savedShells
    if type(store) == "table" and type(store.squares) == "table" then return store.squares end
    return {}
end

function Bodies.begin(job)
    local list = {}
    local cell = World.cell()
    if cell ~= nil and type(cell.getZombieList) == "function" then
        local ok, zombies = pcall(cell.getZombieList, cell)
        if ok then list = World.items(zombies, 8192) end
    end
    Cleanup.volatile.zombies = list
    job.cursor.body = 1
    if job.ghosts == nil then
        job.ghosts = {}
        local squares = Bodies.savedSquares()
        for key, entry in pairs(squares) do
            if type(entry) == "table" and #job.ghosts < Cleanup.settings.watchCap then
                local x, y, z = string.match(tostring(key), "^(-?%d+),(-?%d+),(-?%d+)$")
                if x ~= nil then
                    job.ghosts[#job.ghosts + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), uid = entry.uid }
                end
            end
        end
        if #job.ghosts > 0 then Cleanup.count(job, "npcs.ghost_squares", #job.ghosts) end
    end
end

function Bodies.owned(uid)
    if uid == nil then return false end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return false end
    return (registry.peek or registry.read)(uid) ~= nil
end

function Bodies.remove(job, shell)
    local adapter = ProjectALife.ShellAdapter
    if adapter ~= nil and type(adapter.cleanupShell) == "function" then
        local ok, done = pcall(adapter.cleanupShell, shell)
        if ok and done ~= false then return true end
    end
    local removed = false
    if type(shell.removeFromWorld) == "function" then removed = pcall(shell.removeFromWorld, shell) end
    if type(shell.removeFromSquare) == "function" then pcall(shell.removeFromSquare, shell) end
    return removed
end

function Bodies.work(job, shell)
    local marked, uid = Bodies.marked(shell)
    if not marked then return end
    if Bodies.owned(uid) then
        Cleanup.count(job, "npcs.bodies_registered")
        return
    end
    Cleanup.count(job, "npcs.orphan_bodies")
    if not job.run then return end
    if Bodies.remove(job, shell) then
        Cleanup.count(job, "npcs.removed")
        Cleanup.count(job, "npcs.removed_bodies")
    else
        Cleanup.fail(job, "orphan_body", "remove_failed")
    end
    Cleanup.spend(job, 1)
end

function Bodies.settleGhosts(job)
    local keep = {}
    for _, ghost in ipairs(job.ghosts or {}) do
        if World.loaded(ghost.x, ghost.y) then
            Cleanup.count(job, "npcs.ghost_squares_swept")
        else
            keep[#keep + 1] = ghost
            Cleanup.watch(job, ghost.x, ghost.y)
        end
    end
    job.ghosts = keep
end

function Bodies.step(job)
    local list = Cleanup.volatile.zombies or {}
    while Cleanup.open(job) do
        local shell = list[job.cursor.body]
        if shell == nil then break end
        job.cursor.body = job.cursor.body + 1
        local ok, reason = pcall(Bodies.work, job, shell)
        if not ok then Cleanup.fail(job, "body", reason) end
        Cleanup.spend(job, 0.05)
    end
    if list[job.cursor.body] ~= nil then return false end
    if job.run then Bodies.settleGhosts(job) end
    return true
end

function Bodies.pending(job)
    if not job.run then return 0 end
    return #(job.ghosts or {})
end

function Bodies.pendingList(job, limit)
    local rows = {}
    for _, ghost in ipairs(job.ghosts or {}) do
        if #rows >= limit then break end
        rows[#rows + 1] = { kind = "ghost", id = "ghost", x = ghost.x, y = ghost.y, z = ghost.z, left = 1 }
    end
    return rows
end

Cleanup.add(Bodies)

return Npcs
