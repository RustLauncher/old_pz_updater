require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/Records/ALifeRelationLayers"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local PlayerLocator = ProjectALife.PlayerLocator
local Layers = ProjectALife.RelationLayers
local Reputation = {
    TAG = "ProjectALife.Reputation.v1",
    SCHEMA = 1,
    adapters = {},
    storage = nil,
    dirty = false,
}
ProjectALife.Reputation = Reputation

local function nowHours()
    if type(Reputation.adapters.nowHours) == "function" then
        return Reputation.adapters.nowHours()
    end
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    if tonumber(hours) ~= nil then return tonumber(hours) end
    if type(Reputation.adapters.nowMs) == "function" then
        return (tonumber(Reputation.adapters.nowMs()) or 0) / 3600000
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() / 3600000 end
    return os.time() / 3600
end

local function authoritative()
    local value = Reputation.adapters.authoritative
    if type(value) == "function" then
        local ok, answer = pcall(value)
        return ok and answer == true
    end
    if value ~= nil then return value == true end
    return not (type(isClient) == "function" and isClient()
        and (type(isServer) ~= "function" or not isServer()))
end

local function storage()
    if Reputation.storage ~= nil then return Reputation.storage end
    local result
    if type(Reputation.adapters.getOrCreate) == "function" then
        result = Reputation.adapters.getOrCreate(Reputation.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        result = ModData.getOrCreate(Reputation.TAG)
    end
    if type(result) ~= "table" then return nil, "mod_data_unavailable" end
    if result.schema == nil then
        result.schema = Reputation.SCHEMA
        result.players = {}
        Reputation.dirty = true
    elseif result.schema ~= Reputation.SCHEMA then
        return nil, "reputation_schema_unsupported:" .. tostring(result.schema)
    end
    result.players = type(result.players) == "table" and result.players or {}
    Reputation.storage = result
    return result
end

local function owned(character)
    local data
    pcall(function() data = character:getModData() end)
    return type(data) == "table" and (data.ProjectALifeOwned == true
        or data.ProjectALifeActor == true)
end

local function multiplayer()
    local value = Reputation.adapters.multiplayer
    if type(value) == "function" then
        local ok, answer = pcall(value)
        return ok and answer == true
    end
    if value ~= nil then return value == true end
    local server, client = false, false
    pcall(function() server = type(isServer) == "function" and isServer() end)
    pcall(function() client = type(isClient) == "function" and isClient() end)
    return server or client
end

function Reputation.playerKey(player)
    if type(player) == "string" and player ~= "" then return player end
    if player == nil then return nil end

    if type(instanceof) == "function" then
        local typeOk, isPlayer = pcall(instanceof, player, "IsoPlayer")
        if not typeOk or isPlayer ~= true then return nil end
    elseif owned(player) then
        return nil
    end
    if type(Reputation.adapters.playerKey) == "function" then
        local ok, value = pcall(Reputation.adapters.playerKey, player)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    local indexable = type(player) == "table" or type(player) == "userdata"
    local ok = indexable and player.getUsername ~= nil
    local username = ok and player:getUsername() or nil
    local playerNum = indexable and player.getPlayerNum ~= nil and player:getPlayerNum() or nil
    if tonumber(playerNum) == nil and (not ok or username == nil) then return nil end
    if multiplayer() and ok and username ~= nil and tostring(username) ~= "" then
        return tostring(username)
    end
    return "sp:" .. tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

local function factionIdOf(actorOrFaction)
    if type(actorOrFaction) == "string" then return actorOrFaction end
    if type(actorOrFaction) == "table" and type(actorOrFaction.factionId) == "string" then
        return actorOrFaction.factionId
    end
    local data
    pcall(function() data = actorOrFaction:getModData() end)
    if type(data) ~= "table" then return nil end
    if type(data.ProjectALifeFactionId) == "string" then
        return data.ProjectALifeFactionId
    end
    local registry = ProjectALife.ActorRegistry
    local actor = type(data.ProjectALifeUID) == "string" and registry
        and registry.read(data.ProjectALifeUID) or nil
    return actor and actor.factionId or nil
end

local function normalized(value)
    value = string.lower(tostring(value or ""))

    if value == "suspicious" then return "careful" end
    if value == "allied" then return "friendly" end
    if value == "friendly" or value == "neutral" or value == "hostile"
            or value == "careful" then
        return value
    end
    return nil
end

function Reputation.defaultStatus(actorOrFaction, player)
    return normalized(Reputation.baselineFor(player, actorOrFaction))
end

Reputation.provokedForgetHours = 24

local function overrideFor(player, actorOrFaction)
    local factionId, key = factionIdOf(actorOrFaction), Reputation.playerKey(player)
    if factionId == nil or key == nil then return nil end
    local state = storage()
    local playerState = state and state.players[key] or nil
    local entry = type(playerState) == "table" and playerState[factionId] or nil
    if type(entry) ~= "table" then return nil end
    if entry.cause == "provoked"
            and nowHours() - (tonumber(entry.atHours) or 0) > Reputation.provokedForgetHours then
        return nil
    end
    return normalized(entry.status)
end

function Reputation.recordedStatus(player, actorOrFaction)
    return overrideFor(player, actorOrFaction)
end

function Reputation.statusFor(player, actorOrFaction)
    return overrideFor(player, actorOrFaction)
        or Reputation.defaultStatus(actorOrFaction, player)
end

local function playerObject(key, hint)
    if hint ~= nil and type(hint) ~= "string"
            and Reputation.playerKey(hint) == key then return hint end
    for _, player in ipairs(PlayerLocator.list(Reputation.adapters.players)) do
        if Reputation.playerKey(player) == key then return player end
    end
    return nil
end

function Reputation.baselineFor(player, actorOrFaction)
    local factionId = factionIdOf(actorOrFaction)
    local faction = factionId and Catalog.faction(factionId) or nil
    if faction == nil then return nil end
    if type(player) == "string" then player = playerObject(player) end
    return (Layers.towardPlayer(faction, Layers.professionOf(player)))
end

local function send(player, payload)
    if type(Reputation.adapters.send) == "function" then
        return Reputation.adapters.send(
            player, "ProjectALife", "reputationSync", payload) ~= false
    end
    local dedicated = type(isServer) == "function" and isServer()
    if not dedicated and ProjectALife.StatusStore
            and type(ProjectALife.StatusStore.receive) == "function" then
        ProjectALife.StatusStore.receive("ProjectALife", "reputationSync", payload)
        return true
    end
    if type(sendServerCommand) ~= "function" then return false end
    sendServerCommand(player, "ProjectALife", "reputationSync", payload)
    return true
end

function Reputation.snapshotFor(player)
    local key = Reputation.playerKey(player)
    if key == nil then return nil, "player_required" end
    local state, reason = storage()
    if state == nil then return nil, reason end
    local result = {
        schema = Reputation.SCHEMA,
        playerKey = key,
        generatedAtHours = nowHours(),
        lastKnown = true,
        profession = Layers.professionOf(player) or "",
        relations = {},
    }
    local playerState = state.players[key]
    if type(playerState) == "table" then
        for factionId, entry in pairs(playerState) do
            if type(entry) == "table" and normalized(entry.status) ~= nil then
                local faction = Catalog.faction(factionId)
                result.relations[#result.relations + 1] = {
                    factionId = factionId,
                    factionName = faction and faction.general
                        and faction.general.name or factionId,
                    status = normalized(entry.status),
                    cause = entry.cause,
                    atHours = tonumber(entry.atHours) or 0,
                }
            end
        end
    end
    table.sort(result.relations, function(left, right)
        return tostring(left.factionName) < tostring(right.factionName)
    end)
    local personal = ProjectALife.PersonalRep
    if personal ~= nil and type(personal.snapshotFor) == "function" then
        local ok, view = pcall(personal.snapshotFor, player)
        if ok and type(view) == "table" then result.personal = view end
    end
    local track = ProjectALife.RepTrack
    if track ~= nil and type(track.humans) == "function" then result.humans = track.humans(player) end
    return result
end

function Reputation.sync(player)
    if not authoritative() then return false, "server_authority_required" end
    local payload, reason = Reputation.snapshotFor(player)
    if payload == nil then return false, reason end
    return send(player, payload)
end

local function setHostile(player, actorOrFaction, cause)
    if not authoritative() then return false, "server_authority_required" end
    local factionId, key = factionIdOf(actorOrFaction), Reputation.playerKey(player)
    if factionId == nil then return false, "faction_required" end
    if key == nil then return false, "player_required" end
    local baseline = Reputation.defaultStatus(factionId, player)
    if baseline == nil or baseline == "hostile" then return false, "unchanged" end
    local state, reason = storage()
    if state == nil then return false, reason end
    local playerState = state.players[key]
    if type(playerState) ~= "table" then
        playerState = {}
        state.players[key] = playerState
    end
    local previous = playerState[factionId]

    if type(previous) == "table" and previous.status == "hostile"
            and previous.cause == "attack" then
        return false, "unchanged"
    end
    if type(previous) == "table" and previous.status == "hostile"
            and previous.cause == cause then
        return false, "unchanged"
    end
    playerState[factionId] = {
        status = "hostile",
        cause = cause,
        atHours = nowHours(),
    }
    Reputation.dirty = true
    local live = playerObject(key, player)
    if live ~= nil then Reputation.sync(live) end
    return true
end

function Reputation.escalationBaseline(actorOrFaction, player)
    return Reputation.baselineFor(player, actorOrFaction)
end

Reputation.escalation = {

    allied = {},

    friendly = { attack = "wound", kill = "kill" },

    neutral = { attack = "attack", kill = "attack" },

    careful = { attack = "attack", kill = "attack", provoked = "provoked" },

    hostile = {},
}

function Reputation.escalate(player, actorOrFaction, deed)
    if not authoritative() then return false, "server_authority_required" end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.actorRecord) == "function"
            and type(relations.isSelfDefence) == "function" then
        local victim = relations.actorRecord(actorOrFaction)
        if victim ~= nil and relations.isSelfDefence(player, victim) then return false, "self_defence" end
    end
    local baseline = Reputation.escalationBaseline(actorOrFaction, player)
    if baseline == nil then return false, "unknown_faction" end
    local row = Reputation.escalation[baseline]
    local cause = type(row) == "table" and row[tostring(deed or "")] or nil
    if cause == nil then return false, "unchanged" end
    return setHostile(player, actorOrFaction, cause)
