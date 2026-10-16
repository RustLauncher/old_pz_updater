require "ProjectALife/World/ALifeRoadGraph"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Core/ALifeKillAttribution"
require "ProjectALife/Records/ALifeRosterDraw"

ProjectALife = ProjectALife or {}

local Graph = ProjectALife.RoadGraph
local Ledger = ProjectALife.SquadLedger
local Telemetry = ProjectALife.Telemetry
local KillAttribution = ProjectALife.KillAttribution

local Revenge = {
    adapters = {},
    enabled = true,
    settings = {
        dueMinimumHours = 48,
        dueSpreadHours = 25,
        reinforceMax = 2,
        membersCap = 4,
        retryHours = 6,
        failureLimit = 3,
        fixBlurTiles = 25,
        searchHours = 6,
        maxWaves = 2,
    },
    waves = {},
    notices = {
        "Word is {faction} people are asking around about you",
        "Somebody saw {faction} folks near {town}, asking about you",
        "Caught a scrap of radio chatter, {faction} are hunting whoever hurt their people",
    },

    tallies = {},
    metrics = { attributed = 0, contracts = 0, transferred = 0, executed = 0, failed = 0, dropped = 0,
        forgiven = 0, capped = 0, told = 0 },
}
ProjectALife.Revenge = Revenge

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then
        pcall(Telemetry.emit, category, fields)
    end
end

local function roll()
    if type(Revenge.adapters.roll) == "function" then return Revenge.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    return math.random()
end

function Revenge.configure(adapters)
    Revenge.adapters = adapters or {}
    Revenge.enabled = Revenge.adapters.enabled ~= false
    Revenge.tallies = {}
    Revenge.waves = {}
    return true
end

function Revenge.maxWaves()
    if tonumber(Revenge.adapters.maxWaves) ~= nil then return tonumber(Revenge.adapters.maxWaves) end
    local settings = ProjectALife.Settings
    if type(settings) == "table" and type(settings.read) == "function" then
        local ok, current = pcall(settings.read, nil, true)
        if ok and type(current) == "table" and tonumber(current.revengeMaxWaves) ~= nil then
            return tonumber(current.revengeMaxWaves)
        end
    end
    return Revenge.settings.maxWaves
end

function Revenge.waveOf(squad)
    local task = type(squad) == "table" and squad.task or nil
    if type(task) == "table" and task.kind == "revenge" then return tonumber(task.wave) or 1 end
    return 0
end

function Revenge.reinforcement(survivors)
    local ceiling = math.min(math.max(0, math.floor(tonumber(survivors) or 0)), Revenge.settings.reinforceMax)
    return math.min(ceiling, math.floor(roll() * (ceiling + 1)))
end

function Revenge.blurred(x, y)
    local tiles = Revenge.settings.fixBlurTiles
    local angle = roll() * math.pi * 2
    local reach = roll() * tiles
    return x + math.cos(angle) * reach, y + math.sin(angle) * reach
end

function Revenge.attribute(shell)
    if type(Revenge.adapters.attribute) == "function" then return Revenge.adapters.attribute(shell) end
    return KillAttribution.resolve(shell)
end

function Revenge.onActorDied(actor, shell, kind, key, x, y)
    if not Revenge.enabled or type(actor) ~= "table" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}

    local director = ProjectALife.OutpostDirector
    if kind == "player" and memory.outpostId ~= nil and memory.outpostSquadId ~= nil
            and director ~= nil and type(director.noteKill) == "function" then
        director.noteKill(memory.outpostId, memory.outpostSquadId, key)
    end
    local squadId = memory.squadId
    if squadId == nil then return false end
    if kind == nil then kind, key, x, y = Revenge.attribute(shell) end
    if kind ~= "player" then return false end
    local tally = Revenge.tallies[squadId] or { count = 0 }
    tally.count = tally.count + 1
    tally.playerKey = key
    if x ~= nil then tally.x, tally.y = x, y end
    Revenge.tallies[squadId] = tally
    Revenge.metrics.attributed = Revenge.metrics.attributed + 1
    return true
end

function Revenge.owed(factionId, playerKey)
    local reputation = ProjectALife.Reputation
    if factionId == nil or playerKey == nil or reputation == nil
            or type(reputation.statusFor) ~= "function" then
        return true
    end
    local status = reputation.statusFor(playerKey, factionId)
    return status == nil or status == "hostile"
end

