require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeCustomFactions"
require "ProjectALife/Records/ALifeCreatorTransfer"

ProjectALife = ProjectALife or {}

local Client = { pending = {}, highestSeen = 0, awaitingEdit = false }
ProjectALife.CustomFactionClient = Client

local Custom = ProjectALife.CustomFactions

local function multiplayer()
    local ok, value = pcall(function()
        return type(isClient) == "function" and isClient()
    end)
    return ok and value == true
end

local function player()
    local subject
    pcall(function()
        if type(getSpecificPlayer) == "function" then subject = getSpecificPlayer(0) end
        if subject == nil and type(getPlayer) == "function" then subject = getPlayer() end
    end)
    return subject
end

local function sender()
    if not multiplayer() or type(sendClientCommand) ~= "function" then return false end
    return player()
end

local function sendCommand(command, payload)
    local subject = sender()
    if subject == nil or subject == false then return false end
    local ok, result = pcall(sendClientCommand, subject, "ProjectALife", command, payload)
    return ok and result ~= false
end

function Client.hello(forceRevision)
    local revision = tonumber(forceRevision)
    if revision == nil then revision = Custom.serverManaged and (tonumber(Custom.revision) or 0) or -1 end
    return sendCommand("creatorFactionHello", { revision = math.floor(revision) })
end

function Client.tick()
    if Client.retryAtMs == nil or not multiplayer() then return end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if now < Client.retryAtMs then return end
    Client.retryAtMs = nil
    if not Client.hello(-1) then Client.retryAtMs = now + 1000 end
end

function Client.upsert(faction)
    if type(faction) ~= "table" or type(faction.id) ~= "string" then return false end
    local text = Custom.serializeFaction(faction)
    if #text > ProjectALife.CreatorTransfer.chunkChars then
        local subject = sender()
        if subject == nil or subject == false then return false end
        return ProjectALife.CreatorTransfer.send(subject, "faction", "", text, faction.id)
    end
    return sendCommand("creatorFactionUpsert", {
        factionId = faction.id,
        text = text,
    })
end

function Client.delete(factionId)
    if type(factionId) ~= "string" then return false end
    local sent = sendCommand("creatorFactionDelete", { factionId = factionId })
    if sent then Client.awaitingEdit = true end
    return sent
end

function Client.reset()
    local sent = sendCommand("creatorFactionReset", {})
    if sent then Client.awaitingEdit = true end
    return sent
end

function Client.accept(payload)
    payload = type(payload) == "table" and payload or {}
    if tonumber(payload.schema) ~= 1 then return false, "faction_sync_schema" end
    local revision = math.floor(tonumber(payload.revision) or -1)
    local index = math.floor(tonumber(payload.index) or 0)
    local total = math.floor(tonumber(payload.total) or 0)
    local text = type(payload.text) == "string" and payload.text or nil
    if not ProjectALife.CreatorTransfer.integer(payload.revision, 0, 9007199254740991)
            or not ProjectALife.CreatorTransfer.integer(payload.index, 1, total)
            or not ProjectALife.CreatorTransfer.integer(payload.total, 1, math.ceil(2000000 / 7999))
            or text == nil or #text > 8000 then
        return false, "faction_sync_chunk_invalid"
    end
    if revision < (tonumber(Custom.revision) or 0)
            or revision < Client.highestSeen then return false, "faction_sync_stale" end
    if revision > Client.highestSeen then
        Client.highestSeen = revision
        Client.pending = {}
    end
    if revision == Custom.revision and Custom.serverManaged and not Client.awaitingEdit then
        Client.retryAtMs = nil
        return true, "current"
    end
    local pending = Client.pending[revision]
    if pending == nil then
        pending = { total = total, parts = {}, count = 0 }
        Client.pending[revision] = pending
    elseif pending.total ~= total then
        Client.pending[revision] = nil
        return false, "faction_sync_shape_changed"
    end
    if pending.parts[index] == nil then
        pending.parts[index] = text
        pending.count = pending.count + 1
    elseif pending.parts[index] ~= text then
        Client.pending[revision] = nil
        return false, "faction_sync_chunk_changed"
    end
    if pending.count < total then return true, "partial" end
    local ordered = {}
    for part = 1, total do
        if pending.parts[part] == nil then return true, "partial" end
        ordered[#ordered + 1] = pending.parts[part]
    end
    local combined = table.concat(ordered)
    Client.pending[revision] = nil
    if #combined > 2000000 then return false, "creator_payload_too_large" end
    local applied, reason = Custom.applySync(combined, revision, true)
    if not applied then return false, reason end
    Client.awaitingEdit = false
    Client.retryAtMs = nil
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(catalog.reset) == "function"
            and type(catalog.load) == "function" then
        catalog.reset()
        local loaded, loadReason = catalog.load()
        if loaded == nil then return false, loadReason or "catalog_reload_failed" end
    end

    pcall(function()
        local creator = ProjectALife.CreatorScreen
        if creator ~= nil and type(creator.onFactionsSynced) == "function" then
            creator.onFactionsSynced(revision)
        end
    end)
    return true, "complete"
end

function Client.receive(module, command, payload)
    if module ~= "ProjectALife" then return false end
    if command == "creatorFactionHelloResult" then
        local delay = type(payload) == "table" and tonumber(payload.retryAfterMs) or nil
        if delay ~= nil and delay == delay and delay > 0 then
            local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
            Client.retryAtMs = now + math.max(100, math.min(10000, delay))
            return true
        end
        return false
    end
    if command == "creatorFactionSync" then
        return Client.accept(payload)
    end
    if command == "creatorFactionUpsertResult"
            or command == "creatorFactionDeleteResult"
            or command == "creatorFactionResetResult" then
        if type(payload) == "table" and payload.ok ~= true then

            Client.awaitingEdit = true
            return Client.hello(-1)
        end
        return true
    end
    return false
end

function Client.register()
    if type(Events) ~= "table" then return false end
    if Events.OnServerCommand ~= nil
            and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(Client.receive)
    end
    local function hello()
        if not multiplayer() then return end
        Client.pending, Client.highestSeen, Client.awaitingEdit = {}, 0, true
        Client.retryAtMs = nil
        Custom.revision, Custom.serverManaged = 0, false
        Client.hello(-1)
    end
    if Events.OnConnected ~= nil and type(Events.OnConnected.Add) == "function" then
        Events.OnConnected.Add(hello)
    end
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(hello)
    end
    if Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
        Events.OnTick.Add(Client.tick)
    end
    return true
end

Client.register()

return Client
