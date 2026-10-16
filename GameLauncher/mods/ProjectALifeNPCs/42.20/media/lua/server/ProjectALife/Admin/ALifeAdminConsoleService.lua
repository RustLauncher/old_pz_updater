require "ProjectALife/Admin/ALifeSpawnPlan"

ProjectALife = ProjectALife or {}

local Console = {
    commands = {
        adminSnapshot = "snapshot", adminSpawnPreview = "preview", adminSpawn = "spawn",
        adminSpawnUndo = "undo", adminSpawnLedger = "ledger", adminFactionIndex = "factionIndex",
        adminFactionMembers = "factionMembers", adminRepView = "repView", adminRepFaction = "repFaction",
        adminFunnel = "funnel", adminLog = "log",
    },
    kinds = { squad = true, member = true, roster = true, encounter = true, outpost = true,
        visitor = true, raid = true, support = true },
    batches = {}, order = {}, maximumBatches = 64,
    metrics = { requests = 0, accepted = 0, failed = 0, undone = 0, previews = 0, snapshots = 0,
        refused = 0, faults = 0 },
    pageRows = 40, nearest = 12, maxRelations = 60,
    funnel = { overridden = false, original = nil },
    logging = { aiTrace = true },
}
ProjectALife.AdminConsoleService = Console

function Console.reset()
    Console.batches, Console.order = {}, {}
    Console.capture = nil
    Console.logging = { aiTrace = true }
    Console.metrics = { requests = 0, accepted = 0, failed = 0, undone = 0, previews = 0, snapshots = 0,
        refused = 0, faults = 0 }
    if Console.funnel.overridden then Console.restoreFunnel() end
end

function Console.text(reason)
    local plan = ProjectALife.SpawnPlan
    if plan ~= nil and type(plan.refusalText) == "function" then return plan.refusalText(reason) end
    return tostring(reason)
end

function Console.refuse(Service, player, resultCommand, reason, extra)
    Console.metrics.refused = Console.metrics.refused + 1
    local payload = { ok = false, reason = reason, text = Console.text(reason) }
    for key, value in pairs(extra or {}) do payload[key] = value end
    Service.sendReply(player, resultCommand, payload)
    return false
end

function Console.tap(command, payload)
    local capture = Console.capture
    if capture == nil or type(payload) ~= "table" then return end
    if capture.commands[command] == true then capture.payload = payload end
end

function Console.nested(Service, player, command, args, replyName)
    Console.capture = { commands = { [replyName] = true }, payload = nil }
    local ok, handled = pcall(Service.handle, "ProjectALife", command, player, args)
    local payload = Console.capture.payload
    Console.capture = nil
    return ok and handled == true, payload, ok
end

