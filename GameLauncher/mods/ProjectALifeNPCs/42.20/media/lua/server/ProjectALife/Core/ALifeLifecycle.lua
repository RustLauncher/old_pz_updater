require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Shells/ALifeDeathDrops"
require "ProjectALife/Shells/ALifeDeathInventory"
require "ProjectALife/Shells/ALifeShellState"
require "ProjectALife/Decisions/ALifeDecisionLoop"
require "ProjectALife/Core/ALifeKillAttribution"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Audio/ALifeHumanReactions"
require "ProjectALife/Combat/ALifeBlood"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Watchdog = ProjectALife.Watchdog
local DeathDrops = ProjectALife.DeathDrops
local Decisions = ProjectALife.DecisionLoop
local KillAttribution = ProjectALife.KillAttribution
local Reputation = ProjectALife.Reputation
local Interop = ProjectALife.Interop
local Lifecycle = {
    adapters = {}, pending = {}, order = {},

    corpses = {},
    turning = {},
    turnOrder = {},
    settings = {

        turnSearchMs = 60000,

        turnBudget = 2,

        corpseRemovalMs = 1200000,

        corpsePlayerDistance = 30,

        corpseBudget = 2,

        turnDelayMinS = 20,
        turnDelayMaxS = 90,
        turnStepCapMs = 5000,
        turnGroanMs = 3000,
        turnMaxHeld = 64,
        putDownReach = 3.5,
        putDownNoiseRadius = 24,
        putDownNoiseVolume = 40,
    },
    metrics = { corpsesTracked = 0, corpsesRemoved = 0, corpsesLost = 0,
        stolenLootDropped = 0, stolenLootHeld = 0, turnsQueued = 0, turnsScheduled = 0, turnsLost = 0,
        turnsDelayed = 0, turnsPutDown = 0, turnsGroaned = 0, turnsHeld = 0, turnsRestored = 0,
        putDownRefused = 0, putDownFaults = 0 },
    turnRestored = false,
}
ProjectALife.Lifecycle = Lifecycle

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    if type(Lifecycle.adapters.emit) == "function" then
        pcall(Lifecycle.adapters.emit, category, fields or {})
    end
end

local function identity(shell)
    local ok, uid, generation = pcall(function()
        local data = shell:getModData()
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
    end)
    if ok and type(uid) == "string" and generation ~= nil then return uid, generation end
    ok, uid, generation = pcall(function()
        return shell:GetVariable("ALifeUID"),
            tonumber(shell:GetVariable("ALifeGeneration"))
    end)
    return ok and uid or nil, ok and generation or nil
end

function Lifecycle.configure(adapters)
    adapters = adapters or {}
    Lifecycle.adapters = adapters
    DeathDrops.configure(adapters.deathDrops)
end

function Lifecycle.corpseDue(entry, now, nearestPlayerFlat, settings)
    if type(entry) ~= "table" then return false end
    settings = settings or Lifecycle.settings
    local since = (tonumber(now) or 0) - (tonumber(entry.atMs) or 0)
    if since < (tonumber(settings.corpseRemovalMs) or 0) then return false end
    local reach = tonumber(settings.corpsePlayerDistance) or 0
    local nearest = tonumber(nearestPlayerFlat)
    if nearest ~= nil and nearest < reach * reach then return false end
    return true
end

local function reclaimCorpse(entry)
    local removed = false
    pcall(function()
        local square = getCell():getGridSquare(math.floor(entry.x),
            math.floor(entry.y), math.floor(entry.z or 0))
        if square == nil then return end
        local bodies = square:getDeadBodys()
        if bodies == nil then return end
        for index = bodies:size() - 1, 0, -1 do
            local body = bodies:get(index)
            local data = body ~= nil and body:getModData() or nil
            if type(data) == "table" and data.ProjectALifeUID == entry.uid then
                square:removeCorpse(body, false)
                removed = true
                return
            end
        end
    end)
    return removed
end

function Lifecycle.playerPoints()
    local points = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list()) do
            local point = locator.position(player)
            if point ~= nil then points[#points + 1] = point end
        end
    end)
    return points
end

