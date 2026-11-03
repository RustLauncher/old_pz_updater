-- Server side of A-Life Faction Relations: outpost discovery (#6), kill counts and Jeem Extension's standing points.
-- Read-only use of A-Life's Reputation and OutpostRegistry; kill counts wrap one Reputation function pass-through.
if isClient() then return end

ALifeRelationsServer = {}
local S = ALifeRelationsServer

local MODULE = "ALifeRelations"
local ACTIVE = { built = true, garrisoned = true, draining = true }

-- Sandbox options (page "A-Life Faction Relations").
local function setting(name)
    return SandboxVars and SandboxVars.ALifeRelations and SandboxVars.ALifeRelations[name]
end

-- Tiles; how close a player must get for an outpost to be marked.
function S.discoverRadius()
    return tonumber(setting("DiscoverRadius")) or 50
end

local function send(player, command, args)
    if isServer() then
        sendServerCommand(player, MODULE, command, args)
    elseif ALifeRelations and ALifeRelations.receive then
        ALifeRelations.receive(command, args) -- single player: same Lua state
    end
end

local function players()
    local list, source = {}, isServer() and getOnlinePlayers() or IsoPlayer.getPlayers()
    for i = 0, source:size() - 1 do
        local player = source:get(i)
        if player then list[#list + 1] = player end
    end
    return list
end

-- Kills per player: playerKey -> factionId -> count. Keyed like A-Life's reputation (username in MP,
-- "sp:0" in single player), so counts survive the character's death.
local function killStore()
    return ModData.getOrCreate("ALifeRelations.Kills")
end

function S.killsOf(player)
    local key = ProjectALife and ProjectALife.Reputation and ProjectALife.Reputation.playerKey(player)
    return key and killStore()[key] or {}
end

local counted = {} -- "uid:generation" of deaths already counted, in case A-Life reports one twice

local function countKill(playerOrKey, actor)
    local reputation = ProjectALife.Reputation
    local key = reputation.playerKey(playerOrKey)
    if key == nil or type(actor) ~= "table" or actor.factionId == nil then return end
    local death = tostring(actor.uid) .. ":" .. tostring(actor.generation)
    if counted[death] then return end
    counted[death] = true
    local store = killStore()
    store[key] = store[key] or {}
    store[key][actor.factionId] = (store[key][actor.factionId] or 0) + 1
    for _, player in ipairs(players()) do
        if reputation.playerKey(player) == key then send(player, "kills", { kills = store[key] }) end
    end
end

-- A-Life calls Reputation.onPlayerKilledActor once for every NPC death it pins on a player, whatever the
-- standing. Count first (a bug here can't break A-Life), then hand the call to A-Life unchanged.
local wrapped = false
function S.hookKills()
    local reputation = ProjectALife and ProjectALife.Reputation
    if wrapped or reputation == nil or reputation.onPlayerKilledActor == nil then return end
    wrapped = true
    local original = reputation.onPlayerKilledActor
    reputation.onPlayerKilledActor = function(playerOrKey, actor)
        pcall(countKill, playerOrKey, actor)
        return original(playerOrKey, actor)
    end
end

Events.OnGameStart.Add(S.hookKills)
Events.OnServerStarted.Add(S.hookKills)

-- Jeem Extension's standing points live only in the server's ModData; read them through its own getters.
-- points include the share from the player's vanilla faction, as Jeem's label does.
function S.standingOf(player)
    local J = ProjectALifeJimmy
    local service = J and J.StandingService
    if service == nil then return { available = false } end
    local key = J.playerKey(player)
    local data = service.data()
    local waiting = {}
    for _, item in ipairs(type(data.pending) == "table" and data.pending or {}) do
        if item.key == key then waiting[item.factionId] = (waiting[item.factionId] or 0) + 1 end
    end
    local state, factions = key and data.players[key], {}
    for id, own in pairs(type(state) == "table" and type(state.factions) == "table" and state.factions or {}) do
        local bonus = service.poolBonus(key, id)
        factions[id] = { points = (tonumber(own) or 0) + bonus, bonus = bonus, label = service.labelFor(key, id),
            default = service.defaultLabel(id), toNext = service.toNext(key, id), events = service.events(key, id),
            waiting = waiting[id] }
    end
    return { available = true, enabled = J.enabled("standing"), thresholds = service.thresholds,
        clamp = service.clamp, factions = factions }
end

function S.handle(player, command)
    if command == "kills" then send(player, "kills", { kills = S.killsOf(player) }) end
    if command == "standing" then
        -- Jeem's internals can change under us; a failed read shows as "not available", not a Lua error.
        local ok, standing = pcall(S.standingOf, player)
        if not ok then print("ALifeRelations: reading Jeem's standing failed: " .. tostring(standing)) end
        send(player, "standing", ok and standing or { available = false })
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module == MODULE then S.handle(player, command) end
end)

-- known: siteId -> { x, y, factionId, lastSeenDay, gone }. Sites near the player are refreshed;
-- known sites near the player that are no longer active turn grey but stay on the map.
function S.updateKnown(known, sites, px, py, radius, day)
    local nearby, r2 = {}, radius * radius
    for _, site in ipairs(sites) do
        local x, y = tonumber(site.x) or 0, tonumber(site.y) or 0
        if (x - px) ^ 2 + (y - py) ^ 2 <= r2 then
            nearby[site.id] = true
            if ACTIVE[site.state] then
                known[site.id] = { x = x, y = y, factionId = site.factionId, lastSeenDay = day }
            elseif known[site.id] then
                known[site.id].gone = true
            end
        end
    end
    for id, mark in pairs(known) do
        if not nearby[id] and (mark.x - px) ^ 2 + (mark.y - py) ^ 2 <= r2 then mark.gone = true end
    end
    return known
end

Events.EveryTenMinutes.Add(function()
    local registry = ProjectALife and ProjectALife.OutpostRegistry
    local reputation = ProjectALife and ProjectALife.Reputation
    if registry == nil or reputation == nil or setting("MapMarks") == false then return end
    local sites = registry.list()
    local store = ModData.getOrCreate("ALifeRelations.Outposts")
    local day = math.floor(getGameTime():getWorldAgeHours() / 24) + 1
    local radius = S.discoverRadius()
    for _, player in ipairs(players()) do
        local key = reputation.playerKey(player)
        if key then
            store[key] = S.updateKnown(store[key] or {}, sites, player:getX(), player:getY(), radius, day)
            send(player, "outposts", { sites = store[key] })
        end
    end
end)
