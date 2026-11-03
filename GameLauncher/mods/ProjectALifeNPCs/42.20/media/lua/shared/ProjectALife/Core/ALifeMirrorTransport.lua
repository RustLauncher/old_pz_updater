ProjectALife = ProjectALife or {}
if ProjectALife.MirrorTransport then return ProjectALife.MirrorTransport end

local Transport = {
    settings = { intervalMs = 1000, fullIntervalMs = 30000, interestRadius = 250,
        maxRecipients = 4, budgetMs = 6, requestIntervalMs = 2000,

        baseRadius = 120, baseLimit = 16, baseFreshMs = 60000 },
    peers = {}, cursor = 1, adapters = {},
    client = { records = {}, sequence = 0, requestedAtMs = -1e12 },
    metrics = { frames = 0, full = 0, records = 0, identities = 0, resyncs = 0,
        received = 0, gaps = 0, lastMs = 0, maxMs = 0 },
}
ProjectALife.MirrorTransport = Transport

local function clock()
    if Transport.adapters.nowMs then return Transport.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function copy(value, depth)
    if type(value) ~= "table" then return value end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item, depth) end
    return result
end

local function players()
    if Transport.adapters.players then return Transport.adapters.players() end
    local locator = ProjectALife.PlayerLocator
    if locator and locator.list then return locator.list() end
    return {}
end

local function position(player)
    if Transport.adapters.position then return Transport.adapters.position(player) end
    local locator = ProjectALife.PlayerLocator
    if locator and locator.position then return locator.position(player) end
    return nil
end

function Transport.died(now)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.diedFrame) ~= "function" then return nil end
    return executor.diedFrame(now)
end

function Transport.available()
    return Transport.adapters.send ~= nil or (type(sendServerCommand) == "function"
        and ProjectALife.PlayerLocator ~= nil)
end

local function owns(player, uid)
    if Transport.adapters.owns then return Transport.adapters.owns(player, uid) == true end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog and watchdog.bindings and watchdog.bindings[uid]
    local shell = binding and binding.shell
    if shell and shell.getOwnerPlayer ~= nil then
        local ok, owner = pcall(function() return shell:getOwnerPlayer() end)
        return ok and owner == player
    end
    return false
end

function Transport.request(player, now)
    if player == nil then return false end
    now = now or clock()
    local peer = Transport.peers[player]
    if peer == nil then
        peer = { known = {}, sequence = 0, due = now, fullAt = -1e12, stream = tostring(now) }
        Transport.peers[player] = peer
    end
    if now - (peer.requestedAt or -1e12) < Transport.settings.requestIntervalMs then return false end
    peer.requestedAt, peer.fullAt, peer.due = now, -1e12, now
    Transport.metrics.resyncs = Transport.metrics.resyncs + 1
    return true
end

function Transport.basesNear(point)
    local result = {}
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then return result end
    local source = Transport.adapters.bases
    if source == nil then
        local heat = ProjectALife.BaseHeat
        source = heat ~= nil and (heat.homes or heat.bases) or nil
        if type(source) ~= "function" then return result end
    end
    local ok, bases = pcall(source)
    if not ok or type(bases) ~= "table" then return result end
    local reach, x, y = Transport.settings.baseRadius, tonumber(point.x), tonumber(point.y)
    for _, base in ipairs(bases) do
        if type(base) == "table" and #result < Transport.settings.baseLimit then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil
                    and x >= x1 - reach and x <= x2 + reach and y >= y1 - reach and y <= y2 + reach then
                result[#result + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, owner = Transport.ownerOf(base),
                    flagged = base.flagged == true, occupied = base.occupied == true or nil }
            end
        end
    end
    return result
end

function Transport.ownerOf(base)
    if type(base.owner) == "string" and base.owner ~= "" then return base.owner end
    return nil
end

function Transport.acceptBases(list)
    local kept = {}
    for _, base in ipairs(list) do
        if type(base) == "table" and #kept < Transport.settings.baseLimit then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                kept[#kept + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, owner = Transport.ownerOf(base),
                    flagged = base.flagged == true, occupied = base.occupied == true or nil }
            end
        end
    end
    Transport.client.bases, Transport.client.basesAtMs = kept, clock()
