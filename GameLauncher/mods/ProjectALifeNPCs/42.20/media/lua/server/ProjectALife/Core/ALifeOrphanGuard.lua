require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Compat/ALifeEquipEventShield"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Watchdog = ProjectALife.Watchdog
local Telemetry = ProjectALife.Telemetry
local OrphanGuard = { adapters = {}, cursor = 0, removed = 0, scans = 0, disarmed = 0,
    metrics = { scans = 0, removed = 0, disarmed = 0, ghosts = 0 } }
ProjectALife.OrphanGuard = OrphanGuard

function OrphanGuard.isObject(value)
    local kind = type(value)
    return kind == "userdata" or kind == "table"
end

local function listSize(list)
    if not OrphanGuard.isObject(list) or list.size == nil then return 0 end
    return tonumber(list:size()) or 0
end

local function listGet(list, index, known)
    if not OrphanGuard.isObject(list) or list.get == nil
            or index < 0 or index >= (known or listSize(list)) then return nil end
    return list:get(index)
end

function OrphanGuard.dataOf(shell)
    if shell.getModData == nil then return nil end
    if shell.hasModData ~= nil and shell:hasModData() ~= true then return nil end
    return shell:getModData()
end

local function identity(shell)
    if not OrphanGuard.isObject(shell) then return nil, nil, nil end
    local data = OrphanGuard.dataOf(shell)
    if type(data) == "table" and data.ProjectALifeOwned == true
            and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration), data
    end
    if shell.GetVariable == nil then return nil, nil, data end
    local uid = shell:GetVariable("ALifeUID")
    if type(uid) == "string" and tostring(shell:GetVariable("ALifeActor")) == "true" then
        return uid, tonumber(shell:GetVariable("ALifeGeneration")), data
    end
    return nil, nil, data
end

local function zombieList()
    if type(OrphanGuard.adapters.zombies) == "function" then
        local ok, value = pcall(OrphanGuard.adapters.zombies)
        return ok and value or nil
    end
    if type(getCell) ~= "function" then return nil end
    local ok, cell = pcall(getCell)

    if not ok or not OrphanGuard.isObject(cell) then return nil end
    local listOk, list = pcall(cell.getZombieList, cell)
    return listOk and list or nil
end

local function ownedByRuntime(shell, uid, generation, data)

    local bornAt = type(data) == "table" and tonumber(data.ProjectALifeSpawnedAtMs) or nil
    if bornAt ~= nil then
        local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
        if now >= bornAt and now - bornAt < 6000 then return true end
    end

    if type(shell.isDead) == "function" and shell:isDead() == true then return true end

    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.grappledCorpse) == "function" and sim.grappledCorpse(shell) then return true end
    local actor = (Registry.peek or Registry.read)(uid)
    if actor ~= nil and actor.lifecycle == "dead" then

        local executor = ProjectALife.Executor
        return executor ~= nil and actor.generation == generation
            and type(executor.recentRemoteDeath) == "function"
            and executor.recentRemoteDeath(shell) == true
    end
    local binding = Watchdog.bindings[uid]
    return actor ~= nil and binding ~= nil
        and (actor.lifecycle == "active" or actor.lifecycle == "spawning"
            or (actor.lifecycle == "dormant" and binding.saveCleanupFailed == true))
        and actor.generation == generation
        and binding.generation == generation and binding.shell == shell
end

local function cleanup(shell, uid, generation)
    local ok, result
    if type(OrphanGuard.adapters.cleanupShell) == "function" then
        ok, result = pcall(OrphanGuard.adapters.cleanupShell, shell, "orphan_shell")
    else
        ok = pcall(function()
            shell:removeFromWorld()
            shell:removeFromSquare()
        end)
        result = ok
    end
    if ok and result ~= false then
        OrphanGuard.removed = OrphanGuard.removed + 1
        Telemetry.emit("orphan_shell_removed", { uid = uid, generation = generation })
    end
    return ok and result ~= false
end

function OrphanGuard.configure(adapters)
    OrphanGuard.adapters = adapters or {}