function Console.remember(batch)
    if Console.batches[batch.requestId] == nil then
        Console.order[#Console.order + 1] = batch.requestId
    end
    Console.batches[batch.requestId] = batch
    while #Console.order > Console.maximumBatches do
        local dropped = table.remove(Console.order, 1)
        Console.batches[dropped] = nil
    end
    return batch
end

function Console.ownedBy(Service, player)
    local owner = Service.playerKeyOf(player)
    local rows = {}
    for _, requestId in ipairs(Console.order) do
        local batch = Console.batches[requestId]
        if batch ~= nil and batch.owner == owner then rows[#rows + 1] = batch end
    end
    return rows
end

function Console.cleanIds(list, limit)
    local ids = {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if type(id) == "string" and id ~= "" and #ids < limit then ids[#ids + 1] = string.sub(id, 1, 96) end
    end
    return ids
end

function Console.requestIdOf(args)
    if type(args.requestId) == "string" and args.requestId ~= "" then return string.sub(args.requestId, 1, 96) end
    return nil
end

function Console.cast(Service, args)
    local Catalog = ProjectALife.Catalog
    local kind = args.kind
    local ids = Console.cleanIds(args.profileIds, 8)
    local seed = tonumber(args.seed)
    local used = seed
    if kind == "member" then
        local profileId = type(args.profileId) == "string" and args.profileId or ids[1]
        if profileId == nil then return nil, "spawn_member_required" end
        if Catalog.npc(profileId) == nil then return nil, "spawn_member_unknown" end
        return { profileId }, nil, used
    end
    if kind == "roster" then
        if #ids == 0 then return nil, "spawn_roster_empty" end
        for _, id in ipairs(ids) do
            if Catalog.npc(id) == nil then return nil, "spawn_member_unknown" end
        end
        return ids, nil, used
    end
    if #ids > 0 then
        for _, id in ipairs(ids) do
            if Catalog.npc(id) == nil then return nil, "spawn_member_unknown" end
        end
        return ids, nil, used
    end
    local factionId = type(args.factionId) == "string" and args.factionId or nil
    if kind == "squad" and factionId == nil then return nil, "spawn_faction_required" end
    if factionId ~= nil and Catalog.faction(factionId) == nil then return nil, "faction_unknown" end
    if used == nil then used = math.floor(Service.clockMs() / 1000) end
    local count = math.max(1, math.min(8, math.floor(tonumber(args.count) or 1)))
    local picked, why = Service.hostileProfileIds(count, used, factionId, true)
    if picked == nil then return nil, why or "no_hostile_profiles" end
    return picked, nil, used
end

function Console.gate(Service, args)
    if args.respectGates ~= true then return true end
    local refused = Service.outOfSeason(args)
    if refused == nil then refused = Service.censusGate(args) end
    if refused ~= nil then return false, refused end
    return true
end

function Console.rosterRows(ids)
    local Catalog = ProjectALife.Catalog
    local rows = {}
    for _, id in ipairs(ids) do
        local profile = Catalog.npc(id)
        if profile ~= nil then
            local general = type(profile.general) == "table" and profile.general or {}
            local weapons = type(profile.weapons) == "table" and profile.weapons or {}
            local faction = Catalog.faction(general.faction)
            rows[#rows + 1] = {
                id = id, name = tostring(general.name or id), factionId = general.faction,
                factionName = faction ~= nil and faction.general ~= nil and faction.general.name or general.faction,
                role = general.primaryBehavior, primary = weapons.primary, secondary = weapons.secondary,
                melee = weapons.melee, female = general.female == true,
                weight = tonumber(general.spawnWeight) or 1,
            }
        end
    end
    return rows
end

function Console.routedArguments(args, ids)
    local routed = {}
    for key, value in pairs(args) do routed[key] = value end
    routed.kind, routed.preview, routed.respectGates, routed.seed = nil, nil, nil, nil
    if ids ~= nil then
        if args.kind == "member" then
            routed.profileId, routed.profileIds = ids[1], nil
        else
            routed.profileId, routed.profileIds = nil, ids
        end
    end
    if args.dormant == true then routed.dormant = true end
    return routed
end

function Console.finishBatch(batch, outcome)
    batch.state = outcome.ok == true and "settled" or (tonumber(outcome.active) or 0) > 0 and "partial" or "failed"
    batch.uids = type(outcome.actorUids) == "table" and outcome.actorUids or {}
    batch.active = tonumber(outcome.active) or 0
    batch.groupId = outcome.groupId or batch.groupId
    local undo = nil
    if batch.undoRequested == true then
        local removed, failed, scenes, sites = Console.purgeBatch(batch.Service, batch, batch.player)
        undo = { ok = failed == 0, requestId = batch.requestId, removed = removed, failed = failed,
            scenes = scenes, sites = sites, batches = 1 }
    end
    Console.sendBatch(batch, outcome)
    if undo ~= nil and batch.Service ~= nil then batch.Service.sendReply(batch.player, "adminSpawnUndoResult", undo) end
end

function Console.sendBatch(batch, outcome)
    local Service = batch.Service
    if Service == nil then return end
    Service.sendReply(batch.player, "adminSpawnBatchResult", {
        ok = outcome.ok == true, requestId = batch.requestId, groupId = batch.groupId,
        actorUids = batch.uids, active = batch.active, failed = tonumber(outcome.failed) or 0,
        rejected = tonumber(outcome.rejected) or 0, reason = outcome.reason, reasons = outcome.reasons,
        rolledBack = outcome.rolledBack == true, kind = batch.kind,
    })
end

function Console.watch(Service, player, batch)
    batch.Service, batch.player = Service, player
    local watched = Service.watchGroup(batch.requestId, function(outcome)
        Console.finishBatch(batch, outcome)
    end)
    return watched
end

function Console.spawn(Service, player, args)
    local metrics = Console.metrics
    metrics.requests = metrics.requests + 1
    local resultCommand = "adminSpawnResult"
    local kind = args.kind
    local requestId = Console.requestIdOf(args)
    if Console.kinds[kind] ~= true then
        return Console.refuse(Service, player, resultCommand, "spawn_kind_invalid", { requestId = requestId, kind = kind })
    end
    if requestId == nil then
        Service.sequence = Service.sequence + 1
        requestId = "admin-spawn:" .. tostring(math.floor(Service.clockMs())) .. ":" .. tostring(Service.sequence)
    end
    local base = { requestId = requestId, kind = kind }
    local opened, gateWhy = Console.gate(Service, args)
    if not opened then
        metrics.failed = metrics.failed + 1
        return Console.refuse(Service, player, resultCommand, gateWhy, base)
    end
    local batch = { requestId = requestId, kind = kind, owner = Service.playerKeyOf(player),
        atMs = Service.clockMs(), state = "pending", uids = {}, summary = string.sub(tostring(args.summary or ""), 1, 120) }
    local payload, handled
    if kind == "squad" or kind == "member" or kind == "roster" then
        local ids, why, used = Console.cast(Service, args)
        if ids == nil then
            metrics.failed = metrics.failed + 1
            return Console.refuse(Service, player, resultCommand, why, base)
        end
        base.seed = used
        base.roster = Console.rosterRows(ids)
        payload = Service.rawSpawn(player, Console.routedArguments(args, ids), true)
        handled = type(payload) == "table" and payload.ok == true
    elseif kind == "encounter" or kind == "raid" then
        local routed = Console.routedArguments(args, nil)
        if kind == "raid" then routed.encounterId = "fullscale_raid" end
        handled, payload = Console.nested(Service, player, "debugSpawnCatalog", routed, "debugSpawnResult")
        if payload == nil then payload = { ok = handled, reason = handled and "accepted_pending" or "spawn_refused" } end
    elseif kind == "outpost" then
        local routed = Console.routedArguments(args, nil)
        routed.presetId = args.presetId
        handled, payload = Console.nested(Service, player, "debugBuildOutpost", routed, "debugBuildOutpostResult")
        if payload == nil then payload = { ok = handled, reason = handled and "accepted_pending" or "spawn_refused" } end
        payload.siteId = payload.site
    elseif kind == "visitor" then
        local at = type(args.at) == "table" and args.at or nil
        handled, payload = Console.nested(Service, player, "debugSafehouse",
            { action = "trigger", event = args.event, at = at }, "debugSafehouseResult")
        if payload == nil then payload = { ok = handled, reason = handled and "visit_started" or "spawn_refused" } end
    else
        handled, payload = Console.nested(Service, player, "debugForceSupport", {}, "debugForceSupportResult")
        if payload == nil then payload = { ok = handled, reason = handled and "support_called" or "spawn_refused" } end
    end
    local ok = type(payload) == "table" and payload.ok == true
    local accepted = tonumber(payload.accepted) or 0
    local failed = tonumber(payload.failed) or 0
    if ok and accepted == 0 and (kind == "squad" or kind == "member" or kind == "roster") then ok = false end
    local result = {
        ok = ok, requestId = requestId, kind = kind, accepted = accepted, failed = failed,
        reason = payload.reason, text = (not ok) and (payload.text or Console.text(payload.reason)) or nil,
        groupId = payload.groupId, origin = payload.origin, mode = payload.mode, scene = payload.scene,
        siteId = payload.siteId, raidId = payload.raidId, say = payload.say, seed = base.seed,
        roster = base.roster, dormant = args.dormant == true or nil,
    }
    if ok then
        metrics.accepted = metrics.accepted + math.max(accepted, 1)
        batch.groupId = payload.groupId
        batch.siteId = payload.siteId
        batch.dormant = args.dormant == true
        local group = Service.groups[requestId]
        if group ~= nil then
            batch.sceneKey = group.sceneKey
            batch.sceneCreated = group.sceneCreated == true
        end
        Console.remember(batch)
        result.sceneKey = batch.sceneKey
        if payload.groupId ~= nil then
            Console.watch(Service, player, batch)
        else
            batch.state = "settled"
        end
    else
        metrics.failed = metrics.failed + math.max(failed, 1)
    end
    Service.sendReply(player, resultCommand, result)
    return ok
end

function Console.removeActors(Service, uids, groupId, siteId)
    local Registry = ProjectALife.ActorRegistry
    local wanted = {}
    for _, uid in ipairs(uids or {}) do wanted[uid] = true end
    local removed, failed = 0, 0
    for _, actor in ipairs(Registry.list()) do
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local mine = wanted[actor.uid] == true
        if not mine and groupId ~= nil and memory.groupId == groupId then mine = true end
        if not mine and siteId ~= nil and tostring(memory.outpostId or "") == siteId then mine = true end
        if mine then
            if Service.purgeActor(actor, "admin_spawn_undo") then removed = removed + 1 else failed = failed + 1 end
        end
    end
    return removed, failed
end

function Console.removeSite(siteId)
    local registry = ProjectALife.OutpostRegistry
    if registry == nil or siteId == nil then return false end
    local site = type(registry.read) == "function" and registry.read(siteId) or nil
    if site == nil or site.state == "expired" then return false end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return registry.expire(site.id, site.revision, hours, "admin_spawn_undo") ~= nil
end

function Console.purgeBatch(Service, batch, player)
    local removed, failed = Console.removeActors(Service, batch.uids, batch.groupId, batch.siteId)
    local scenes, sites = 0, 0
    if batch.sceneKey ~= nil and batch.sceneCreated == true then
        local kit = ProjectALife.SceneKit
        if kit ~= nil and type(kit.remove) == "function" then
            local okScene, done = pcall(kit.remove, batch.sceneKey)
            if okScene and done == true then scenes = 1 end
        end
    end
    if batch.siteId ~= nil and Console.removeSite(batch.siteId) then sites = 1 end
    batch.undone, batch.undoRequested, batch.state = true, nil, "undone"
    Console.metrics.undone = Console.metrics.undone + removed
    return removed, failed, scenes, sites
end

function Console.undoOne(Service, player, batch)
    if batch.undone == true then return { removed = 0, failed = 0, reason = "undo_nothing" } end
    if batch.state == "pending" and Service.groups[batch.requestId] ~= nil then
        batch.undoRequested = true
        return { removed = 0, failed = 0, pending = true, reason = "undo_pending" }
    end
    local removed, failed, scenes, sites = Console.purgeBatch(Service, batch, player)
    return { removed = removed, failed = failed, scenes = scenes, sites = sites }
end

function Console.undo(Service, player, args)
    local resultCommand = "adminSpawnUndoResult"
    local total = { removed = 0, failed = 0, scenes = 0, sites = 0, pending = 0, batches = 0 }
    local requestId = Console.requestIdOf(args)
    local list = {}
    if args.all == true then
        list = Console.ownedBy(Service, player)
    elseif requestId ~= nil and Console.batches[requestId] ~= nil then
        list = { Console.batches[requestId] }
    elseif type(args.groupId) == "string" or type(args.siteId) == "string" then
        local ad = { requestId = requestId or ("undo:" .. tostring(args.groupId or args.siteId)),
            kind = "adhoc", owner = Service.playerKeyOf(player), state = "settled", uids = Console.cleanIds(args.actorUids, 64),
            groupId = type(args.groupId) == "string" and string.sub(args.groupId, 1, 96) or nil,
            siteId = type(args.siteId) == "string" and string.sub(args.siteId, 1, 96) or nil,
            sceneKey = type(args.sceneKey) == "string" and string.sub(args.sceneKey, 1, 160) or nil,
            sceneCreated = type(args.sceneKey) == "string" }
        list = { ad }
    end
    if #list == 0 then
        return Console.refuse(Service, player, resultCommand, "undo_unknown_batch", { requestId = requestId })
    end
    for _, batch in ipairs(list) do
        local one = Console.undoOne(Service, player, batch)
        total.removed = total.removed + one.removed
        total.failed = total.failed + one.failed
        total.scenes = total.scenes + (one.scenes or 0)
        total.sites = total.sites + (one.sites or 0)
        if one.pending then total.pending = total.pending + 1 end
        total.batches = total.batches + 1
    end
    local ok = total.failed == 0 and (total.removed > 0 or total.scenes > 0 or total.sites > 0 or total.pending > 0)
    local reason = nil
    if total.failed > 0 then reason = "undo_failed"
    elseif not ok then reason = "undo_nothing"
    elseif total.pending > 0 and total.removed == 0 then reason = "undo_pending" end
    Service.sendReply(player, resultCommand, {
        ok = ok, requestId = args.all == true and "*" or requestId, removed = total.removed,
        failed = total.failed, scenes = total.scenes, sites = total.sites, pending = total.pending,
        batches = total.batches, reason = reason, text = reason ~= nil and Console.text(reason) or nil,
    })
    return ok
end

function Console.ledger(Service, player, args)
    local rows = {}
    for _, batch in ipairs(Console.ownedBy(Service, player)) do
        rows[#rows + 1] = { requestId = batch.requestId, kind = batch.kind, state = batch.state,
            groupId = batch.groupId, siteId = batch.siteId, sceneKey = batch.sceneKey,
            active = batch.active, count = #batch.uids, undone = batch.undone == true, atMs = batch.atMs }
    end
    Service.sendReply(player, "adminSpawnLedgerResult", { ok = true, batches = rows })
    return true
end

function Console.preview(Service, player, args)
    local metrics = Console.metrics
    metrics.previews = metrics.previews + 1
    local resultCommand = "adminSpawnPreviewResult"
    local kind = args.kind
    local requestId = Console.requestIdOf(args)
    local base = { requestId = requestId, kind = kind }
    if Console.kinds[kind] ~= true then
        return Console.refuse(Service, player, resultCommand, "spawn_kind_invalid", base)
    end
    local reply = { ok = true, requestId = requestId, kind = kind, notes = {}, roster = {} }
    local opened, gateWhy = Console.gate(Service, args)
    reply.gate = { ok = opened, reason = gateWhy, text = gateWhy ~= nil and Console.text(gateWhy) or nil }
    if kind == "squad" or kind == "member" or kind == "roster" then
        local ids, why, used = Console.cast(Service, args)
        if ids == nil then return Console.refuse(Service, player, resultCommand, why, base) end
        reply.seed = used
        reply.roster = Console.rosterRows(ids)
        reply.expected = #ids
        if kind == "member" then reply.expected = math.max(1, math.min(8, math.floor(tonumber(args.count) or 1))) end
    elseif kind == "encounter" then
        local definition = Service.encounterDefinitionOf(args.encounterId)
        if definition == nil then return Console.refuse(Service, player, resultCommand, "unknown_encounter", base) end
        reply.notes[#reply.notes + 1] = tostring(definition.label or definition.id) .. ": "
            .. tostring(definition.summary or "no summary")
        reply.expected = tonumber(args.count) and tonumber(args.count) > 0 and tonumber(args.count)
            or math.floor(((definition.minCount or 2) + (definition.maxCount or 4)) / 2)
        reply.notes[#reply.notes + 1] = "The encounter casts its own squad; seed does not apply."
        local ids = Service.hostileProfileIds(reply.expected, math.floor(Service.clockMs() / 1000),
            args.factionId, true)
        if ids ~= nil then reply.roster = Console.rosterRows(ids) end
    elseif kind == "outpost" then
        local presets = ProjectALife.OutpostPresets
        local preset = presets ~= nil and presets.get(args.presetId) or nil
        if preset == nil then return Console.refuse(Service, player, resultCommand, "preset_unknown", base) end
        reply.notes[#reply.notes + 1] = tostring(preset.label or preset.id) .. " (" .. tostring(preset.class) .. ")"
        if preset.class == "building" then
            reply.notes[#reply.notes + 1] = "Needs a building at the spot. Right-click one to target it."
        end
    elseif kind == "visitor" then
        reply.notes[#reply.notes + 1] = "Uses the safehouse director. It creates a test base at the spot when you have none."
    elseif kind == "raid" then
        local raid = ProjectALife.RaidDirector
        if raid ~= nil and raid.state ~= nil then
            reply.gate = { ok = false, reason = "raid_active", text = Console.text("raid_active") }
        end
        reply.expected = tonumber(args.count)
    else
        reply.notes[#reply.notes + 1] = "The NPC nearest to you places the call."
    end
    if args.dormant == true then
        reply.notes[#reply.notes + 1] = "Dormant: the squad exists as a marker and gets bodies when a player comes near."
    end
    if kind == "squad" or kind == "member" or kind == "roster" or kind == "encounter" then
        reply.placement = Console.checkSquare(Service, player, args, kind)
    end
    reply.ok = true
    Service.sendReply(player, resultCommand, reply)
    return true
end

function Console.checkSquare(Service, player, args, kind)
    local SpawnPolicy = ProjectALife.SpawnPolicy
    if tostring(args.placementMode or "here") == "rule" then
        return { ok = true, reason = "placed_by_rule", text = "Placed by the encounter's own rule when you spawn." }
    end
    local origin, _, why = Service.requestedOriginOf(player, args)
    if origin == nil then return { ok = false, reason = why, text = Console.text(why) } end
    if args.dormant == true then
        return { ok = true, x = origin.x, y = origin.y, z = origin.z,
            text = "Dormant squads skip the square check; bodies are placed when they hydrate." }
    end
    local separation = math.max(1, math.min(8, math.floor(tonumber(args.separation) or 2)))
    local options = { allowProtected = args.mode == "guard", adminPlaced = true,
        searchRadius = math.max(8, separation * 2), playerKeepOut = 0, fairness = false }
    local requested = { x = origin.x + 0.5, y = origin.y + 0.5, z = origin.z }
    local ok, position, reason = pcall(SpawnPolicy.find, requested, options)
    if not ok then return { ok = false, reason = "spawn_square_unavailable", text = Console.text("spawn_square_unavailable") } end
    if position == nil then
        reason = reason or "spawn_square_unavailable"
        return { ok = false, reason = reason, text = Console.text(reason), x = origin.x, y = origin.y, z = origin.z }
    end
    return { ok = true, x = math.floor(position.x), y = math.floor(position.y), z = math.floor(position.z) }
end

function Console.factionRow(faction, day)
    local Funnel = ProjectALife.Funnel
    local custom = ProjectALife.CustomFactions
    local rules = ProjectALife.FactionSpawnRules
    local spawn = type(faction.spawn) == "table" and faction.spawn or {}
    local general = type(faction.general) == "table" and faction.general or {}
    local relations = type(faction.relations) == "table" and faction.relations or {}
    local open = nil
    if rules ~= nil and type(rules.inSeason) == "function" and day ~= nil then
        local done, value = pcall(rules.inSeason, faction, day)
        if done then open = value == true end
    end
    return {
        id = faction.id, name = tostring(general.name or faction.id), category = general.category,
        program = spawn.program, peaceable = spawn.peaceable == true, relation = relations.player,
        class = Funnel ~= nil and type(Funnel.classOf) == "function" and Funnel.classOf(faction.id) or nil,
        custom = custom ~= nil and type(custom.factions) == "table" and custom.factions[faction.id] ~= nil or false,
        open = open,
    }
end

function Console.today()
    local day
    pcall(function() day = getGameTime():getWorldAgeHours() / 24 end)
    return day
end

function Console.factionIndex(Service, player, args)
    local current = ProjectALife.Catalog.current or ProjectALife.Catalog.load()
    if current == nil then
        return Console.refuse(Service, player, "adminFactionIndexResult", "catalog_unavailable", {})
    end
    local counts = {}
    for _, profile in ipairs(current.npcOrder or {}) do
        local id = profile.general ~= nil and profile.general.faction or nil
        if id ~= nil then counts[id] = (counts[id] or 0) + 1 end
    end
    local rows, day = {}, Console.today()
    for _, faction in ipairs(current.factionOrder or {}) do
        if counts[faction.id] ~= nil then
            local row = Console.factionRow(faction, day)
            row.count = counts[faction.id]
            rows[#rows + 1] = row
        end
    end
    local pages = Service.catalogPages(rows, Console.pageRows, Service.catalogPageBytes)
    for index = 1, #pages do
        Service.sendReply(player, "adminFactionIndexResult", { ok = true, part = index, parts = #pages,
            factions = pages[index], total = #rows })
    end
    return true
end

function Console.factionMembers(Service, player, args)
    local factionId = type(args.factionId) == "string" and args.factionId or nil
    local current = ProjectALife.Catalog.current or ProjectALife.Catalog.load()
    if current == nil then
        return Console.refuse(Service, player, "adminFactionMembersResult", "catalog_unavailable", { factionId = factionId })
    end
    if factionId == nil or ProjectALife.Catalog.faction(factionId) == nil then
        return Console.refuse(Service, player, "adminFactionMembersResult", "faction_unknown", { factionId = factionId })
    end
    local ids = {}
    for _, profile in ipairs(current.npcOrder or {}) do
        if profile.general ~= nil and profile.general.faction == factionId then ids[#ids + 1] = profile.id end
    end
    local rows = Console.rosterRows(ids)
    local pages = Service.catalogPages(rows, Console.pageRows, Service.catalogPageBytes)
    for index = 1, #pages do
        Service.sendReply(player, "adminFactionMembersResult", { ok = true, factionId = factionId,
            part = index, parts = #pages, members = pages[index], total = #rows })
    end
    return true
end

function Console.funnelState()
    local Funnel = ProjectALife.Funnel
    if Funnel == nil then return nil end
    local day = Funnel.day()
    local stage = Funnel.stageAt(day)
    local row = Funnel.stages[stage + 1]
    return { enabled = Funnel.enabled(), day = math.floor(day), stage = stage,
        name = row ~= nil and row.name or nil, offset = Funnel.dayOffset(),
        overridden = Console.funnel.overridden == true, today = math.floor(Funnel.today()) }
end

function Console.restoreFunnel()
    local settings = ProjectALife.Settings
    if type(settings) == "table" and type(settings.current) == "table" then
        settings.current.funnelDayOffset = Console.funnel.original
    end
    Console.funnel.overridden, Console.funnel.original = false, nil
end

function Console.funnelCommand(Service, player, args)
    local resultCommand = "adminFunnelResult"
    local Funnel = ProjectALife.Funnel
    local settings = ProjectALife.Settings
    if Funnel == nil or type(settings) ~= "table" or type(settings.current) ~= "table" then
        return Console.refuse(Service, player, resultCommand, "funnel_unavailable", {})
    end
    if args.reset == true then
        if Console.funnel.overridden then Console.restoreFunnel() end
    else
        local stage = tonumber(args.stage)
        local offset = tonumber(args.offset)
        if stage ~= nil then
            stage = math.floor(stage)
            local row = Funnel.stages[stage + 1]
            if row == nil then
                return Console.refuse(Service, player, resultCommand, "funnel_stage_invalid", {})
            end
            offset = math.ceil(row.from - Funnel.today())
        end
        if offset == nil then
            return Console.refuse(Service, player, resultCommand, "funnel_stage_invalid", {})
        end
        offset = math.max(-Funnel.offsetLimit, math.min(Funnel.offsetLimit, math.floor(offset)))
        if not Console.funnel.overridden then
            Console.funnel.original = settings.current.funnelDayOffset
            Console.funnel.overridden = true
        end
        settings.current.funnelDayOffset = offset
    end
    local state = Console.funnelState()
    state.ok = true
    if not state.enabled then state.note = "Funnel_Enabled is off: the preview has no effect until it is switched on." end
    Service.sendReply(player, resultCommand, state)
    return true
end

function Console.repView(Service, player, args)
    local resultCommand = "adminRepViewResult"
    local reputation = ProjectALife.Reputation
    if reputation == nil or type(reputation.snapshotFor) ~= "function" then
        return Console.refuse(Service, player, resultCommand, "reputation_unavailable", {})
    end
    local snapshot, why = reputation.snapshotFor(player)
    if snapshot == nil then return Console.refuse(Service, player, resultCommand, why or "reputation_unavailable", {}) end
    local relations = {}
    for _, row in ipairs(snapshot.relations or {}) do
        if #relations < Console.maxRelations then relations[#relations + 1] = row end
    end
    Service.sendReply(player, resultCommand, { ok = true, playerKey = snapshot.playerKey,
        profession = snapshot.profession, personal = snapshot.personal, relations = relations })
    return true
end

function Console.repFaction(Service, player, args)
    local resultCommand = "adminRepFactionResult"
    local reputation = ProjectALife.Reputation
    local factionId = type(args.factionId) == "string" and args.factionId or nil
    if reputation == nil or type(reputation.snapshotFor) ~= "function" then
        return Console.refuse(Service, player, resultCommand, "reputation_unavailable", {})
    end
    if factionId == nil or ProjectALife.Catalog.faction(factionId) == nil then
        return Console.refuse(Service, player, resultCommand, "faction_unknown", { factionId = factionId })
    end
    local key = reputation.playerKey(player)
    reputation.snapshotFor(player)
    local state = reputation.storage
    if key == nil or type(state) ~= "table" or type(state.players) ~= "table" then
        return Console.refuse(Service, player, resultCommand, "reputation_unavailable", {})
    end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    local playerState = state.players[key]
    if type(playerState) ~= "table" then
        playerState = {}
        state.players[key] = playerState
    end
    if args.status == "hostile" then
        playerState[factionId] = { status = "hostile", cause = "admin", atHours = hours }
    else
        playerState[factionId] = nil
    end
    reputation.dirty = true
    if type(reputation.sync) == "function" then pcall(reputation.sync, player) end
    Service.sendReply(player, resultCommand, { ok = true, factionId = factionId,
        status = args.status == "hostile" and "hostile" or "baseline" })
    return true
end

function Console.population(Service, player)
    local Registry, Watchdog, Funnel = ProjectALife.ActorRegistry, ProjectALife.Watchdog, ProjectALife.Funnel
    local lifecycle = { active = 0, spawning = 0, dormant = 0, dead = 0 }
    local byFaction, byClass, byState = {}, {}, { active = 0, dormant = 0 }
    local squads, soloCount, total = {}, 0, 0
    local at = Service.playerAt(player)
    local now = Service.clockMs()
    local holds, holdCount = {}, 0
    local nearest = {}
    Registry.each(function(actor)
        total = total + 1
        lifecycle[actor.lifecycle] = (lifecycle[actor.lifecycle] or 0) + 1
        if actor.lifecycle == "dead" then return false end
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local key = tostring(memory.groupId or memory.squadId or ("solo:" .. tostring(actor.uid)))
        local squad = squads[key]
        if squad == nil then
            squad = { size = 0, active = false, factionId = actor.factionId }
            squads[key] = squad
            if string.sub(key, 1, 5) == "solo:" then soloCount = soloCount + 1 end
        end
        squad.size = squad.size + 1
        if actor.lifecycle == "active" then squad.active = true end
        if actor.lifecycle == "dormant" and holdCount < 200 then
            local wait = Service.bodyWait(actor, at, now)
            if wait ~= nil then
                holds[wait.reason] = (holds[wait.reason] or 0) + 1
                holdCount = holdCount + 1
            end
        end
        if at ~= nil and actor.worldPosition ~= nil then
            local dx, dy = actor.worldPosition.x - at.x, actor.worldPosition.y - at.y
            nearest[#nearest + 1] = { distance = math.sqrt(dx * dx + dy * dy), actor = actor }
        end
        return false
    end)
    local squadCount = 0
    for _, squad in pairs(squads) do
        squadCount = squadCount + 1
        local state = squad.active and "active" or "dormant"
        byState[state] = byState[state] + 1
        byFaction[squad.factionId or "?"] = (byFaction[squad.factionId or "?"] or 0) + 1
        local class = Funnel ~= nil and Funnel.classOf(squad.factionId) or nil
        class = class or "unclassed"
        byClass[class] = (byClass[class] or 0) + 1
    end
    table.sort(nearest, function(left, right) return left.distance < right.distance end)
    local near = {}
    for index = 1, math.min(Console.nearest, #nearest) do
        local entry = nearest[index]
        local actor = entry.actor
        local profile = ProjectALife.Catalog.npc(actor.profileId)
        near[#near + 1] = { uid = actor.uid, name = profile ~= nil and profile.general ~= nil and profile.general.name or actor.profileId,
            factionId = actor.factionId, lifecycle = actor.lifecycle, activity = actor.activity,
            distance = math.floor(entry.distance), x = math.floor(actor.worldPosition.x), y = math.floor(actor.worldPosition.y) }
    end
    local counters = {}
    local population = ProjectALife.Population
    for key, value in pairs(population ~= nil and type(population.metrics) == "table" and population.metrics or {}) do
        if type(value) == "number" and #counters < 60 then counters[#counters + 1] = { key, value } end
    end
    table.sort(counters, function(left, right) return left[1] < right[1] end)
    local factions = {}
    for id, count in pairs(byFaction) do factions[#factions + 1] = { id = id, squads = count } end
    table.sort(factions, function(left, right)
        if left.squads ~= right.squads then return left.squads > right.squads end
        return left.id < right.id
    end)
    while #factions > 14 do table.remove(factions) end
    local shells = 0
    if Watchdog ~= nil and type(Watchdog.bindings) == "table" then
        for _ in pairs(Watchdog.bindings) do shells = shells + 1 end
    end
    return { total = total, lifecycle = lifecycle, shells = shells, squads = squadCount, solo = soloCount,
        byState = byState, byClass = byClass, byFaction = factions, holds = holds, holdCount = holdCount,
        counters = counters, nearest = near, funnel = Console.funnelState() }
end

function Console.world(Service, player)
    local result = { day = Console.today() }
    if result.day ~= nil then result.day = math.floor(result.day) end
    pcall(function() result.hour = math.floor(getGameTime():getTimeOfDay() * 10) / 10 end)
    pcall(function()
        local time = getGameTime()
        if type(time.getMonth) == "function" and type(time.getDay) == "function" then
            result.date = { month = time:getMonth() + 1, day = time:getDay() + 1 }
        end
    end)
    if type(getClimateManager) == "function" then
        pcall(function()
            local climate = getClimateManager()
            if climate == nil then return end
            local weather = {}
            if type(climate.getTemperature) == "function" then weather.temperature = math.floor(climate:getTemperature() * 10) / 10 end
            if type(climate.isRaining) == "function" then weather.raining = climate:isRaining() == true end
            if type(climate.getRainIntensity) == "function" then weather.rain = math.floor(climate:getRainIntensity() * 100) / 100 end
            if type(climate.getDayLightStrength) == "function" then weather.daylight = math.floor(climate:getDayLightStrength() * 100) / 100 end
            result.weather = weather
        end)
    end
    local raid = ProjectALife.RaidDirector
    if raid ~= nil then
        local state = raid.state
        result.raid = { active = state ~= nil, raidId = state and state.raidId or nil,
            wave = state and state.waveNumber or nil, wavesTotal = state and state.wavesTotal or nil,
            factionId = state and state.factionId or nil }
    end
    local meta = ProjectALife.MetaDirector
    if meta ~= nil then result.meta = { pending = meta.pending ~= nil, events = meta.metrics and meta.metrics.events or 0 } end
    local director = ProjectALife.OutpostDirector
    if director ~= nil and type(director.metrics) == "table" then
        local m = director.metrics
        local reasons = {}
        for reason, count in pairs(type(m.garrisonDeferred) == "table" and m.garrisonDeferred or {}) do
            if #reasons < 8 then reasons[#reasons + 1] = { reason, count } end
        end
        table.sort(reasons, function(left, right) return left[2] > right[2] end)
        result.outposts = { rolls = m.rolls, proposed = m.proposed, built = m.built, garrisoned = m.garrisoned,
            expired = m.expired, refused = m.refused, deferred = reasons, sites = {} }
        local registry = ProjectALife.OutpostRegistry
        if registry ~= nil and type(registry.list) == "function" then
            for _, site in ipairs(registry.list()) do
                if site.state ~= "expired" and #result.outposts.sites < 12 then
                    result.outposts.sites[#result.outposts.sites + 1] = { id = site.id, preset = site.presetId,
                        state = site.state, x = site.x, y = site.y, factionId = site.factionId }
                end
            end
        end
    end
    result.funnel = Console.funnelState()
    return result
end

function Console.diagnostics(Service, player)
    local result = { modules = {} }
    local registry = ProjectALife.ModuleRegistry
    if registry ~= nil and type(registry.modules) == "table" then
        for id, module in pairs(registry.modules) do
            result.modules[#result.modules + 1] = { id = id, kind = module.kind,
                enabled = registry.isEnabled(id) == true, primary = module.primary == true }
        end
        table.sort(result.modules, function(left, right) return left.id < right.id end)
        result.lastError = registry.lastError
    end
    local runtime = ProjectALife.Runtime
    local m = runtime ~= nil and type(runtime.metrics) == "table" and runtime.metrics or {}
    result.runtime = { ticks = m.ticks, overruns = m.overruns, worstTickMs = m.maximumTickMs,
        lastTickMs = m.lastTickMs, faults = m.faults, lastFault = m.lastFault }
    local timings = {}
    for name, timing in pairs(type(m.subsystems) == "table" and m.subsystems or {}) do
        timings[#timings + 1] = { name = name, lastMs = timing.lastMs, maxMs = timing.maximumMs,
            avgMs = math.floor(timing.totalMs / math.max(1, timing.calls) * 100) / 100, calls = timing.calls }
    end
    table.sort(timings, function(left, right) return (left.maxMs or 0) > (right.maxMs or 0) end)
    while #timings > 14 do table.remove(timings) end
    result.timings = timings
    local telemetry = ProjectALife.Telemetry
    local errors = {}
    if telemetry ~= nil and type(telemetry.events) == "table" then
        for index = #telemetry.events, 1, -1 do
            local event = telemetry.events[index]
            if event.error ~= nil or string.find(tostring(event.category), "fault", 1, true) ~= nil
                    or string.find(tostring(event.category), "failed", 1, true) ~= nil then
                errors[#errors + 1] = { category = event.category, error = event.error, atMs = event.atMs, uid = event.uid }
                if #errors >= 10 then break end
            end
        end
    end
    result.errors = errors
    local box = ProjectALife.BlackBox
    result.recorder = box ~= nil and box.enabled == true
    result.adminSpawn = Console.qaFields()
    result.aiTrace = Console.logging.aiTrace
    return result
end

function Console.snapshot(Service, player, args)
    Console.metrics.snapshots = Console.metrics.snapshots + 1
    local sections = tostring(args.sections or "population")
    local payload = { ok = true, sections = sections, atMs = Service.clockMs() }
    if string.find(sections, "population", 1, true) ~= nil then payload.population = Console.population(Service, player) end
    if string.find(sections, "world", 1, true) ~= nil then payload.world = Console.world(Service, player) end
    if string.find(sections, "diagnostics", 1, true) ~= nil then payload.diagnostics = Console.diagnostics(Service, player) end
    local runtime = ProjectALife.Runtime
    payload.build = runtime ~= nil and runtime.BUILD or nil
    Service.sendReply(player, "adminSnapshotResult", payload)
    return true
end

function Console.logCommand(Service, player, args)
    if type(args.aiTrace) == "boolean" then Console.logging.aiTrace = args.aiTrace end
    Service.sendReply(player, "adminLogResult", { ok = true, aiTrace = Console.logging.aiTrace })
    return true
end

Console.handlers = {
    snapshot = Console.snapshot, preview = Console.preview, spawn = Console.spawn, undo = Console.undo,
    ledger = Console.ledger, factionIndex = Console.factionIndex, factionMembers = Console.factionMembers,
    repView = Console.repView, repFaction = Console.repFaction, funnel = Console.funnelCommand,
    log = Console.logCommand,
}

function Console.handle(Service, command, player, args, resultCommand)
    local name = Console.commands[command]
    local handler = name ~= nil and Console.handlers[name] or nil
    if handler == nil then return false end
    local ok, handled = pcall(handler, Service, player, args)
    if ok then return handled == true end
    Console.metrics.faults = Console.metrics.faults + 1
    print("[ALIFE-DEBUG] admin console command failed: " .. tostring(command) .. " " .. tostring(handled))
    Service.sendReply(player, resultCommand, { ok = false, reason = "admin_command_failed", text = tostring(handled) })
    return false
end

function Console.qaFields()
    local m = Console.metrics
    return { requests = m.requests, accepted = m.accepted, failed = m.failed, undone = m.undone,
        previews = m.previews, snapshots = m.snapshots, refused = m.refused, faults = m.faults }
end

function Console.qaLine()
    local m = Console.metrics
    return "[ALIFE-QA] AdminSpawn: requests=" .. tostring(m.requests) .. " accepted=" .. tostring(m.accepted)
        .. " failed=" .. tostring(m.failed) .. " undone=" .. tostring(m.undone)
        .. " previews=" .. tostring(m.previews) .. " snapshots=" .. tostring(m.snapshots)
        .. " batches=" .. tostring(#Console.order) .. " refused=" .. tostring(m.refused)
        .. " faults=" .. tostring(m.faults)
        .. " funnelOverride=" .. tostring(Console.funnel.overridden == true)
end

return Console
