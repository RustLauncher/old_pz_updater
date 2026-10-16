require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeCustomProfileAuthority"
require "ProjectALife/Records/ALifeCustomFactionAuthority"
require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/World/ALifeSpawnService"
require "ProjectALife/Shells/ALifeShellAdapter"
require "ProjectALife/Decisions/ALifeDecisionLoop"
require "ProjectALife/World/ALifePopulation"
require "ProjectALife/World/ALifeDirector"
require "ProjectALife/Core/ALifeLifecycle"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Offline/ALifeOfflineDirector"
require "ProjectALife/Outposts/ALifeOutpostRegistry"
require "ProjectALife/Outposts/ALifeOutpostDirector"
require "ProjectALife/World/ALifeSupport"
require "ProjectALife/Outposts/ALifeOutpostRadio"
require "ProjectALife/Outposts/ALifeOutpostTheft"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/Admin/ALifeDiagnostics"
require "ProjectALife/Core/ALifeOrphanGuard"
require "ProjectALife/World/ALifeEncounterDirector"
require "ProjectALife/World/ALifeRaidDirector"
require "ProjectALife/World/ALifeMetaDirector"
require "ProjectALife/World/ALifePopulateDirector"
require "ProjectALife/World/ALifeTownWelcome"
require "ProjectALife/Talk/ALifeTalk"
require "ProjectALife/Talk/ALifeTalkOrders"
require "ProjectALife/Talk/ALifeParty"
require "ProjectALife/Talk/ALifeChatterDirector"
require "ProjectALife/Behaviours/ALifeModuleTalkPresence"
require "ProjectALife/Behaviours/ALifeModuleRobbery"
require "ProjectALife/Decisions/ALifeStandoff"
require "ProjectALife/Decisions/ALifeKnowledge"
require "ProjectALife/Talk/ALifeRumors"
require "ProjectALife/Decisions/ALifeRisk"
require "ProjectALife/Fear/ALifeThreatWatch"
require "ProjectALife/World/ALifeBaseHeat"
require "ProjectALife/World/ALifeSafehouseDirector"
require "ProjectALife/World/ALifeSafehouseVisit"
require "ProjectALife/World/ALifeIntrusionCue"
require "ProjectALife/World/ALifeResidentCorpses"
require "ProjectALife/Outposts/ALifeSceneKit"
require "ProjectALife/Activities/ALifeActivityService"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Decisions/ALifeReputationPersonal"
require "ProjectALife/Decisions/ALifeNpcOpinion"
require "ProjectALife/Decisions/ALifeStanding"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Admin/ALifeBlackBox"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Persistence = ProjectALife.Persistence
local Registry = ProjectALife.ActorRegistry
local SpawnService = ProjectALife.SpawnService
local Watchdog = ProjectALife.Watchdog
local ShellAdapter = ProjectALife.ShellAdapter
local Decisions = ProjectALife.DecisionLoop
local Population = ProjectALife.Population
local Director = ProjectALife.Director
local Lifecycle = ProjectALife.Lifecycle
local Telemetry = ProjectALife.Telemetry
local SpawnPolicy = ProjectALife.SpawnPolicy
local Diagnostics = ProjectALife.Diagnostics
local OrphanGuard = ProjectALife.OrphanGuard
local Animations = ProjectALife.Animations
local Reputation = ProjectALife.Reputation

if ProjectALife.BlackBox ~= nil and type(ProjectALife.BlackBox.readBuild) == "function" then
    ProjectALife.BlackBox.readBuild()
end
local Runtime = {
    VERSION = "1.3.15",

    BUILD = ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.BUILD or "unknown",
    started = false,
    enabled = true,
    lastError = nil,
    lastTickAtMs = 0,
    tickIntervalMs = 100,
    tickBudget = 8,
    adapters = {},
    presentationCursor = 0,
    lastPresentationSyncAtMs = 0,
    metrics = { ticks = 0, lastTickMs = 0, maximumTickMs = 0, faults = 0, overruns = 0,
        hitches = {}, hitchCount = 0, totalCount = 0, details = {}, detailCount = 0,
        overrunBy = {}, windowOverruns = 0 },

    hitchThresholdsMs = { 16, 33, 50, 100 },
    hitchWindowMs = 60000,
    hitchWindowAtMs = nil,
}
ProjectALife.Runtime = Runtime

local function nowMs()
    if type(Runtime.adapters.nowMs) == "function" then return Runtime.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    Telemetry.emit(category, fields)
    if type(Runtime.adapters.emit) == "function" then Runtime.adapters.emit(category, fields) end
end

local function serverAuthority()
    if type(isClient) == "function" and isClient()
            and (type(isServer) ~= "function" or not isServer()) then
        return false
    end
    return true
end

Runtime.rehomeFallbackId = "alife_riverside"
Runtime.lastRehomed = 0

function Runtime.rehome(record, catalog)
    if type(record) ~= "table" or type(catalog) ~= "table" then return false end
    if type(catalog.factions) ~= "table" then return false end
    local factionId = Runtime.rehomeFallbackId
    if catalog.factions[factionId] == nil then

        factionId = Runtime.rehomeInSeason(catalog, record.uid)
        local first = catalog.factionOrder and catalog.factionOrder[1]
        factionId = factionId or (type(first) == "table" and first.id or nil)
    end
    if factionId == nil or catalog.factions[factionId] == nil then return false end
    local chosen = Runtime.rosterPick(catalog, factionId, record.uid)
    if chosen == nil then return false end
    record.factionId = factionId
    record.profileId = chosen
    return true