end

function OrphanGuard.reset()
    OrphanGuard.cursor = 0
    OrphanGuard.removed = 0
    OrphanGuard.scans = 0
    OrphanGuard.metrics = { scans = 0, removed = 0, disarmed = 0, ghosts = 0 }
    if type(OrphanGuard.resetReload) == "function" then OrphanGuard.resetReload() end
end

function OrphanGuard.publish()
    local metrics = OrphanGuard.metrics
    metrics.scans, metrics.removed = OrphanGuard.scans, OrphanGuard.removed
    metrics.disarmed, metrics.ghosts = OrphanGuard.disarmed, OrphanGuard.ghosts or 0
end

function OrphanGuard.marked(shell)
    if not OrphanGuard.isObject(shell) then return false end
    return OrphanGuard.markedWith(shell, OrphanGuard.dataOf(shell))
end

function OrphanGuard.markedWith(shell, data)
    if type(data) == "table" then
        for key in pairs(data) do
            if type(key) == "string" and string.sub(key, 1, 11) == "ProjectALif" then return true end
        end
    end
    return shell.GetVariable ~= nil and tostring(shell:GetVariable("ALifeActor")) == "true"
end

function OrphanGuard.disarm(shell, isMarked)
    if not OrphanGuard.isObject(shell) then return false end
    if isMarked == nil then isMarked = OrphanGuard.marked(shell) end
    if isMarked then return false end
    local held = shell.getPrimaryHandItem ~= nil and (shell:getPrimaryHandItem() ~= nil
        or (shell.getSecondaryHandItem ~= nil and shell:getSecondaryHandItem() ~= nil))
    if not held then return false end
    local ok = pcall(ProjectALife.EquipEventShield.withCleanup, shell, function()
        shell:setPrimaryHandItem(nil)
        shell:setSecondaryHandItem(nil)
        shell:resetModelNextFrame()
    end)
    if ok then OrphanGuard.disarmed = OrphanGuard.disarmed + 1 end
    return ok
end

function OrphanGuard.tick(budget)
    local list = zombieList()
    local count = listSize(list)
    if count == 0 then OrphanGuard.cursor = 0; return OrphanGuard.reloadTick(OrphanGuard.clock()) end
    local ghosts = OrphanGuard.ghostStore()
    local maximum = math.max(1, math.min(count, math.floor(tonumber(budget) or 16)))
    local processed = 0
    local skipSwept

    while processed < maximum and count > 0 do
        OrphanGuard.cursor = OrphanGuard.cursor % count
        local shell = listGet(list, OrphanGuard.cursor, count)
        OrphanGuard.cursor = OrphanGuard.cursor + 1
        local uid, generation, data = identity(shell)

        local isMarked
        if uid == nil then
            isMarked = false
            if OrphanGuard.isObject(shell) then isMarked = OrphanGuard.markedWith(shell, data) end
        end
        if uid ~= nil then
            if not ownedByRuntime(shell, uid, generation, data) then
                cleanup(shell, uid, generation)
                count = listSize(list)
            end
        elseif OrphanGuard.savedGhost(shell, isMarked, ghosts) then
            if cleanup(shell, nil, nil) then OrphanGuard.ghosts = (OrphanGuard.ghosts or 0) + 1 end
            count = listSize(list)
        else
            if Watchdog ~= nil and (Watchdog.lostCount or 0) > 0 then
                if skipSwept == nil then skipSwept = OrphanGuard.reloadOn() end
                Watchdog.noteGhost(shell, skipSwept)
            end
            OrphanGuard.disarm(shell, isMarked)
        end
        processed = processed + 1
    end
    OrphanGuard.scans = OrphanGuard.scans + processed
    OrphanGuard.publish()
    return processed + OrphanGuard.reloadTick(OrphanGuard.clock())
end

OrphanGuard.ghostTtlHours = 168
OrphanGuard.ghostCap = 600
OrphanGuard.session = tostring(type(getTimestampMs) == "function" and getTimestampMs() or os.time())