end

function Reputation.onPlayerDamagedActor(player, actorOrFaction)
    return Reputation.escalate(player, actorOrFaction, "attack")
end

function Reputation.onPlayerKilledActor(player, actorOrFaction)
    return Reputation.escalate(player, actorOrFaction, "kill")
end

function Reputation.onPlayerProvoked(player, actorOrFaction)
    return Reputation.escalate(player, actorOrFaction, "provoked")
end

function Reputation.onPlayerDied(player)
    if not authoritative() then return false, "server_authority_required" end
    local key = Reputation.playerKey(player)
    if key == nil then return false, "player_required" end
    local state, reason = storage()
    if state == nil then return false, reason end
    local playerState = state.players[key]
    if type(playerState) ~= "table" then return false, "unchanged" end
    local changed = false
    for factionId, entry in pairs(playerState) do
        if type(entry) == "table" and (entry.cause == "kill" or entry.cause == "wound")
                and Reputation.defaultStatus(factionId, player) == "friendly" then
            playerState[factionId] = nil
            changed = true
        end
    end
    local populated = false
    for _ in pairs(playerState) do populated = true end
    if not populated then state.players[key] = nil end
    if not changed then return false, "unchanged" end
    Reputation.dirty = true
    local live = playerObject(key, player)
    if live ~= nil then Reputation.sync(live) end
    return true
end

function Reputation.forgetPlayer(player)
    if not authoritative() then return false, "server_authority_required" end
    local key = Reputation.playerKey(player)
    if key == nil then return false, "player_required" end
    local state, reason = storage()
    if state == nil then return false, reason end
    if state.players[key] == nil then return false, "unchanged" end
    state.players[key] = nil
    Reputation.dirty = true
    local live = playerObject(key, player)
    if live ~= nil then Reputation.sync(live) end
    return true
end

function Reputation.configure(adapters)
    Reputation.adapters = adapters or {}
    Reputation.storage = nil
    Reputation.dirty = false
    Layers.forget()
    return true
end

function Reputation.reset()
    local state = storage()
    if state == nil then return false end
    state.schema, state.players = Reputation.SCHEMA, {}
    Reputation.dirty = true
    return true
end

function Reputation.flush()
    if not Reputation.dirty then return true, false end
    if type(Reputation.adapters.transmit) == "function" then
        local ok, result = pcall(Reputation.adapters.transmit, Reputation.TAG)
        if not ok or result == false then return false, "reputation_transmit_failed" end
    end
    Reputation.dirty = false
    return true, true
end

return Reputation