end

function Runtime.rehomeInSeason(catalog, key)
    local rules = ProjectALife.FactionSpawnRules
    if rules == nil or type(rules.inSeason) ~= "function" then return nil end
    for _, faction in ipairs(type(catalog.factionOrder) == "table" and catalog.factionOrder or {}) do
        if type(faction) == "table" and catalog.factions[faction.id] ~= nil and rules.inSeason(faction)
                and not (type(rules.visitorOnly) == "function" and rules.visitorOnly(faction))
                and Runtime.rosterPick(catalog, faction.id, key) ~= nil then
            return faction.id
        end
    end
    return nil
end

function Runtime.rosterPick(catalog, factionId, key, taken)
    local roster = {}
    for _, npc in ipairs(catalog.npcOrder or {}) do
        if type(npc) == "table" and npc.general and npc.general.faction == factionId then
            roster[#roster + 1] = npc
        end
    end
    if #roster == 0 then return nil end
    local hash, text = 5381, tostring(key or "")
    for index = 1, #text do
        hash = (hash * 33 + string.byte(text, index)) % 2147483647
    end
    local at = hash % #roster
    if type(taken) == "table" then
        local free = nil
        for step = 0, #roster - 1 do
            local candidate = roster[1 + (at + step) % #roster]
            if taken[candidate.id] ~= true then free = candidate break end
        end
        if free == nil then
            local used = {}
            for id in pairs(taken) do used[#used + 1] = id end
            for _, id in ipairs(used) do taken[id] = nil end
            free = roster[1 + at]
        elseif free ~= roster[1 + at] then
            local draw = ProjectALife.RosterDraw
            if draw ~= nil then draw.metrics.avoided = draw.metrics.avoided + 1 end
        end
        taken[free.id] = true
        return free.id
    end
    return roster[1 + at].id
end

function Runtime.tombstoned(catalog, factionId, profileId)
    local factions = type(catalog) == "table" and catalog.deletedFactions or nil
    if factionId ~= nil and type(factions) == "table" and factions[factionId] == true then return true end
    local custom = ProjectALife.CustomProfiles
    return profileId ~= nil and custom ~= nil and type(custom.isDeleted) == "function"
        and custom.isDeleted(profileId) == true
end

function Runtime.squadPick(catalog, head, profileId, key, uid, taken)
    local npcs = type(catalog.npcs) == "table" and catalog.npcs or {}
    local profile = profileId ~= nil and npcs[profileId] or nil
    if profile ~= nil and type(profile.general) == "table" and profile.general.faction == head.factionId then
        if type(taken) == "table" then taken[profileId] = true end
        return nil
    end
    if profile == nil and Runtime.tombstoned(catalog, nil, profileId) then return nil end
    local registry = ProjectALife.ActorRegistry
    local record = uid ~= nil and registry ~= nil and registry.read(uid) or nil
    local own = record ~= nil and npcs[record.profileId] or nil
    if own ~= nil and type(own.general) == "table" and own.general.faction == head.factionId then
        if type(taken) == "table" then taken[record.profileId] = true end
        return record.profileId
    end
    return Runtime.rosterPick(catalog, head.factionId, key, taken)
end

function Runtime.rehomeSquads(catalog)
    local ledger = ProjectALife.SquadLedger
    if ledger == nil or type(catalog) ~= "table" or type(catalog.factions) ~= "table" then return 0 end
    local moved = 0
    for _, squad in ipairs(ledger.list()) do
        local head = { uid = tostring(squad.id), factionId = squad.factionId }
        local homeless = head.factionId == nil or catalog.factions[head.factionId] == nil
        if Runtime.tombstoned(catalog, head.factionId, nil)
                or (homeless and not Runtime.rehome(head, catalog)) then
            head = nil
        end
        local uids = type(squad.renderedUids) == "table" and squad.renderedUids or {}
        local release = type(squad.releasePending) == "table" and squad.releasePending.members or nil
        local picks, kept, changed = {}, {}, homeless and head ~= nil
        local taken = {}
        for index, member in ipairs(head ~= nil and type(squad.members) == "table" and squad.members or {}) do
            picks[index] = Runtime.squadPick(catalog, head, member.profileId,
                head.uid .. ":member:" .. tostring(index), uids[index], taken)
            changed = changed or picks[index] ~= nil
        end
        for index, member in ipairs(head ~= nil and type(release) == "table" and release or {}) do
            kept[index] = Runtime.squadPick(catalog, head, member.profileId,
                head.uid .. ":release:" .. tostring(index), nil, taken)
            changed = changed or kept[index] ~= nil
        end
        if changed and ledger.update(squad.id, squad.revision, function(q)
                q.factionId = head.factionId
                for index, member in ipairs(type(q.members) == "table" and q.members or {}) do
                    member.profileId = picks[index] or member.profileId
                end
                local pending = type(q.releasePending) == "table" and q.releasePending.members or nil
                for index, member in ipairs(type(pending) == "table" and pending or {}) do
                    member.profileId = kept[index] or member.profileId
                end

                local spec = type(q.stagePending) == "table" and q.stagePending.specification or nil
                if type(spec) == "table" then
                    spec.factionId = head.factionId
                    spec.profileId = picks[#uids + 1] or spec.profileId
                end
            end) ~= nil then
            moved = moved + 1
        end
    end
    return moved
end

function Runtime.rehomeSites(catalog)
    local sites = ProjectALife.OutpostRegistry
    if sites == nil or type(catalog) ~= "table" or type(catalog.factions) ~= "table" then return 0 end
    local moved = 0
    for _, site in ipairs(sites.list()) do
        local head = { uid = tostring(site.id) }
        if site.state ~= "expired" and type(site.factionId) == "string"
                and catalog.factions[site.factionId] == nil
                and not Runtime.tombstoned(catalog, site.factionId, nil)
                and Runtime.rehome(head, catalog)
                and sites.update(site.id, site.revision, function(s) s.factionId = head.factionId end) ~= nil then
            moved = moved + 1
        end
    end
    return moved
end

function Runtime.start(options)
    if Runtime.started then return true, "already_started" end
    if not serverAuthority() then return false, "server_authority_required" end
    options = options or {}
    Runtime.enabled = options.enabled ~= false
    Runtime.adapters = options.runtimeAdapters or {}
    Telemetry.reset()
    Telemetry.configure({ nowMs = Runtime.adapters.nowMs, log = Runtime.adapters.log })
    Persistence.configure(options.persistenceAdapters)

    local foundingCap = tonumber(options.offlineAdapters and options.offlineAdapters.squadCap)
    ProjectALife.SquadLedger.configure({ maximum =
        (foundingCap ~= nil and foundingCap > 0) and foundingCap or Persistence.squadCap })
    local shellAdapters = options.shellAdapters or {}
    shellAdapters.profile = shellAdapters.profile or {}
    shellAdapters.profile.emit = shellAdapters.profile.emit or emit
    ShellAdapter.configure(shellAdapters)
    local lifecycleAdapters = options.lifecycleAdapters or {}
    lifecycleAdapters.emit = lifecycleAdapters.emit or emit
    lifecycleAdapters.turnStore = lifecycleAdapters.turnStore
        or function() return Persistence.bucket("pendingTurns", { rows = {} }) end
    Lifecycle.reset()
    Lifecycle.configure(lifecycleAdapters)
    SpawnPolicy.configure(options.spawnPolicyAdapters)
    Animations.configure({ nowMs = Runtime.adapters.nowMs })

    local multiplayerAuthority = type(options.customProfileAdapters) == "table"
        or (type(isServer) == "function" and isServer())
    if multiplayerAuthority then
        ProjectALife.CustomProfileAuthority.configure(options.customProfileAdapters)
        local profilesOk, profilesError = ProjectALife.CustomProfileAuthority.load(false)
        if not profilesOk then
            Runtime.lastError = "creator_profiles_load_failed:" .. tostring(profilesError)
            return false, Runtime.lastError
        end

        ProjectALife.CustomFactionAuthority.configure(options.customFactionAdapters)
        local factionsOk, factionsError = ProjectALife.CustomFactionAuthority.load(false)
        if not factionsOk then
            Runtime.lastError = "creator_factions_load_failed:" .. tostring(factionsError)
            return false, Runtime.lastError
        end
    else
        ProjectALife.CustomProfiles.serverManaged = false
        ProjectALife.CustomFactions.serverManaged = false
    end

    local catalog, catalogError
    if type(options.factionText) == "string" and type(options.npcText) == "string" then
        catalog, catalogError = Catalog.loadFromText(options.factionText, options.npcText)
    else
        catalog, catalogError = Catalog.load()
    end
    if catalog == nil then
        Runtime.lastError = catalogError
        return false, catalogError
    end
    Reputation.configure(options.reputationAdapters)
    ProjectALife.PersonalRep.configure(options.personalReputationAdapters)
    ProjectALife.NpcOpinion.reset()
    ProjectALife.Standing.configure(options.standingAdapters)

    local saved, loadError = Persistence.load()
    if saved == nil then
        Runtime.lastError = loadError
        return false, loadError
    end

    ProjectALife.SceneKit.reset()
    ProjectALife.SceneKit.recover()

    SpawnService.reset()
    local naturalMembers = {}
    for operationId, operation in pairs(saved.operations or {}) do
        if string.sub(tostring(operationId), 1, 9) == "director:" then
            naturalMembers[operation.uid] = true
        end
    end

    local rehomed = 0
    local restored, normalized, migration = Registry.restore(saved, function(record)
        local profile = Catalog.npc(record.profileId)
        local faction = Catalog.faction(record.factionId)
        if profile == nil or faction == nil or not profile.general
                or profile.general.faction ~= record.factionId then
            if Runtime.tombstoned(catalog, record.factionId, record.profileId) then return true end
            if not Runtime.rehome(record, catalog) then return false end
            rehomed = rehomed + 1
            profile = Catalog.npc(record.profileId)
            faction = Catalog.faction(record.factionId)
            if profile == nil or faction == nil then return false end
        end
        Director.restoreMemberPolicy(record, faction, profile, naturalMembers[record.uid])
        return true
    end)
    Runtime.lastRehomed = rehomed
    if not restored then
        Runtime.lastError = normalized
        return false, normalized
    end

    local spawnAdapters = options.spawnAdapters or ShellAdapter.spawnAdapters({
        nowMs = Runtime.adapters.nowMs,
        newUid = Runtime.adapters.newUid,
        persist = Persistence.save,
        emit = emit,
    })
    if options.spawnAdapters then
        spawnAdapters.persist = Persistence.save
        spawnAdapters.emit = spawnAdapters.emit or emit
        spawnAdapters.nowMs = spawnAdapters.nowMs or Runtime.adapters.nowMs
    end
    local externalDormant = spawnAdapters.onActorDormant
    spawnAdapters.onActorDormant = function(actor, reason)
        Decisions.forget(actor.uid, actor.generation, reason)
        if type(externalDormant) == "function" then
            pcall(externalDormant, actor, reason)
        end
    end
    local externalRecovered = spawnAdapters.onShellRecovered
    spawnAdapters.onShellRecovered = function(actor, shell, reason)
        Decisions.forget(actor.uid, actor.generation, "shell_recovered")
        if type(externalRecovered) == "function" then
            pcall(externalRecovered, actor, shell, reason)
        end
    end
    local configured, configureError = SpawnService.configure(spawnAdapters)
    if not configured then
        Runtime.lastError = configureError
        return false, configureError
    end
    OrphanGuard.reset()
    OrphanGuard.configure({ cleanupShell = spawnAdapters.cleanupShell })
    local orphanScan = OrphanGuard.purgeLoaded(4096)
    Decisions.reset()
    Decisions.configure(options.decisionAdapters)
    Population.reset()
    local populationAdapters = options.populationAdapters or {}
    populationAdapters.nowMs = populationAdapters.nowMs or Runtime.adapters.nowMs
    Population.configure(populationAdapters)
    Director.reset()
    Director.configure(options.directorAdapters)

    ProjectALife.OfflineDirector.reset()
    ProjectALife.OfflineDirector.configure(options.offlineAdapters)

    ProjectALife.OutpostRegistry.configure({})
    ProjectALife.OutpostDirector.reset()
    ProjectALife.OutpostDirector.configure(options.outpostAdapters)
    ProjectALife.OutpostDirector.resumeSession()
    Runtime.lastRehomed = Runtime.lastRehomed + Runtime.rehomeSquads(catalog) + Runtime.rehomeSites(catalog)
    ProjectALife.Support.configure(options.supportAdapters)
    ProjectALife.OutpostRadio.reset()
    ProjectALife.OutpostRadio.configure(options.outpostAdapters)
    ProjectALife.OutpostTheft.reset()
    ProjectALife.OutpostTheft.configure({})
    ProjectALife.BaseHeat.reset()
    ProjectALife.BaseHeat.configure(options.baseHeatAdapters)
    if ProjectALife.DoorPolicy ~= nil and type(ProjectALife.DoorPolicy.reset) == "function" then ProjectALife.DoorPolicy.reset() end
    ProjectALife.BaseHeat.flagConfigure(options.safehouseAdapters)
    if ProjectALife.SafehouseDirector ~= nil then
        ProjectALife.SafehouseVisit.reset()
        ProjectALife.SafehouseDirector.reset()
        ProjectALife.SafehouseDirector.configure(options.safehouseAdapters)
    end
    ProjectALife.RaidDirector.reset()
    ProjectALife.RaidDirector.configure(options.raidAdapters)
    ProjectALife.MetaDirector.reset()
    ProjectALife.MetaDirector.configure(options.metaAdapters)

    ProjectALife.PopulateDirector.reset()
    ProjectALife.PopulateDirector.configure(options.populateAdapters)
    ProjectALife.TownWelcome.reset()
    ProjectALife.TownWelcome.configure(options.welcomeAdapters)
    ProjectALife.ResidentCorpses.reset()
    ProjectALife.ResidentCorpses.configure(options.residentCorpseAdapters)

    Runtime.configureTalk(options.talkAdapters)
    if normalized > 0 and not Persistence.save(Registry.snapshot()) then
        Runtime.lastError = "normalized_snapshot_save_failed"
        return false, Runtime.lastError
    end

    Runtime.started = true
    Runtime.lastError = nil
    Runtime.lastTickAtMs = 0
    Runtime.presentationCursor = 0
    Runtime.lastPresentationSyncAtMs = 0
    Runtime.metrics = {
        ticks = 0, lastTickMs = 0, maximumTickMs = 0,
        faults = 0, overruns = 0, subsystemFaults = {},
        hitches = {}, hitchCount = 0,
        totalCount = 0, details = {}, detailCount = 0, overrunBy = {}, windowOverruns = 0,
    }
    Runtime.hitchWindowAtMs = nil
    emit("runtime_started", {
        factions = #catalog.factionOrder,
        npcs = #catalog.npcOrder,
        restoredActors = #Registry.list(),
        normalizedActors = normalized,
        removedUnknownActors = migration and migration.unknownActors or 0,
        inspectedLoadedShells = orphanScan,
    })
    return true
end

local function syncPresentation(now)
    if type(isServer) ~= "function" or not isServer()
            or now - Runtime.lastPresentationSyncAtMs < 500
            or #Watchdog.order == 0 then return 0 end
    Runtime.lastPresentationSyncAtMs = now
    local sent = 0

    for index = 1, math.min(64, #Watchdog.order) do
        Runtime.presentationCursor = (Runtime.presentationCursor % #Watchdog.order) + 1
        local binding = Watchdog.bindings[Watchdog.order[Runtime.presentationCursor]]
        if binding and binding.shell then
            Animations.syncPresentation(binding.shell)
            sent = sent + 1
        end
    end
    return sent
end

function Runtime.safeStart(options)
    local ok, started, reason = pcall(Runtime.start, options)
    if not ok then
        Runtime.lastError = tostring(started)
        Telemetry.emit("runtime_start_failed", { error = Runtime.lastError })
        return false, Runtime.lastError
    end
    if started ~= true then
        Runtime.lastError = reason
        Telemetry.emit("runtime_start_failed", { error = reason })
    end
    return started == true, reason
end

local function runSubsystem(name, callback)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.skips(name) then return 0 end
    local started = nowMs()
    local ok, result = pcall(callback)
    local elapsed = math.max(0, nowMs() - started)
    Runtime.metrics.subsystems = Runtime.metrics.subsystems or {}
    local timing = Runtime.metrics.subsystems[name] or { calls = 0, totalMs = 0, maximumMs = 0 }
    timing.calls, timing.totalMs = timing.calls + 1, timing.totalMs + elapsed
    timing.lastMs, timing.maximumMs = elapsed, math.max(timing.maximumMs, elapsed)
    timing.lastAtMs = started
    Runtime.metrics.subsystems[name] = timing
    if elapsed > Runtime.hitchThresholdsMs[1] then Runtime.noteHitch(name, elapsed) end
    if ok then return math.max(0, tonumber(result) or 0) end
    Runtime.lastError = name .. ":" .. tostring(result)
    Runtime.metrics.faults = (Runtime.metrics.faults or 0) + 1
    Runtime.metrics.subsystemFaults[name] =
        (Runtime.metrics.subsystemFaults[name] or 0) + 1
    Runtime.metrics.lastFault = Runtime.lastError
    emit("runtime_fault", { subsystem = name, error = result })
    return 0
end

function Runtime.noteHitch(name, elapsed)
    local limits = Runtime.hitchThresholdsMs
    if type(elapsed) ~= "number" or elapsed <= limits[1] then return false end
    local metrics = Runtime.metrics
    metrics.hitches = metrics.hitches or {}
    local row = metrics.hitches[name]
    if row == nil then
        row = { maximumMs = 0 }
        for index = 1, #limits do row[index] = 0 end
        metrics.hitches[name] = row
    end
    for index = 1, #limits do
        if elapsed > limits[index] then row[index] = row[index] + 1 end
    end
    row.maximumMs = math.max(row.maximumMs, elapsed)
    metrics.hitchCount = (metrics.hitchCount or 0) + 1
    return true
end

function Runtime.hitchOrder(a, b)
    for index = #a.row, 1, -1 do
        if a.row[index] ~= b.row[index] then return a.row[index] > b.row[index] end
    end
    if a.row.maximumMs ~= b.row.maximumMs then return a.row.maximumMs > b.row.maximumMs end
    return a.name < b.name
end

function Runtime.bumpRow(rows, name, elapsed)
    local limits = Runtime.hitchThresholdsMs
    local row = rows[name]
    if row == nil then
        row = { maximumMs = 0 }
        for index = 1, #limits do row[index] = 0 end
        rows[name] = row
    end
    for index = 1, #limits do
        if elapsed > limits[index] then row[index] = row[index] + 1 end
    end
    row.maximumMs = math.max(row.maximumMs, elapsed)
    return row
end

function Runtime.noteTotal(elapsed)
    if type(elapsed) ~= "number" or elapsed <= Runtime.hitchThresholdsMs[1] then return false end
    local metrics = Runtime.metrics
    metrics.totalRows = metrics.totalRows or {}
    Runtime.bumpRow(metrics.totalRows, "total", elapsed)
    metrics.totalCount = (metrics.totalCount or 0) + 1
    return true
end

function Runtime.noteDetail(name, elapsed)
    if type(elapsed) ~= "number" or elapsed <= Runtime.hitchThresholdsMs[1] then return false end
    local metrics = Runtime.metrics
    metrics.details = metrics.details or {}
    Runtime.bumpRow(metrics.details, tostring(name), elapsed)
    metrics.detailCount = (metrics.detailCount or 0) + 1
    return true
end

function Runtime.slowestSubsystem(now)
    local slowest, cost = "unknown", 0
    for name, timing in pairs(Runtime.metrics.subsystems or {}) do
        if (timing.lastAtMs or -math.huge) >= now and (timing.lastMs or 0) > cost then
            slowest, cost = name, timing.lastMs
        end
    end
    return slowest, cost
end

function Runtime.noteOverrun(slowest)
    local metrics = Runtime.metrics
    metrics.overrunBy = metrics.overrunBy or {}
    metrics.overrunBy[slowest] = (metrics.overrunBy[slowest] or 0) + 1
    metrics.windowOverruns = (metrics.windowOverruns or 0) + 1
end

function Runtime.rowText(name, row)
    local counts = {}
    for level = 1, #row do counts[level] = tostring(row[level]) end
    return tostring(name) .. "=" .. table.concat(counts, "/")
        .. "/" .. tostring(math.floor(row.maximumMs)) .. "ms"
end

function Runtime.quietWindow(metrics)
    return (metrics.hitchCount or 0) == 0 and (metrics.totalCount or 0) == 0
        and (metrics.detailCount or 0) == 0 and (metrics.windowOverruns or 0) == 0
end

function Runtime.worstRows(rows, limit, parts)
    local sorted = {}
    for name, row in pairs(rows or {}) do sorted[#sorted + 1] = { name = name, row = row } end
    table.sort(sorted, Runtime.hitchOrder)
    for index = 1, math.min(limit, #sorted) do
        parts[#parts + 1] = Runtime.rowText(sorted[index].name, sorted[index].row)
    end
    if #sorted > limit then parts[#parts + 1] = "+" .. tostring(#sorted - limit) end
    return #sorted
end

function Runtime.reportHitches(now)
    if Runtime.hitchWindowAtMs == nil then
        Runtime.hitchWindowAtMs = now
        return false
    end
    if now - Runtime.hitchWindowAtMs < Runtime.hitchWindowMs then return false end
    local metrics = Runtime.metrics
    local windowMs = now - Runtime.hitchWindowAtMs
    Runtime.hitchWindowAtMs = now
    if Runtime.quietWindow(metrics) then return false end
    local parts = {}
    local total = metrics.totalRows ~= nil and metrics.totalRows.total or nil
    if total ~= nil then parts[#parts + 1] = Runtime.rowText("total", total) end
    Runtime.worstRows(metrics.hitches, 6, parts)
    if (metrics.windowOverruns or 0) > 0 then
        local by = {}
        for name, count in pairs(metrics.overrunBy or {}) do by[#by + 1] = tostring(name) .. ":" .. tostring(count) end
        table.sort(by)
        parts[#parts + 1] = "overruns=" .. tostring(metrics.windowOverruns) .. "(" .. table.concat(by, ",") .. ")"
    end
    if (metrics.detailCount or 0) > 0 then
        parts[#parts + 1] = "detail"
        Runtime.worstRows(metrics.details, 4, parts)
    end
    local count = metrics.hitchCount or 0
    metrics.hitches, metrics.hitchCount = {}, 0
    metrics.totalRows, metrics.totalCount = nil, 0
    metrics.details, metrics.detailCount = {}, 0
    metrics.overrunBy, metrics.windowOverruns = {}, 0
    emit("runtime_hitch_summary", {
        windowS = math.floor(windowMs / 1000),
        count = count,
        hitches = table.concat(parts, " "),
    })
    return true
end

function Runtime.timeHook(name, callback, ...)
    local started = nowMs()
    local first, second = callback(...)
    Runtime.noteHitch(name, math.max(0, nowMs() - started))
    return first, second
end

function Runtime.slotDue(slot)
    return Runtime.metrics.ticks % 10 == slot
end

local function runBackground(name, callback, slot)
    if Runtime.metrics.ticks % 10 ~= slot then return 0 end
    return runSubsystem(name, callback)
end

function Runtime.configureTalk(adapters)
    adapters = type(adapters) == "table" and adapters or {}
    local talk = ProjectALife.Talk
    if talk ~= nil then
        talk.reset()
        talk.configure({ enabled = adapters.enabled ~= false })
    end
    local presence = ProjectALife.ModuleTalkPresence
    if presence ~= nil then
        presence.reset()
        presence.settings.enabled = adapters.enabled ~= false and adapters.presence ~= false
    end
    local speech = ProjectALife.Speech
    if speech ~= nil then speech.reset() end
    local robbery = ProjectALife.ModuleRobbery
    if robbery ~= nil then
        if type(robbery.reset) == "function" then robbery.reset() end
        if type(robbery.settings) == "table" then
            robbery.settings.enabled = adapters.robberyEnabled ~= false
            robbery.settings.chancePercent = tonumber(adapters.robberyChance) or 100
        end
    end
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.reset) == "function" then standoff.reset() end
    local orders = ProjectALife.TalkOrders
    if orders ~= nil then
        orders.reset()
        orders.configure({ enabled = adapters.ordersEnabled, chance = adapters.ordersChance,
            zombieTiles = adapters.ordersZombieTiles, fightPercent = adapters.ordersFightPercent,
            surrenderSeconds = adapters.ordersSurrenderSeconds })
    end
    local knowledge = ProjectALife.Knowledge
    if knowledge ~= nil and type(knowledge.reset) == "function" then knowledge.reset() end
    local rumors = ProjectALife.Rumors
    if rumors ~= nil and type(rumors.reset) == "function" then rumors.reset() end
    local party = ProjectALife.Party
    if party ~= nil and type(party.reset) == "function" then party.reset() end
    local chatter = ProjectALife.ChatterDirector
    if chatter ~= nil and type(chatter.reset) == "function" then chatter.reset() end
    local risk = ProjectALife.Risk
    if risk ~= nil and type(risk.settings) == "table" then
        if type(risk.reset) == "function" then risk.reset() end
        risk.settings.enabled = adapters.riskAssessment ~= false
    end
    local radio = ProjectALife.KnoxRadio
    if radio ~= nil and type(radio.settings) == "table" then
        radio.settings.enabled = adapters.radio ~= false
    end
    return true
end

function Runtime.carefulTick(now)
    local careful = ProjectALife.ModuleCareful
    if careful == nil or type(careful.serverTick) ~= "function" then return 0 end
    return careful.serverTick(now)
end

function Runtime.activityTick()
    local service = ProjectALife.ActivityService
    if service == nil or type(service.tick) ~= "function" then return 0 end
    return service.tick(nowMs())
end

function Runtime.tick()
    if not Runtime.started or not Runtime.enabled then return 0 end
    local now = nowMs()
    if now - Runtime.lastTickAtMs < Runtime.tickIntervalMs then return 0 end
    Runtime.lastTickAtMs = now

    local executor = ProjectALife.Executor
    local delegating = executor ~= nil and executor.serverDelegates() == true
    local faultsBefore = Runtime.metrics.faults or 0
    local spawnBudget = 1
    local actionBudget = math.max(2, math.min(24,
        math.ceil(#ProjectALife.ActionLedger.order / 5)))
    local shellBudget = math.max(2, math.min(24,
        math.ceil(#ProjectALife.Watchdog.order / 5)))

    local populationBudget = 5
    local decisionBudget = math.max(4, math.min(24,
        math.ceil(math.max(1, #Decisions.order) / 5)))

    local processed = runSubsystem("watchdog", function()
            return SpawnService.watchdogTick(actionBudget, shellBudget)
        end)
        + runSubsystem("spawn_settle", function()
            return SpawnService.settleTick(spawnBudget)
        end)
        + runSubsystem("server_shells", function()

            local dedicated = type(isServer) == "function" and isServer()
            local guard = ProjectALife.AIFence
            for index = 1, #Watchdog.order do
                local binding = Watchdog.bindings[Watchdog.order[index]]
                if binding then
                    ProjectALife.ShellSimulation.reconcileHealth(binding.shell)
                    if dedicated and ShellAdapter.shellAlive(binding.shell) then
                        guard.onZombieUpdate(binding.shell)
                    end
                end
            end
            return #Watchdog.order
        end)
        + runSubsystem("lifecycle", function() return Lifecycle.tick(8) end)
        + runBackground("director", Director.tick, 0)
        + runSubsystem("edge_parking", function()
            if type(isServer) == "function" and isServer() then return 0 end
            return Population.edgeSweep(now)
        end)
        + runSubsystem("population", function() return Population.tick(populationBudget) end)
        + (Runtime.slotDue(1) and runBackground("offline_director", function()
            return ProjectALife.OfflineDirector.tick()
        end, 1) or 0)
        + (Runtime.slotDue(2) and runBackground("outposts", function()
            return ProjectALife.OutpostDirector.tick()
        end, 2) or 0)
        + runSubsystem("movement", function()
            if delegating then return 0 end
            return ProjectALife.Movement.tick(4)
        end)
        + runSubsystem("animations", function()
            if delegating then return 0 end
            return Animations.tick(8)
        end)
        + runSubsystem("presentation_sync", function() return syncPresentation(now) end)
        + runSubsystem("executor_mirror", function()
            if not delegating then return 0 end
            return executor.serverTick(now)
        end)
        + runSubsystem("orphan_guard", function() return OrphanGuard.tick(16) end)
        + runSubsystem("entrance_claims", function()
            local entrances = ProjectALife.Entrances
            return entrances ~= nil and entrances.tick(now) or 0
        end)
        + (Runtime.slotDue(3) and runBackground("base_heat", function()
            return ProjectALife.BaseHeat.tick()
        end, 3) or 0)
        + (Runtime.slotDue(4) and runBackground("raid_director", function()
            return ProjectALife.RaidDirector.tick()
        end, 4) or 0)
        + (Runtime.slotDue(5) and runBackground("meta_director", function()
            return ProjectALife.MetaDirector.tick()
        end, 5) or 0)
        + (Runtime.slotDue(7) and runBackground("populate", function()
            local hours = 0
            pcall(function() hours = getGameTime():getWorldAgeHours() end)
            return ProjectALife.PopulateDirector.tick(now, hours)
        end, 7) or 0)
        + (Runtime.slotDue(9) and runBackground("town_welcome", function()
            local hours = 0
            pcall(function() hours = getGameTime():getWorldAgeHours() end)
            return ProjectALife.TownWelcome.tick(now, hours)
        end, 9) or 0)
        + runSubsystem("populate_scan", function()
            return ProjectALife.PopulateDirector.scanTick()
        end)
        + (Runtime.slotDue(6) and runBackground("encounter_director", function()
            local director = ProjectALife.EncounterDirector
            return director ~= nil and director.tick() or 0
        end, 6) or 0)
        + (Runtime.slotDue(8) and runBackground("resident_corpses", function()
            local corpses = ProjectALife.ResidentCorpses
            return corpses ~= nil and corpses.tick(now) or 0
        end, 8) or 0)
        + (Runtime.slotDue(0) and runBackground("safehouse", function()
            local safehouse = ProjectALife.SafehouseDirector
            return safehouse ~= nil and safehouse.tick() or 0
        end, 0) or 0)
        + (Runtime.slotDue(9) and runBackground("activities", Runtime.activityTick, 9) or 0)
        + runSubsystem("talk", function()
            return ProjectALife.Talk.tick(now)
        end)

        + runSubsystem("robbery", function()
            return ProjectALife.ModuleRobbery.tick(now)
        end)
        + runSubsystem("standoff", function()
            local standoff = ProjectALife.Standoff
            return standoff ~= nil and standoff.tick(now) or 0
        end)
        + runSubsystem("rumors", function()
            return ProjectALife.Rumors.tick(now)
        end)
        + runSubsystem("party", function()
            local party = ProjectALife.Party
            return party ~= nil and party.tick(now) or 0
        end)
        + runSubsystem("chatter", function()
            local chatter = ProjectALife.ChatterDirector
            return chatter ~= nil and chatter.tick(now) or 0
        end)

        + runSubsystem("threat_watch", function()
            local watch = ProjectALife.ThreatWatch
            return watch ~= nil and watch.tick(now) or 0
        end)
        + runSubsystem("careful", function()
            return Runtime.carefulTick(now)
        end)
        + runSubsystem("admin_queue", function()
            local service = ProjectALife.DebugService
            return service and type(service.tick) == "function" and service.tick(1) or 0
        end)
        + runSubsystem("decisions", function()
            if delegating then return 0 end
            return Decisions.tick(decisionBudget)
        end)
    local elapsed = math.max(0, nowMs() - now)
    Runtime.metrics.ticks = Runtime.metrics.ticks + 1
    Runtime.metrics.lastTickMs = elapsed
    Runtime.metrics.maximumTickMs = math.max(Runtime.metrics.maximumTickMs, elapsed)
    Runtime.noteTotal(elapsed)
    if elapsed > Runtime.tickIntervalMs then
        Runtime.metrics.overruns = (Runtime.metrics.overruns or 0) + 1
        local slowest, cost = Runtime.slowestSubsystem(now)
        Runtime.noteOverrun(slowest)
        if now - (Runtime.metrics.lastSlowReportAtMs or -10000) >= 10000 then
            Runtime.metrics.lastSlowReportAtMs = now
            emit("runtime_slow_tick", { elapsedMs = elapsed, subsystem = slowest, subsystemMs = cost })
        end
    end
    Runtime.reportHitches(now)
    if (Runtime.metrics.faults or 0) == faultsBefore then Runtime.lastError = nil end
    return processed
end

function Runtime.save()
    if not serverAuthority() then return false, "server_authority_required" end
    if not Runtime.started then return true, false end
    Lifecycle.tick(math.max(8, Lifecycle.pendingCount()))
    if Lifecycle.pendingCount() > 0 then
        Runtime.lastError = "death_persistence_pending:" .. tostring(Lifecycle.pendingCount())
        emit("save_park_failed", { error = Runtime.lastError })
        return false, Runtime.lastError
    end
    local parked, count, failed = SpawnService.parkForSave()
    local flushed, flushError = Runtime.flush(true)
    if not parked then
        Runtime.lastError = "save_park_failed:" .. tostring(failed)
        emit("save_park_failed", { actors = count, failed = failed, error = Runtime.lastError })
        return false, Runtime.lastError
    end
    return flushed, flushError
end

Runtime.checkpointBudget = 6

function Runtime.flush(full)
    if not Runtime.started then return true, false end
    Lifecycle.tick(math.max(8, Lifecycle.pendingCount()))
    if Lifecycle.pendingCount() > 0 then
        Runtime.lastError = "death_persistence_pending:" .. tostring(Lifecycle.pendingCount())
        emit("checkpoint_failed", { error = Runtime.lastError })
        return false, Runtime.lastError
    end
    local checkpointed, count, failed
    if full == true or (type(isServer) == "function" and isServer() == true) then
        checkpointed, count, failed = SpawnService.checkpointAll()
    else
        checkpointed, count, failed = SpawnService.checkpointAll(Runtime.checkpointBudget)
    end
    if not checkpointed then
        Runtime.lastError = "checkpoint_failed:" .. tostring(failed or count)
        emit("checkpoint_failed", { error = Runtime.lastError, failed = failed })
        return false, Runtime.lastError
    end
    emit("checkpoint_complete", { actors = count or 0 })
    pcall(ProjectALife.SquadLedger.flush)
    pcall(ProjectALife.OutpostRegistry.flush)
    pcall(Reputation.flush)
    pcall(ProjectALife.PersonalRep.flush)
    pcall(ProjectALife.Standing.flush)
    local service = ProjectALife.DebugService
    if type(service) == "table" and type(service.flushPeopleMet) == "function" then
        local called, saved = pcall(service.flushPeopleMet)
        if not called or saved ~= true then
            emit("people_met_checkpoint_deferred", { reason = tostring(saved) })
        end
    end
    return Persistence.flush()
end

function Runtime.stop()
    if not Runtime.started then return true end
    local flushed = Runtime.flush(true)
    Runtime.started = false
    emit("runtime_stopped", {})
    return flushed
end

return Runtime