function OrphanGuard.ghostStore()
    if type(OrphanGuard.adapters.ghostStore) == "function" then return OrphanGuard.adapters.ghostStore() end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then

        local spare = OrphanGuard.ghostDefaults or { squares = {}, count = 0 }
        local value = persistence.bucket("savedShells", spare)
        if value == spare then spare = nil end
        OrphanGuard.ghostDefaults = spare
        if type(value) == "table" then return value end
    end
    OrphanGuard.fallbackGhosts = OrphanGuard.fallbackGhosts or { squares = {}, count = 0 }
    return OrphanGuard.fallbackGhosts
end

function OrphanGuard.worldHours()
    if type(OrphanGuard.adapters.worldHours) == "function" then return OrphanGuard.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours) or 0
end

local function squareKey(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

function OrphanGuard.recordSaved()
    local store = OrphanGuard.ghostStore()
    store.squares = type(store.squares) == "table" and store.squares or {}
    local now, count = OrphanGuard.worldHours(), 0
    for key, entry in pairs(store.squares) do
        if type(entry) ~= "table" or now - (tonumber(entry.at) or 0) > OrphanGuard.ghostTtlHours then
            store.squares[key] = nil
        else
            count = count + 1
        end
    end
    for _, binding in pairs(Watchdog.bindings or {}) do
        if count >= OrphanGuard.ghostCap then break end
        pcall(function()
            local shell = binding.shell
            if not OrphanGuard.isObject(shell) or type(shell.isDead) ~= "function"
                    or type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
                    or type(shell.getZ) ~= "function" or type(shell.getPersistentOutfitID) ~= "function" then return end
            if shell:isDead() then return end
            local uid, generation = identity(shell)
            if uid == nil or generation == nil or generation ~= binding.generation then return end
            local key = squareKey(math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()))
            if store.squares[key] == nil then count = count + 1 end

            local outfit = tonumber(shell:getPersistentOutfitID())
            store.squares[key] = { at = now, session = OrphanGuard.session, outfit = outfit,
                uid = uid, generation = generation }
        end)
    end
    store.count = count
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
    return count
end

OrphanGuard.ghostSightMs = 10000
OrphanGuard.ghostJumpTiles = 8
OrphanGuard.sightings = setmetatable({}, { __mode = "k" })
OrphanGuard.sightingCount = 0

function OrphanGuard.firstSight(shell, x, y, outfit)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local id = shell.getOnlineID ~= nil and shell:getOnlineID() or nil
    local seen = OrphanGuard.sightings[shell]
    if seen == nil then
        OrphanGuard.sightings[shell] = { firstX = x, firstY = y, lastX = x, lastY = y, at = now, outfit = outfit, id = id }
        OrphanGuard.sightingCount = OrphanGuard.sightingCount + 1
        return true
    end
    local jump = OrphanGuard.ghostJumpTiles
    if seen.outfit ~= outfit or seen.id ~= id
            or math.abs(x - seen.lastX) > jump or math.abs(y - seen.lastY) > jump then
        seen.firstX, seen.firstY, seen.at, seen.outfit, seen.id = x, y, now, outfit, id
    end
    seen.lastX, seen.lastY = x, y
    return now - seen.at <= OrphanGuard.ghostSightMs
        and math.abs(x - seen.firstX) <= 1 and math.abs(y - seen.firstY) <= 1
end

function OrphanGuard.savedGhost(shell, isMarked, supplied)
    local store = supplied or OrphanGuard.ghostStore()
    if type(store.squares) ~= "table" or (tonumber(store.count) or 0) <= 0 then

        if OrphanGuard.sightingCount > 0 then
            OrphanGuard.sightings, OrphanGuard.sightingCount = setmetatable({}, { __mode = "k" }), 0
        end
        return false
    end
    if not OrphanGuard.isObject(shell) then return false end
    local uid, generation, data = identity(shell)
    if uid == nil or generation == nil or ownedByRuntime(shell, uid, generation, data) then return false end
    for key, entry in pairs(store.squares) do
        if type(entry) == "table" and entry.session ~= OrphanGuard.session
                and entry.uid == uid and entry.generation == generation then
            store.squares[key] = nil
            store.count = math.max(0, (tonumber(store.count) or 1) - 1)
            local persistence = ProjectALife.Persistence
            if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
            return true
        end
    end
    return false