function Revenge.onReleased(squad, survivors, hours)
    if not Revenge.enabled or type(squad) ~= "table" then return false end
    local tally = Revenge.tallies[squad.id]
    Revenge.tallies[squad.id] = nil
    if tally == nil or tally.count == 0 or tally.playerKey == nil then return false end
    if not Revenge.owed(squad.factionId, tally.playerKey) then
        Revenge.metrics.forgiven = Revenge.metrics.forgiven + 1
        return false
    end
    local wave = Revenge.waveOf(squad) + 1
    local chain = tostring(squad.factionId) .. "|" .. tostring(tally.playerKey)
    if wave > Revenge.maxWaves() or (Revenge.waves[chain] or 0) >= Revenge.maxWaves() then
        Revenge.metrics.capped = Revenge.metrics.capped + 1
        Ledger.record("revenge_capped", { squad = squad.id, player = tally.playerKey, wave = wave })
        return false
    end
    local contract = {
        playerKey = tally.playerKey,
        dueHours = hours + Revenge.settings.dueMinimumHours + roll() * Revenge.settings.dueSpreadHours,
        lastKnown = { x = tally.x or squad.x, y = tally.y or squad.y },
        backupSize = Revenge.reinforcement(survivors),
        casualties = tally.count,
        wave = wave,
    }
    if survivors > 0 then
        local fresh = Ledger.read(squad.id)
        if fresh == nil then return false end
        Ledger.update(fresh.id, fresh.revision, function(q) q.revenge = contract end, true)
        Revenge.metrics.contracts = Revenge.metrics.contracts + 1
        Ledger.record("revenge_sworn", { squad = squad.id, player = contract.playerKey,
            dueHours = math.floor(contract.dueHours) })
        emit("offline_revenge", { squad = squad.id, task = "sworn on " .. contract.playerKey })
        return true
    end
    if squad.homeOutpostId ~= nil then

        Ledger.record("revenge_transferred", { squad = squad.id, outpost = squad.homeOutpostId,
            player = contract.playerKey })
        Revenge.metrics.transferred = Revenge.metrics.transferred + 1
        return true
    end
    return false
end

local function playerPosition(key, players)
    for _, p in ipairs(players or {}) do
        if tostring(p.key or "") == key then return p end
    end
    return nil
end

local function rosterFor(factionId)
    if type(Revenge.adapters.roster) == "function" then return Revenge.adapters.roster(factionId) end
    local director = ProjectALife.Director
    local roster = director and director.rosters and director.rosters[factionId] or nil
    return roster
end

function Revenge.backOff(squad, hours, reason)
    local contract = squad.revenge
    local failures = (tonumber(contract.failures) or 0) + 1
    local dropped = failures >= Revenge.settings.failureLimit
    Ledger.update(squad.id, squad.revision, function(q)
        if dropped or type(q.revenge) ~= "table" then
            q.revenge = nil
        else
            q.revenge.failures = failures
            q.revenge.dueHours = hours + Revenge.settings.retryHours
        end
    end, true)
    Revenge.metrics.failed = Revenge.metrics.failed + 1
    if dropped then Revenge.metrics.dropped = Revenge.metrics.dropped + 1 end
    reason = string.sub(tostring(reason), 1, 160)
    Ledger.record(dropped and "revenge_dropped" or "revenge_failed", { squad = squad.id,
        player = contract.playerKey, failures = failures, reason = reason })
    emit("offline_revenge", { squad = squad.id, task = (dropped and "dropped: " or "failed: ") .. reason })
    return dropped
end

function Revenge.censusSeats(size, factionId, hours)
    size = math.max(0, math.floor(tonumber(size) or 0))
    local census = ProjectALife.WorldPressure
    if size < 1 or type(census) ~= "table" or type(census.censusAdmit) ~= "function" then return size end
    return math.min(size, tonumber((census.censusAdmit(size, factionId, hours))) or 0)
end

function Revenge.fixFor(contract, players)
    local p = playerPosition(contract.playerKey, players)
    if p ~= nil and tonumber(p.x) ~= nil and tonumber(p.y) ~= nil then
        local x, y = Revenge.blurred(tonumber(p.x), tonumber(p.y))
        return { x = x, y = y, z = 0, key = contract.playerKey, source = "dispatch", searches = 0 }, p
    end
    local last = type(contract.lastKnown) == "table" and contract.lastKnown or {}
    return { x = tonumber(last.x) or 0, y = tonumber(last.y) or 0, z = 0, key = contract.playerKey,
        source = "fight", searches = 0 }, nil
end