local function nearestPlayerFlat(x, y, points)
    local best
    for _, point in ipairs(points) do
        local dx, dy = (point.x or 0) - x, (point.y or 0) - y
        local flat = dx * dx + dy * dy
        if best == nil or flat < best then best = flat end
    end
    return best
end

function Lifecycle.sweepCorpses(now, budget)
    now = tonumber(now) or nowMs()
    local allowed = math.max(1, math.floor(tonumber(budget)
        or Lifecycle.settings.corpseBudget or 1))
    local handled, index, points = 0, 1, nil
    while handled < allowed and index <= #Lifecycle.corpses do
        local entry = Lifecycle.corpses[index]

        local due = type(entry) == "table" and Lifecycle.corpseDue(entry, now, nil)
        if due then
            points = points or Lifecycle.playerPoints()
            due = Lifecycle.corpseDue(entry, now, nearestPlayerFlat(entry.x, entry.y, points))
        end
        if type(entry) ~= "table" then
            table.remove(Lifecycle.corpses, index)
        elseif due then
            if reclaimCorpse(entry) then
                Lifecycle.metrics.corpsesRemoved = Lifecycle.metrics.corpsesRemoved + 1
            else

                Lifecycle.metrics.corpsesLost = Lifecycle.metrics.corpsesLost + 1
            end
            table.remove(Lifecycle.corpses, index)
            handled = handled + 1
        else
            index = index + 1
        end
    end
    return handled
end

function Lifecycle.trackCorpse(uid, position, now)
    if type(uid) ~= "string" or type(position) ~= "table" then return false end
    Lifecycle.corpses[#Lifecycle.corpses + 1] = {
        uid = uid, x = tonumber(position.x) or 0, y = tonumber(position.y) or 0,
        z = tonumber(position.z) or 0, atMs = tonumber(now) or nowMs(),
    }
    Lifecycle.metrics.corpsesTracked = Lifecycle.metrics.corpsesTracked + 1
    return true
end

function Lifecycle.reset()
    Lifecycle.pending = {}
    Lifecycle.order = {}
    Lifecycle.turning = {}
    Lifecycle.turnOrder = {}
    Lifecycle.turnRestored = false
end

function Lifecycle.killedByZombie(shell)
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.reportedKiller) == "function" then
        local ok, kind = pcall(executor.reportedKiller, shell)
        if ok and kind ~= nil then return kind == "zombie" end
    end
    local ok, kind, _, _, _, killer = pcall(KillAttribution.peek, shell)
    if not ok or kind ~= "zombie" or killer == shell then return false end
    if killer ~= nil and type(instanceof) == "function" and not instanceof(killer, "IsoZombie") then return false end
    return true
end

function Lifecycle.infectedAtDeath(shell, actor)
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.reanimationEnabled) ~= "function" or not sim.reanimationEnabled() then return false end
    if sim.loreValue("Transmission", 1) == 3 then return true end
    local data = nil
    if type(shell.getModData) == "function" then data = shell:getModData() end
    if type(data) == "table" and data.ProjectALifeTurnAtHours ~= nil then return true end
    local memory = nil
    if type(actor) == "table" then memory = actor.memory end
    if type(memory) == "table" and memory.infectedTurnAtHours ~= nil then return true end
    return Lifecycle.killedByZombie(shell) and sim.woundInfects("killed")
end

function Lifecycle.shellPosition(shell)
    return shell:getX(), shell:getY(), shell:getZ()
end

function Lifecycle.sandboxValue(name)
    local vars = nil
    if type(SandboxVars) == "table" then vars = SandboxVars.ALife end
    if type(vars) ~= "table" then return nil end
    return vars[name]
end

function Lifecycle.turnOptions()
    local loaded = ProjectALife.Settings
    local current = nil
    if type(loaded) == "table" then current = loaded.current end
    if type(current) == "table" and current.turningEnabled ~= nil then
        return current.turningEnabled == true, tonumber(current.turningDelayMinS), tonumber(current.turningDelayMaxS)
    end
    return Lifecycle.sandboxValue("Turning_Enabled") ~= false,
        tonumber(Lifecycle.sandboxValue("Turning_DelaySecondsMin")),
        tonumber(Lifecycle.sandboxValue("Turning_DelaySecondsMax"))
end