end

function OrphanGuard.savedAt(position)
    if type(position) ~= "table" then return false end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil then return false end
    local store = OrphanGuard.ghostStore()
    if type(store.squares) ~= "table" or (tonumber(store.count) or 0) <= 0 then return false end
    x, y = math.floor(x), math.floor(y)
    local z = math.floor(tonumber(position.z) or 0)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local entry = store.squares[squareKey(x + dx, y + dy, z)]
            if type(entry) == "table" and entry.session ~= OrphanGuard.session then return true end
        end
    end
    return false
end

function OrphanGuard.purgeLoaded(limit)
    local list = zombieList()
    local count = listSize(list)
    local maximum = math.max(0, math.min(count, math.floor(tonumber(limit) or count)))
    local processed = 0
    for index = count - 1, math.max(0, count - maximum), -1 do
        local shell = listGet(list, index)
        local uid, generation, data = identity(shell)
        if uid ~= nil then
            if not ownedByRuntime(shell, uid, generation, data) then cleanup(shell, uid, generation) end
        end
        processed = processed + 1
    end
    return processed
end

OrphanGuard.reloadWindowMs = 45000
OrphanGuard.reloadRadius = 2
OrphanGuard.reloadEveryMs = 500
OrphanGuard.reloadBudgetMs = 24
OrphanGuard.reloadSliced = 0
OrphanGuard.squadEveryMs = 5000
OrphanGuard.squadQuietMs = 60000
OrphanGuard.squadRadius = 6
OrphanGuard.squadNoteGapMs = 600000
OrphanGuard.reloadAtMs = nil
OrphanGuard.squadAtMs = nil
OrphanGuard.squadSince = {}
OrphanGuard.squadNoted = {}
OrphanGuard.squadRows = {}
OrphanGuard.orphansRemoved = 0
OrphanGuard.reloadReadopt = 0
OrphanGuard.reloadDeferred = 0
OrphanGuard.reloadExpired = 0
OrphanGuard.ghostSquads = 0
OrphanGuard.bodylessSquads = 0
OrphanGuard.bodylessInReach = 0
OrphanGuard.bodylessFar = 0
OrphanGuard.squadMemberCap = 6

function OrphanGuard.reloadOn()
    local read = Watchdog.reloadGuard
    return type(read) == "function" and read() == true
end

function OrphanGuard.clock()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function OrphanGuard.resetReload()
    OrphanGuard.reloadAtMs, OrphanGuard.squadAtMs = nil, nil
    OrphanGuard.squadSince, OrphanGuard.squadNoted, OrphanGuard.squadRows = {}, {}, {}
    OrphanGuard.orphansRemoved, OrphanGuard.reloadReadopt = 0, 0
    OrphanGuard.reloadDeferred, OrphanGuard.reloadExpired = 0, 0
    OrphanGuard.reloadSliced = 0
    OrphanGuard.ghostSquads, OrphanGuard.bodylessSquads = 0, 0
    OrphanGuard.bodylessInReach, OrphanGuard.bodylessFar = 0, 0
end

function OrphanGuard.plainZombie(zombie)
    if not OrphanGuard.isObject(zombie) or zombie.isDead == nil or zombie.getX == nil or zombie.getY == nil then
        return false
    end
    if type(instanceof) == "function" and not instanceof(zombie, "IsoZombie") then return false end
    if zombie:isDead() == true then return false end
    if OrphanGuard.marked(zombie) then return false end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.grappledCorpse) == "function" and sim.grappledCorpse(zombie) == true then
        return false
    end
    return true
end

function OrphanGuard.dropBody(zombie)
    if type(zombie.removeFromWorld) ~= "function" or type(zombie.removeFromSquare) ~= "function" then return false end
    return pcall(function()
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end) == true
end