end

function Transport.clientBases()
    local client = Transport.client
    if type(client.bases) ~= "table" or client.basesAtMs == nil
            or clock() - client.basesAtMs > Transport.settings.baseFreshMs then
        return nil
    end
    return client.bases
end

function Transport.tick(now)
    if not Transport.available() then return 0 end
    now = now or clock()
    local started, online, live = clock(), players(), {}
    for _, player in ipairs(online) do live[player] = true end
    for player in pairs(Transport.peers) do
        if not live[player] then Transport.peers[player] = nil end
    end
    local sent, visited, active, present, total = 0, 0, nil, nil, 0
    while visited < #online and sent < Transport.settings.maxRecipients do
        if sent > 0 and clock() - started >= Transport.settings.budgetMs then break end
        if Transport.cursor > #online then Transport.cursor = 1 end
        local player = online[Transport.cursor]
        Transport.cursor, visited = Transport.cursor + 1, visited + 1
        local peer = Transport.peers[player]
        if peer == nil then
            Transport.request(player, now)
            peer = Transport.peers[player]
        end
        if now >= peer.due then
            if active == nil then
                active, present = {}, {}
                ProjectALife.ActorRegistry.each(function(record)
                    if record.lifecycle == "active" then
                        active[#active + 1] = record
                        present[record.uid] = record.generation
                        total = total + 1
                    end
                end)
            end
            local point, known, changed, removed, count = position(player), {}, {}, {}, 0
            local full = now - peer.fullAt >= Transport.settings.fullIntervalMs

            local catalog = ProjectALife.Catalog and ProjectALife.Catalog.current
            if peer.catalog ~= catalog then full = true end
            local profileKnown = full and {} or (peer.profileKnown or {})
            local factionKnown = full and {} or (peer.factionKnown or {})
            local definitions = { npcs = {}, factions = {} }
            local radius2 = Transport.settings.interestRadius ^ 2
            for _, record in ipairs(active) do
                local p = record.worldPosition
                local nearby = point and p and type(p.x) == "number" and type(p.y) == "number"
                    and (p.x - point.x)^2 + (p.y - point.y)^2 <= radius2
                if nearby or owns(player, record.uid) then
                    if catalog ~= nil then
                        if not profileKnown[record.profileId] and catalog.npcs[record.profileId] then
                            definitions.npcs[record.profileId] = copy(catalog.npcs[record.profileId])
                        end
                        if not factionKnown[record.factionId] and catalog.factions[record.factionId] then
                            definitions.factions[record.factionId] = copy(catalog.factions[record.factionId])
                        end
                    end
                    local version = tostring(record.generation) .. ":" .. tostring(record.revision)
                    known[record.uid] = version
                    if full or peer.known[record.uid] ~= version then
                        changed[record.uid], count = copy(record), count + 1
                    end
                end
            end
            for uid in pairs(peer.known) do if known[uid] == nil then removed[uid] = true end end
            local frame = { stream = peer.stream, sequence = peer.sequence + 1, full = full,
                records = changed, removed = removed, present = present, catalog = definitions,
                warfare = ProjectALife.Relations and ProjectALife.Relations.warfare,
                bases = Transport.basesNear(point),
                died = Transport.died(now) }
            local ok, result
            if Transport.adapters.send then
                ok, result = pcall(Transport.adapters.send, player, frame)
            else
                ok, result = pcall(sendServerCommand, player, "ProjectALife", "executorMirror", frame)
            end
            peer.due = now + Transport.settings.intervalMs
            if ok and result ~= false then
                for id in pairs(definitions.npcs) do profileKnown[id] = true end
                for id in pairs(definitions.factions) do factionKnown[id] = true end
                peer.catalog, peer.profileKnown, peer.factionKnown = catalog, profileKnown, factionKnown
            end
            if ok and result ~= false then
                peer.known, peer.sequence = known, frame.sequence
                if full then peer.fullAt = now; Transport.metrics.full = Transport.metrics.full + 1 end
                Transport.metrics.frames = Transport.metrics.frames + 1
                Transport.metrics.records = Transport.metrics.records + count
                Transport.metrics.identities = Transport.metrics.identities + total
            end
            sent = sent + 1
        end
    end
    Transport.metrics.lastMs = clock() - started
    Transport.metrics.maxMs = math.max(Transport.metrics.maxMs, Transport.metrics.lastMs)
    return sent
end

function Transport.requestFull(now)
    now = now or clock()
    if now - Transport.client.requestedAtMs < Transport.settings.requestIntervalMs then return false end
    Transport.client.requestedAtMs = now
    if Transport.adapters.request then Transport.adapters.request()
    elseif type(sendClientCommand) == "function" then
        sendClientCommand("ProjectALife", "executorMirrorRequest", {})
    end
    return true
end

function Transport.receive(frame)
    if type(frame) ~= "table" or type(frame.records) ~= "table" or type(frame.present) ~= "table"
        or type(frame.sequence) ~= "number" or type(frame.stream) ~= "string" then return false end
    local client = Transport.client
    if frame.stream == client.stream and frame.sequence <= client.sequence then return false end
    if not frame.full and (frame.stream ~= client.stream or frame.sequence ~= client.sequence + 1) then
        Transport.metrics.gaps = Transport.metrics.gaps + 1
        Transport.requestFull()
        return false
    end
    local records = frame.full and {} or client.records
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(frame.catalog) == "table" then
        if frame.full or catalog.network == nil then catalog.network = { npcs = {}, factions = {} } end
        for _, kind in ipairs({ "npcs", "factions" }) do
            for id, definition in pairs(frame.catalog[kind] or {}) do
                if type(id) == "string" and type(definition) == "table" then catalog.network[kind][id] = definition end
            end
        end
        if type(catalog.normalize) == "function" then catalog.normalize(catalog.network) end
    end
    if type(frame.warfare) == "boolean" and ProjectALife.Relations ~= nil then
        ProjectALife.Relations.warfare = frame.warfare
    end
    for uid in pairs(type(frame.removed) == "table" and frame.removed or {}) do records[uid] = nil end
    for uid, record in pairs(frame.records) do records[uid] = record end
    local count = 0
    for _ in pairs(records) do count = count + 1 end

    local data = { records = records, present = frame.present, count = count }
    if type(frame.died) == "table" then data.died = frame.died end
    if not frame.full then data.changed = frame.records end
    if not ProjectALife.Executor.applyMirror(data) then return false end
    client.records, client.sequence, client.stream = records, frame.sequence, frame.stream
    client.receivedAtMs = clock()
    if type(frame.bases) == "table" then Transport.acceptBases(frame.bases) end
    Transport.metrics.received = Transport.metrics.received + 1

    local held = 0
    for _ in pairs(records or {}) do held = held + 1 end
    Transport.metrics.heldRecords = held
    Transport.metrics.heldPeak = math.max(tonumber(Transport.metrics.heldPeak) or 0, held)
    return true
end

function Transport.reset()
    if ProjectALife.Catalog ~= nil then ProjectALife.Catalog.network = nil end
    Transport.peers, Transport.cursor = {}, 1
    Transport.client = { records = {}, sequence = 0, requestedAtMs = -1e12 }
    Transport.metrics = { frames = 0, full = 0, records = 0, identities = 0,
        resyncs = 0, received = 0, gaps = 0, lastMs = 0, maxMs = 0,

        heldRecords = 0, heldPeak = 0 }
end

function Transport.qaLine()
    local m = Transport.metrics
    return " mirrorFrames=" .. m.frames .. " full=" .. m.full .. " changedRecords=" .. m.records
        .. " identityEntries=" .. m.identities .. " received=" .. m.received .. " gaps=" .. m.gaps
        .. " resyncs=" .. m.resyncs .. " sendMs=" .. m.lastMs .. "/" .. m.maxMs
end

return Transport