function Lifecycle.turnDelayMs()
    local enabled, low, high = Lifecycle.turnOptions()
    if not enabled then return 0 end
    local settings = Lifecycle.settings
    if low == nil then low = settings.turnDelayMinS end
    if high == nil then high = settings.turnDelayMaxS end
    low = math.max(0, low)
    high = math.max(low, high)
    local span = math.floor(high - low)
    local extra = 0
    if span > 0 and type(ZombRand) == "function" then extra = ZombRand(span + 1) end
    return math.floor((low + extra) * 1000)
end

function Lifecycle.markPending(target)
    if target == nil or type(target.getModData) ~= "function" then return false end
    local data = target:getModData()
    if type(data) ~= "table" or data.ProjectALifeTurnPending == true then return false end
    data.ProjectALifeTurnPending = true
    return true
end

function Lifecycle.clearPending(target)
    if target == nil or type(target.getModData) ~= "function" then return false end
    if type(target.hasModData) == "function" and target:hasModData() ~= true then return false end
    local data = target:getModData()
    if type(data) ~= "table" or data.ProjectALifeTurnPending == nil then return false end
    data.ProjectALifeTurnPending = nil
    return true
end

function Lifecycle.turnStore()
    local reader = Lifecycle.adapters.turnStore
    if type(reader) ~= "function" then return nil end
    local ok, store = pcall(reader)
    if not ok or type(store) ~= "table" then return nil end
    if type(store.rows) ~= "table" then store.rows = {} end
    return store
end