function OrphanGuard.reloadFind(cell, entry)
    local best, bestSquared
    local radius = OrphanGuard.reloadRadius
    local cx, cy = entry.x + 0.5, entry.y + 0.5
    for sx = entry.x - radius, entry.x + radius do
        for sy = entry.y - radius, entry.y + radius do
            local square = cell:getGridSquare(sx, sy, entry.z)
            local moving = OrphanGuard.isObject(square) and square.getMovingObjects ~= nil
                and square:getMovingObjects() or nil
            for index = 0, listSize(moving) - 1 do
                local zombie = moving:get(index)
                if OrphanGuard.plainZombie(zombie) then
                    local squared = (zombie:getX() - cx) ^ 2 + (zombie:getY() - cy) ^ 2
                    if bestSquared == nil or squared < bestSquared then best, bestSquared = zombie, squared end
                end
            end
        end
    end
    return best
end

function OrphanGuard.reloadNote(action, entry, zombie, now)
    local x, y, z = tonumber(zombie:getX()) or entry.x, tonumber(zombie:getY()) or entry.y, tonumber(zombie:getZ()) or entry.z
    local shown = { uid = entry.uid, reason = "reload_" .. action, x = entry.x, y = entry.y, z = entry.z, atMs = entry.atMs }
    pcall(Watchdog.emitGhost, shown, zombie, math.floor(x), math.floor(y), math.floor(z), now)
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil and type(plus.reloadNote) == "function" then
        pcall(plus.reloadNote, "ghost-" .. action, entry.uid, x, y, "lostAt=" .. tostring(entry.x) .. "," .. tostring(entry.y))
    end
end

function OrphanGuard.readopt(actor, zombie, now)
    local population, service = ProjectALife.Population, ProjectALife.SpawnService
    if population == nil or service == nil or type(service.request) ~= "function"
            or type(population.nearWindowEdge) ~= "function" or type(population.edgeBands) ~= "function" then
        return false
    end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.visit) == "table" or type(memory.guest) == "table" then return false end
    local at = { x = math.floor(zombie:getX()) + 0.5, y = math.floor(zombie:getY()) + 0.5,
        z = math.floor(tonumber(zombie:getZ()) or 0) }
    local _, respawn = population.edgeBands(now)
    if population.nearWindowEdge(at, now, respawn) then return false end
    local settings = ProjectALife.Settings
    local maximum = settings ~= nil and type(settings.current) == "table"
        and tonumber(settings.current.maximumHostileActors) or 32
    if population.capacityUsed(false) >= maximum then return false end
    if not OrphanGuard.dropBody(zombie) then return false end
    OrphanGuard.orphansRemoved = OrphanGuard.orphansRemoved + 1
    local moved = Registry.update(actor.uid, actor.revision, function(record) record.worldPosition = at end)
    if moved == nil then return true end
    local generation = (tonumber(moved.generation) or 0) + 1
    local request = service.request(actor.uid, "reload:spawn:" .. actor.uid .. ":" .. generation,
        actor.uid .. ":" .. generation .. ":" .. tostring(at.x) .. ":" .. tostring(at.y), 2500)
    if request ~= nil then
        OrphanGuard.reloadReadopt = OrphanGuard.reloadReadopt + 1
        population.retryAtMs[actor.uid], population.retryCount[actor.uid] = nil, nil
    end
    return true
end

function OrphanGuard.reloadEntry(cell, entry, now)
    local actor = (Registry.peek or Registry.read)(entry.uid)
    if actor == nil or actor.lifecycle == "dead" then return true end
    local since = math.max(entry.loadedAtMs or now, entry.watchedAtMs or 0)
    if now - since > OrphanGuard.reloadWindowMs then
        OrphanGuard.reloadExpired = OrphanGuard.reloadExpired + 1
        return true
    end
    local zombie = OrphanGuard.reloadFind(cell, entry)
    if zombie == nil then return false end
    if actor.lifecycle == "dormant" and Watchdog.bindings[entry.uid] == nil
            and OrphanGuard.readopt(actor, zombie, now) then
        OrphanGuard.reloadNote("readopt", entry, zombie, now)
        return true
    end
    local adapter = ProjectALife.ShellAdapter
    if adapter ~= nil and type(adapter.zombieWatched) == "function" and adapter.zombieWatched(zombie) == true then
        if entry.watchedAtMs == nil then OrphanGuard.reloadDeferred = OrphanGuard.reloadDeferred + 1 end
        entry.watchedAtMs = now
        return false
    end
    if not OrphanGuard.dropBody(zombie) then return false end
    OrphanGuard.orphansRemoved = OrphanGuard.orphansRemoved + 1
    OrphanGuard.reloadNote("removed", entry, zombie, now)
    return true