function Revenge.tell(squad, contract, fix, online)
    if online == nil then return false end
    local standoff = ProjectALife.Standoff
    if standoff == nil or type(standoff.notify) ~= "function" then return false end
    local catalog, radio = ProjectALife.Catalog, ProjectALife.KnoxRadio
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(squad.factionId) or nil
    local name = type(faction) == "table" and type(faction.general) == "table" and faction.general.name or "Some"
    local town = radio ~= nil and type(radio.townOf) == "function" and radio.townOf(fix.x, fix.y) or nil
    local line = Revenge.notices[1 + math.floor(roll() * #Revenge.notices) % #Revenge.notices]
    if town == nil and string.find(line, "{town}", 1, true) ~= nil then line = Revenge.notices[1] end
    line = string.gsub(string.gsub(line, "{faction}", tostring(name)), "{town}", tostring(town or ""))
    if standoff.notify(contract.playerKey, line) then
        Revenge.metrics.told = Revenge.metrics.told + 1
        return true
    end
    return false
end

function Revenge.drawBackup(roster, q, backup)
    local catalog = ProjectALife.Catalog
    local draw = ProjectALife.RosterDraw
    local taken = {}
    for _, member in ipairs(q.members) do taken[#taken + 1] = member.profileId end
    local drawn = draw ~= nil and draw.begin(taken) or nil
    for index = 1, backup do
        if #q.members >= Revenge.settings.membersCap then break end
        local profile = roster[1 + (index - 1) % math.max(1, #roster)]
        if drawn ~= nil and catalog and catalog.weightedProfile then
            profile = draw.pick(roster, drawn, roll)
        elseif catalog and catalog.weightedProfile then
            profile = catalog.weightedProfile(roster, roll())
        end
        if profile == nil then break end
        q.members[#q.members + 1] = {
            profileId = profile and tostring(profile.id or profile) or (q.members[1] and q.members[1].profileId) or "?",
            health = 100 }
    end
    return q
end

local function execute(squad, hours, players)
    local contract = squad.revenge
    local roster = rosterFor(squad.factionId) or {}
    local backup = Revenge.censusSeats(contract.backupSize, squad.factionId, hours)
    local fix, online = Revenge.fixFor(contract, players)
    local target = Graph.nearest(fix.x, fix.y)
    local here = squad.nodeId or Graph.nearest(squad.x, squad.y)
    local route = (target ~= nil and here ~= nil) and Graph.route(here, target) or nil
    local updated, reason = Ledger.update(squad.id, squad.revision, function(q)
        Revenge.drawBackup(roster, q, backup)
        q.task = { kind = "revenge", label = "revenge: " .. contract.playerKey,
            dest = target, playerKey = contract.playerKey, fix = fix, wave = tonumber(contract.wave) or 1,
            searchUntilHours = hours + Revenge.settings.searchHours }
        q.route = {}
        if type(route) == "table" then
            for index = 2, #route do q.route[#q.route + 1] = route[index] end
        end
        q.legFrom, q.legStartedHours, q.legHours = here, hours, nil
        q.revenge = nil
        q.decisionDueHours = hours + 1e6
    end)
    if updated ~= nil then
        Revenge.metrics.executed = Revenge.metrics.executed + 1
        local chain = tostring(squad.factionId) .. "|" .. tostring(contract.playerKey)
        Revenge.waves[chain] = math.max(Revenge.waves[chain] or 0, tonumber(contract.wave) or 1)
        Revenge.tell(squad, contract, fix, online)
        Ledger.record("revenge_due", { squad = squad.id, player = contract.playerKey })
        emit("offline_revenge", { squad = squad.id, task = "revenge: " .. contract.playerKey })
    elseif string.find(tostring(reason), "squad_mutation_failed", 1, true) == 1 then
        Revenge.backOff(squad, hours, reason)
    end
    return updated ~= nil
end

function Revenge.tick(hours, players)
    if not Revenge.enabled then return 0 end
    local work = 0

    local sworn = {}
    Ledger.eachLive(function(q)
        local contract = q.revenge
        if type(contract) == "table" and q.state == "offline" and hours >= (tonumber(contract.dueHours) or 0) then
            sworn[#sworn + 1] = q.id
        end
    end)
    for _, id in ipairs(sworn) do
        local squad = Ledger.read(id)
        local contract = squad and squad.revenge
        if type(contract) == "table" and squad.state == "offline"
                and not Revenge.owed(squad.factionId, contract.playerKey) then
            Ledger.update(squad.id, squad.revision, function(q) q.revenge = nil end, true)
            Revenge.metrics.forgiven = Revenge.metrics.forgiven + 1
            Ledger.record("revenge_forgiven", { squad = squad.id, player = contract.playerKey })
            work = work + 1
        elseif type(contract) == "table" and squad.state == "offline" then
            if hours >= (tonumber(contract.dueHours) or 0) then
                if execute(squad, hours, players) then work = work + 1 end
            end
        end
    end
    return work
end

return Revenge