function Lifecycle.saveTurns()
    local store = Lifecycle.turnStore()
    if store == nil then return false end
    local rows = {}
    for _, uid in ipairs(Lifecycle.turnOrder) do
        local entry = Lifecycle.turning[uid]
        if entry ~= nil then
            local left = math.max(0, (tonumber(entry.delayMs) or 0) - (tonumber(entry.loadedMs) or 0))
            rows[#rows + 1] = { uid = uid, x = entry.x, y = entry.y, z = entry.z, left = left }
        end
    end
    store.rows = rows
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
    return true
end

function Lifecycle.restoreTurns()
    Lifecycle.turnRestored = true
    local store = Lifecycle.turnStore()
    if store == nil then return 0 end
    local restored = 0
    for _, row in ipairs(store.rows) do
        local uid = type(row) == "table" and row.uid or nil
        if type(uid) == "string" and Lifecycle.turning[uid] == nil and tonumber(row.x) ~= nil
                and tonumber(row.y) ~= nil and #Lifecycle.turnOrder < Lifecycle.settings.turnMaxHeld then
            local now = nowMs()
            Lifecycle.turning[uid] = { uid = uid, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) or 0,
                atMs = now, delayMs = math.max(0, tonumber(row.left) or 0), loadedMs = 0, restored = true }
            Lifecycle.turnOrder[#Lifecycle.turnOrder + 1] = uid
            Lifecycle.metrics.turnsRestored = Lifecycle.metrics.turnsRestored + 1
            restored = restored + 1
        end
    end
    return restored
end

function Lifecycle.noteTurning(shell, actor, uid)
    if type(uid) ~= "string" or Lifecycle.turning[uid] ~= nil then return false end
    if not Lifecycle.infectedAtDeath(shell, actor) then return false end
    local ok, x, y, z = pcall(Lifecycle.shellPosition, shell)
    if not ok or tonumber(x) == nil or tonumber(y) == nil then return false end
    if Lifecycle.turnRestored ~= true then Lifecycle.restoreTurns() end
    local now = nowMs()
    local delayMs = Lifecycle.turnDelayMs()
    Lifecycle.turning[uid] = { uid = uid, x = x, y = y, z = tonumber(z) or 0, atMs = now,
        delayMs = delayMs, loadedMs = 0, missingSinceMs = now }
    Lifecycle.turnOrder[#Lifecycle.turnOrder + 1] = uid
    Lifecycle.metrics.turnsQueued = Lifecycle.metrics.turnsQueued + 1
    while #Lifecycle.turnOrder > Lifecycle.settings.turnMaxHeld do
        local oldest = table.remove(Lifecycle.turnOrder, 1)
        if Lifecycle.turning[oldest] ~= nil then
            Lifecycle.turning[oldest] = nil
            Lifecycle.metrics.turnsLost = Lifecycle.metrics.turnsLost + 1
        end
    end
    if delayMs > 0 then
        Lifecycle.markPending(shell)
        Lifecycle.metrics.turnsDelayed = Lifecycle.metrics.turnsDelayed + 1
        emit("turn_delayed", { uid = uid, delayMs = delayMs })
        Lifecycle.saveTurns()
    end
    return true
end

function Lifecycle.corpseNamed(body, uid)
    if body == nil or type(body.getModData) ~= "function" then return false end
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return false end
    local data = body:getModData()
    return type(data) == "table" and (data.ProjectALifeCorpseOf == uid or data.ProjectALifeUID == uid)
end

function Lifecycle.corpseOf(entry)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local bx, by, bz = math.floor(entry.x), math.floor(entry.y), math.floor(entry.z)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(bx + dx, by + dy, bz)
            if square ~= nil and type(square.getDeadBodys) == "function" then
                local bodies = square:getDeadBodys()
                local count = 0
                if bodies ~= nil and type(bodies.size) == "function" then count = bodies:size() end
                for index = 0, count - 1 do
                    local body = bodies:get(index)
                    if Lifecycle.corpseNamed(body, entry.uid) then return body end
                end
            end
        end
    end
    return nil
end

function Lifecycle.scrubForTurn(body)
    local data = body:getModData()
    if type(data) ~= "table" then return 0 end
    local doomed = {}
    for key in pairs(data) do
        if type(key) == "string" and (string.sub(key, 1, 12) == "ProjectALife" or string.sub(key, 1, 5) == "ALife") then
            doomed[#doomed + 1] = key
        end
    end
    for index = 1, #doomed do data[doomed[index]] = nil end
    return #doomed
end

function Lifecycle.squareUnloaded(entry)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    return cell:getGridSquare(math.floor(entry.x), math.floor(entry.y), math.floor(entry.z)) == nil
end

function Lifecycle.turnGroan(body)
    local female = false
    if type(body.isFemale) == "function" then female = body:isFemale() == true end
    local pick = 0
    if type(ZombRand) == "function" then pick = ZombRand(3) end
    local name = "MaleZombieVoice"
    if female then name = "FemaleZombieVoice" end
    name = name .. string.sub("ABC", pick + 1, pick + 1)
    local square = nil
    if type(body.getSquare) == "function" then square = body:getSquare() end
    if type(isServer) == "function" and isServer() == true then
        if not ProjectALife.AudioPolicy.playFrom(body, name) then return false end
    elseif square ~= nil and type(square.playSound) == "function" then
        square:playSound(name)
    elseif type(body.playSound) == "function" then
        body:playSound(name)
    else
        return false
    end
    Lifecycle.metrics.turnsGroaned = Lifecycle.metrics.turnsGroaned + 1
    return true
end

function Lifecycle.stepTurn(entry, body, now)
    now = tonumber(now) or 0
    local cap = tonumber(Lifecycle.settings.turnStepCapMs) or 5000
    if entry.seenAtMs ~= nil and now > entry.seenAtMs then
        entry.loadedMs = (tonumber(entry.loadedMs) or 0) + math.min(now - entry.seenAtMs, cap)
    end
    entry.seenAtMs = now
    entry.missingSinceMs = nil
    entry.held = nil
    local left = (tonumber(entry.delayMs) or 0) - (tonumber(entry.loadedMs) or 0)
    if left > 0 then
        Lifecycle.markPending(body)
        if left <= Lifecycle.settings.turnGroanMs and entry.groaned ~= true then
            entry.groaned = true
            Lifecycle.turnGroan(body)
        end
        return false
    end
    Lifecycle.scrubForTurn(body)
    body:reanimateLater()
    Lifecycle.metrics.turnsScheduled = Lifecycle.metrics.turnsScheduled + 1
    return true
end

function Lifecycle.settleTurning(now)
    if Lifecycle.turnRestored ~= true then Lifecycle.restoreTurns() end
    local order = Lifecycle.turnOrder
    local budget = math.max(1, math.floor(tonumber(Lifecycle.settings.turnBudget) or 2))
    local checked, index, seen, changed = 0, 1, #order, false
    while checked < budget and index <= #order and seen > 0 do
        seen = seen - 1
        local uid = order[index]
        local entry = Lifecycle.turning[uid]
        local done = entry == nil
        if not done then
            checked = checked + 1
            local body = Lifecycle.corpseOf(entry)
            if body ~= nil and type(body.reanimateLater) == "function" then
                done = Lifecycle.stepTurn(entry, body, now)
                if done then changed = true end
            elseif Lifecycle.squareUnloaded(entry) then
                entry.seenAtMs, entry.missingSinceMs = nil, nil
                if entry.held ~= true then
                    entry.held = true
                    Lifecycle.metrics.turnsHeld = Lifecycle.metrics.turnsHeld + 1
                    changed = true
                end
            else
                entry.seenAtMs = nil
                if entry.missingSinceMs == nil then entry.missingSinceMs = tonumber(now) or 0 end
                if (tonumber(now) or 0) - entry.missingSinceMs > Lifecycle.settings.turnSearchMs then
                    Lifecycle.metrics.turnsLost = Lifecycle.metrics.turnsLost + 1
                    done = true
                    changed = true
                end
            end
        end
        table.remove(order, index)
        if done then
            Lifecycle.turning[uid] = nil
        else
            order[#order + 1] = uid
        end
    end
    if changed then Lifecycle.saveTurns() end
    return checked
end

function Lifecycle.putDownReply(player, payload)
    if player == nil then return false end
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", "putDownCorpse", payload) end
        return true
    end
    local receive = ProjectALife.PutDownReceive
    if type(receive) == "function" then
        receive(payload)
        return true
    end
    return false
end

function Lifecycle.putDownNoise(player, weapon)
    local combat = ProjectALife.Combat
    if combat == nil or type(combat.worldNoise) ~= "function" then return false end
    local radius, volume = Lifecycle.settings.putDownNoiseRadius, Lifecycle.settings.putDownNoiseVolume
    if type(weapon.getSoundRadius) == "function" then radius = tonumber(weapon:getSoundRadius()) or radius end
    if type(weapon.getSoundVolume) == "function" then volume = tonumber(weapon:getSoundVolume()) or volume end
    local heard = combat.worldNoise(player, radius, volume)
    local shot = nil
    if type(weapon.getSwingSound) == "function" then shot = weapon:getSwingSound() end
    if type(shot) == "string" and shot ~= "" then ProjectALife.AudioPolicy.playFrom(player, shot) end
    return heard == true
end

function Lifecycle.putDownRefuse(player, payload, reason)
    payload.reason = reason
    Lifecycle.metrics.putDownRefused = Lifecycle.metrics.putDownRefused + 1
    Lifecycle.putDownReply(player, payload)
    return false, reason
end

function Lifecycle.putDown(player, args)
    local uid = nil
    if type(args) == "table" then uid = args.uid end
    local payload = { uid = type(uid) == "string" and uid or "", ok = false }
    if player == nil or type(uid) ~= "string" or uid == "" or #uid > 64 then
        return Lifecycle.putDownRefuse(player, payload, "unavailable")
    end
    local entry = Lifecycle.turning[uid]
    if entry == nil then return Lifecycle.putDownRefuse(player, payload, "not_pending") end
    local body = Lifecycle.corpseOf(entry)
    if body == nil or type(body.getX) ~= "function" or type(player.getX) ~= "function" then
        return Lifecycle.putDownRefuse(player, payload, "unavailable")
    end
    local reach = Lifecycle.settings.putDownReach
    local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
    if math.abs(body:getZ() - player:getZ()) > 0.5 or dx * dx + dy * dy > reach * reach then
        return Lifecycle.putDownRefuse(player, payload, "too_far")
    end
    local sim = ProjectALife.ShellSimulation
    local weapon, kind = nil, nil
    if sim ~= nil and type(sim.putDownWeapon) == "function" then weapon, kind = sim.putDownWeapon(player) end
    if weapon == nil then return Lifecycle.putDownRefuse(player, payload, "no_weapon") end
    Lifecycle.turning[uid] = nil
    Lifecycle.clearPending(body)
    if kind == "firearm" then Lifecycle.putDownNoise(player, weapon) end
    Lifecycle.metrics.turnsPutDown = Lifecycle.metrics.turnsPutDown + 1
    emit("turn_put_down", { uid = uid, weapon = kind })
    Lifecycle.saveTurns()
    payload.ok, payload.kind = true, kind
    Lifecycle.putDownReply(player, payload)
    if type(isServer) == "function" and isServer() and type(sendServerCommand) == "function" then
        sendServerCommand("ProjectALife", "turnCleared", { uid = uid, x = entry.x, y = entry.y, z = entry.z })
    end
    return true
end

function Lifecycle.onClientCommand(module, command, player, args)
    if module ~= "ProjectALife" or command ~= "putDownCorpse" then return end
    local ok = pcall(Lifecycle.putDown, player, args)
    if not ok then Lifecycle.metrics.putDownFaults = Lifecycle.metrics.putDownFaults + 1 end
end

local function recordWeaponDuplicates(shell, actor)
    pcall(function()
        local items = shell:getInventory():getItems()
        local counts, worstType, worstCount, total = {}, nil, 0, 0
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local weapon = false
            pcall(function() weapon = item:IsWeapon() == true end)
            local fullType = ""
            pcall(function() fullType = tostring(item:getFullType() or "") end)
            if weapon and fullType ~= "" and fullType ~= "Base.BareHands" then
                total = total + 1
                counts[fullType] = (counts[fullType] or 0) + 1
                if counts[fullType] > worstCount then
                    worstType, worstCount = fullType, counts[fullType]
                end
            end
        end
        Lifecycle.metrics = Lifecycle.metrics or {}
        Lifecycle.metrics.deathWeaponsCarried =
            (Lifecycle.metrics.deathWeaponsCarried or 0) + total
        if worstCount > 1 then
            Lifecycle.metrics.deathDuplicateBodies =
                (Lifecycle.metrics.deathDuplicateBodies or 0) + 1
            if worstCount > (Lifecycle.metrics.deathDuplicateWorst or 0) then
                Lifecycle.metrics.deathDuplicateWorst = worstCount
                Lifecycle.metrics.deathDuplicateType = worstType
            end
            emit("death_duplicate_weapons", {
                uid = actor.uid, generation = actor.generation,
                itemType = worstType, count = worstCount, weapons = total,
            })
        end
    end)
end

local function finishPhysicalDeath(shell, actor)
    Decisions.forget(actor.uid, actor.generation, "shell_dead")
    recordWeaponDuplicates(shell, actor)

    local authority = not (type(isClient) == "function" and isClient())
    local dropOk, dropped, dropReason = true, true, nil
    if authority then
        dropOk, dropped, dropReason = pcall(DeathDrops.process, shell, actor)
    end
    if not dropOk or dropped ~= true then
        emit("death_drop_failed", {
            uid = actor.uid, generation = actor.generation,
            error = dropOk and dropReason or tostring(dropped),
        })
    end
    local unbound, unbindReason = Watchdog.unbind(
        actor.uid, actor.generation, "shell_dead")
    if not unbound and unbindReason ~= "shell_not_bound" then
        emit("death_unbind_failed", {
            uid = actor.uid, generation = actor.generation, error = unbindReason,
        })
    end

    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.markCorpse) == "function" then sim.markCorpse(shell) end
end

local function fanOutAttributedDeath(actor, shell)
    local ok, kind, key, x, y, killer = pcall(KillAttribution.resolve, shell)
    if not ok then
        emit("kill_attribution_failed", { uid = actor.uid, error = tostring(kind) })
        Interop.died(shell, actor.uid, actor.generation, nil)
        return
    end
    Interop.died(shell, actor.uid, actor.generation, killer)
    pcall(function()
        local revenge = ProjectALife.Revenge
        if revenge ~= nil then
            revenge.onActorDied(actor, shell, kind, key, x, y)
        end
    end)
    if kind == "player" then
        local standoff = ProjectALife.Standoff
        if standoff ~= nil and type(standoff.breakTruce) == "function" then pcall(standoff.breakTruce, actor, key) end
        local track = ProjectALife.RepTrack
        if track ~= nil and type(track.onActorKilled) == "function" then pcall(track.onActorKilled, killer, actor, key) end
        pcall(Reputation.onPlayerKilledActor, killer or key, actor)
        local personal = ProjectALife.PersonalRep
        if personal ~= nil and type(personal.onActorKilled) == "function" then
            pcall(personal.onActorKilled, actor, shell, key, killer)
        end
        if ProjectALife.NpcOpinion ~= nil and type(ProjectALife.NpcOpinion.noteKill) == "function" then
            pcall(ProjectALife.NpcOpinion.noteKill, actor, key, killer)
        end
    end

    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory ~= nil and type(memory.stolenLoot) == "table" and #memory.stolenLoot > 0 then

        local loot = memory.stolenLoot
        memory.stolenLoot = nil
        pcall(function()
            if Registry == nil then return end
            local current = Registry.read(actor.uid)
            if current == nil then return end
            Registry.updateTransient(current.uid, current.revision, function(record)
                record.memory = type(record.memory) == "table" and record.memory or {}
                record.memory.stolenLoot = nil
            end)
        end)
        do
            pcall(function()
                local square = shell:getCurrentSquare()
                if square == nil then return end
                for index, saved in ipairs(loot) do
                    if index > 12 then break end
                    local item = ProjectALife.ShellState.createItem(saved)
                    if item ~= nil then
                        square:AddWorldInventoryItem(item, 0.2 + (index % 5) * 0.15, 0.3 + (index % 3) * 0.2, 0)
                    end
                end
            end)

            if Lifecycle ~= nil then
                Lifecycle.metrics = Lifecycle.metrics or {}
                Lifecycle.metrics.stolenLootDropped =
                    (Lifecycle.metrics.stolenLootDropped or 0) + #loot
            end
        end
    end
end

local function queueDurableDeath(shell, actor, position, reason)
    local current = Registry.read(actor.uid)
    local quarantined = current and Registry.updateTransient(
        current.uid, current.revision, function(record)
            record.lifecycle = "dead"
            record.activity = "dead"
            record.intent = "none"
            if position ~= nil then record.worldPosition = position end
            record.memory = type(record.memory) == "table" and record.memory or {}
            record.memory.pendingDeathPersistence = true
        end)
    if quarantined == nil then return false, "death_quarantine_failed" end
    if Lifecycle.pending[actor.uid] == nil then
        Lifecycle.order[#Lifecycle.order + 1] = actor.uid
    end
    Lifecycle.pending[actor.uid] = {
        uid = actor.uid, generation = actor.generation, shell = shell,
        position = position, reason = reason, attempts = 0,
    }
    finishPhysicalDeath(shell, quarantined)
    emit("death_persistence_pending", {
        uid = actor.uid, generation = actor.generation, error = reason,
    })
    return true
end

function Lifecycle.handToOwner(shell, uid)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.killDelegated) ~= "function"
            or type(executor.serverDelegates) ~= "function" or executor.serverDelegates() ~= true then
        return false
    end
    local ok, handed = pcall(executor.killDelegated, shell, uid, "server_kill")
    return ok and handed == true
end

function Lifecycle.reportedDeath(shell, uid, generation)
    local executor = ProjectALife.Executor
    return executor ~= nil and type(executor.takeReported) == "function"
        and executor.takeReported(shell, uid, generation) == true
end

function Lifecycle.finishReported(shell, actor)
    finishPhysicalDeath(shell, actor)
    pcall(function()
        local survival = ProjectALife.Survival
        local memory = type(actor.memory) == "table" and actor.memory or nil
        if survival ~= nil and memory ~= nil then
            survival.noteLoss(memory.groupId, { x = shell:getX(), y = shell:getY(), z = shell:getZ() }, nowMs())
        end
    end)
    local reactions = ProjectALife.HumanReactions
    if reactions ~= nil then reactions.forget(actor.uid) end
    fanOutAttributedDeath(actor, shell)
    Lifecycle.metrics.reportedDeaths = (Lifecycle.metrics.reportedDeaths or 0) + 1
    return true, "reported_death"
end

function Lifecycle.onShellDeath(shell)
    if shell == nil then return false, "death_shell_missing" end
    local blood = ProjectALife.Blood
    if blood ~= nil then pcall(blood.onDeath, shell) end

    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and sim.grappledCorpse ~= nil and sim.grappledCorpse(shell) then
        return true, "grappled_corpse"
    end
    local uid, generation = identity(shell)
    if type(uid) ~= "string" or type(generation) ~= "number" then
        return false, "death_shell_not_owned"
    end
    local actor = Registry.read(uid)
    if actor == nil then return false, "death_actor_missing" end
    if actor.generation ~= generation then return false, "death_generation_stale" end
    Lifecycle.noteTurning(shell, actor, uid)
    local injury = ProjectALife.Injury
    if injury ~= nil and type(injury.onDeath) == "function" then pcall(injury.onDeath, shell) end

    ProjectALife.DeathInventory.restore(shell)

    pcall(function()
        shell:setReanimate(false)
        shell:setFakeDead(false)
        shell:setForceFakeDead(false)
    end)

    pcall(function()
        local entrances = ProjectALife.Entrances
        if entrances ~= nil then entrances.release(uid) end
    end)
    if actor.lifecycle == "dead" then
        if actor.generation == generation and Lifecycle.reportedDeath(shell, uid, generation) then
            return Lifecycle.finishReported(shell, actor)
        end
        return true, "already_dead"
    end
    local position
    local positionOk, x, y, z = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ()
    end)
    if positionOk then position = { x = x, y = y, z = z } end
    local current = Registry.read(uid)
    local dead, deadError = Registry.markDead(
        uid, current.revision, generation, position)
    if dead == nil then
        local queued, queueError = queueDurableDeath(shell, actor, position, deadError)
        if queued then
            Lifecycle.handToOwner(shell, uid)
            fanOutAttributedDeath(actor, shell)
        end
        return false, queued and "death_persistence_pending" or queueError
    end
    finishPhysicalDeath(shell, dead)
    Lifecycle.handToOwner(shell, uid)
    pcall(function()
        local survival = ProjectALife.Survival
        local memory = type(actor.memory) == "table" and actor.memory or nil
        if survival ~= nil and memory ~= nil then survival.noteLoss(memory.groupId, position, nowMs()) end
    end)

    Lifecycle.trackCorpse(uid, position, nowMs())

    local reactions = ProjectALife.HumanReactions
    if reactions ~= nil then
        reactions.death(shell, uid)
        reactions.forget(uid)
    end
    emit("actor_died", { uid = uid, generation = generation })

    fanOutAttributedDeath(actor, shell)

    pcall(function()
        local leader = ProjectALife.ModuleLeader
        if leader ~= nil then leader.onActorDied(actor) end
    end)
    return true
end

function Lifecycle.tick(budget)
    local maximum = math.max(1, math.floor(tonumber(budget) or 4))
    local processed = Lifecycle.sweepCorpses(nowMs())
    Lifecycle.settleTurning(nowMs())
    local index = 1
    while processed < maximum and index <= #Lifecycle.order do
        local uid = Lifecycle.order[index]
        local entry = Lifecycle.pending[uid]
        if entry == nil then
            table.remove(Lifecycle.order, index)
        else
            local actor = Registry.read(uid)
            if actor == nil or actor.generation ~= entry.generation then
                Lifecycle.pending[uid] = nil
                table.remove(Lifecycle.order, index)
            else
                entry.attempts = entry.attempts + 1
                local persisted, reason = Registry.update(
                    uid, actor.revision, function(record)
                        record.lifecycle = "dead"
                        record.activity = "dead"
                        record.intent = "none"
                        record.memory = type(record.memory) == "table" and record.memory or {}
                        record.memory.pendingDeathPersistence = nil
                    end)
                if persisted ~= nil then
                    Lifecycle.pending[uid] = nil
                    table.remove(Lifecycle.order, index)
                    Registry.pruneDead(Registry.maximumDeadRecords)
                    emit("death_persistence_recovered", {
                        uid = uid, generation = entry.generation, attempts = entry.attempts,
                    })
                else
                    entry.reason = reason
                    index = index + 1
                end
            end
            processed = processed + 1
        end
    end
    return processed
end

function Lifecycle.pendingCount()
    return #Lifecycle.order
end

if type(Events) == "table" and Events.OnClientCommand ~= nil and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Lifecycle.onClientCommand)
end

return Lifecycle