end

function OrphanGuard.reloadSweep(now)
    local list = Watchdog.lostSquares
    if #list == 0 or type(getCell) ~= "function" then return 0 end
    local cell = getCell()
    if not OrphanGuard.isObject(cell) or cell.getGridSquare == nil then return 0 end
    local handled = 0
    local started = OrphanGuard.clock()
    for index = #list, 1, -1 do
        local entry = list[index]
        if entry ~= nil and entry.sweep == true then
            if now - entry.atMs > Watchdog.lostTtlMs then
                table.remove(list, index)
                Watchdog.lostCount = #list
            elseif cell:getGridSquare(entry.x, entry.y, entry.z) ~= nil then
                if entry.loadedAtMs == nil then entry.loadedAtMs = now end
                if OrphanGuard.reloadEntry(cell, entry, now) then
                    table.remove(list, index)
                    Watchdog.lostCount = #list
                end
                handled = handled + 1
                if index > 1 and OrphanGuard.clock() - started >= OrphanGuard.reloadBudgetMs then
                    OrphanGuard.reloadAtMs = nil
                    OrphanGuard.reloadSliced = OrphanGuard.reloadSliced + 1
                    break
                end
            end
        end
    end
    return handled
end

function OrphanGuard.squadGroups()
    local rows = OrphanGuard.squadRows
    for key in pairs(rows) do rows[key] = nil end
    Registry.each(function(actor)
        if actor.lifecycle ~= "dead" and type(actor.worldPosition) == "table" then
            local memory = type(actor.memory) == "table" and actor.memory or {}
            local key = memory.groupId or memory.squadId
            if key ~= nil then
                local row = rows[key]
                if row == nil then
                    row = { count = 0, bound = 0, at = actor.worldPosition, uids = {} }
                    rows[key] = row
                end
                row.count = row.count + 1
                if row.count <= OrphanGuard.squadMemberCap then row.uids[row.count] = actor.uid end
                if actor.lifecycle ~= "dormant" and Watchdog.bindings[actor.uid] ~= nil then row.bound = row.bound + 1 end
            end
        end
    end)
    return rows
end

function OrphanGuard.memberWhy(uid, now)
    local actor = (Registry.peek or Registry.read)(uid)
    local population = ProjectALife.Population
    local short = string.match(tostring(uid), ":([^:]+:[^:]+)$") or tostring(uid)
    if actor == nil then return short .. ":removed" end
    local info = population ~= nil and type(population.holdInfo) == "function"
        and population.holdInfo(uid, now) or {}
    local why = actor.lifecycle == "dead" and "dead" or tostring(info.why or "none")
    return short .. ":" .. tostring(actor.lifecycle) .. "/g" .. tostring(actor.generation or 0)
        .. "/ret=" .. tostring(info.retryS or 0) .. "s/why=" .. why
end

function OrphanGuard.squadReach(row, now)
    local population = ProjectALife.Population
    if population == nil or type(population.nearestTiles) ~= "function" or type(population.hydrateReach) ~= "function" then
        return nil, nil
    end
    local first = row.uids ~= nil and (Registry.peek or Registry.read)(row.uids[1]) or nil
    local located = {}
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then
        for _, player in ipairs(locator.list(population.adapters and population.adapters.players) or {}) do
            local at = locator.position(player, population.adapters and population.adapters.playerPosition)
            if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
                located[#located + 1] = { x = tonumber(at.x), y = tonumber(at.y), z = tonumber(at.z) or 0 }
            end
        end
    end
    local at = { x = row.at.x, y = row.at.y, z = tonumber(row.at.z) or 0 }
    local near = population.nearestTiles(at, located)
    local reach = first ~= nil and tonumber(population.hydrateReach(first)) or nil
    return near, reach
end

function OrphanGuard.squadNote(key, row, near, plain, now, since)
    local plus = ProjectALife.BlackBoxPlus
    if plus == nil or type(plus.reloadNote) ~= "function" then return end
    local nearTiles, reach = OrphanGuard.squadReach(row, now)
    local inReach = nearTiles ~= nil and reach ~= nil and nearTiles <= reach
    local parts = {}
    for index = 1, math.min(row.count, OrphanGuard.squadMemberCap) do
        parts[#parts + 1] = OrphanGuard.memberWhy(row.uids[index], now)
    end
    pcall(plus.reloadNote, plain > 0 and "ghost-squad" or "bodyless-squad", tostring(key),
        row.at.x, row.at.y, "members=" .. tostring(row.count) .. " plain6=" .. tostring(plain)
        .. " quietS=" .. tostring(math.floor((now - since) / 1000))
        .. " near=" .. tostring(nearTiles or "-") .. " reach=" .. tostring(reach or "-")
        .. " inReach=" .. (inReach and "yes" or "no") .. " m=" .. table.concat(parts, ","))
    if inReach then
        OrphanGuard.bodylessInReach = OrphanGuard.bodylessInReach + 1
    else
        OrphanGuard.bodylessFar = OrphanGuard.bodylessFar + 1
    end
end

function OrphanGuard.squadSweep(now)
    local adapter = ProjectALife.ShellAdapter
    if adapter == nil or type(adapter.countZombies) ~= "function" or type(getCell) ~= "function" then return 0 end
    local cell = getCell()
    if not OrphanGuard.isObject(cell) or cell.getGridSquare == nil then return 0 end
    local since, noted = OrphanGuard.squadSince, OrphanGuard.squadNoted
    local flagged = 0
    for key, row in pairs(OrphanGuard.squadGroups()) do
        local at = row.at
        local loaded = row.bound == 0 and cell:getGridSquare(math.floor(at.x), math.floor(at.y),
            math.floor(tonumber(at.z) or 0)) ~= nil
        if not loaded then
            since[key] = nil
        elseif since[key] == nil then
            since[key] = now
        elseif now - since[key] >= OrphanGuard.squadQuietMs
                and (noted[key] == nil or now - noted[key] >= OrphanGuard.squadNoteGapMs) then
            noted[key] = now
            local near = adapter.countZombies(at, OrphanGuard.squadRadius, nil, false)
            if (near.plain or 0) > 0 then
                OrphanGuard.ghostSquads = OrphanGuard.ghostSquads + 1
            else
                OrphanGuard.bodylessSquads = OrphanGuard.bodylessSquads + 1
            end
            flagged = flagged + 1
            OrphanGuard.squadNote(key, row, near, near.plain or 0, now, since[key])
        end
    end
    for key in pairs(since) do
        if OrphanGuard.squadRows[key] == nil then since[key] = nil end
    end
    return flagged
end

function OrphanGuard.reloadTick(now)
    if not OrphanGuard.reloadOn() then return 0 end
    local worked = 0
    if OrphanGuard.reloadAtMs == nil or now < OrphanGuard.reloadAtMs
            or now - OrphanGuard.reloadAtMs >= OrphanGuard.reloadEveryMs then
        OrphanGuard.reloadAtMs = now
        worked = worked + OrphanGuard.reloadSweep(now)
    end
    if OrphanGuard.squadAtMs == nil or now < OrphanGuard.squadAtMs
            or now - OrphanGuard.squadAtMs >= OrphanGuard.squadEveryMs then
        OrphanGuard.squadAtMs = now
        worked = worked + OrphanGuard.squadSweep(now)
    end
    return worked
end

return OrphanGuard
