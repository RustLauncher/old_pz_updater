require "ProjectALife/World/ALifeRoadGraph"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Core/ALifeTelemetry"

ProjectALife = ProjectALife or {}

local Graph = ProjectALife.RoadGraph
local Ledger = ProjectALife.SquadLedger
local Telemetry = ProjectALife.Telemetry

local Combat = {
    adapters = {},
    settings = {
        meetDistance = 25,
        playerKeepOut = 110,
        pairCooldownHours = 6,
        wobbleMinimum = 0.82,
        wobbleMaximum = 1.18,
        loserMorale = -0.2,
        winnerMorale = 0.08,
        moraleFloor = 0.1,

        weaponScores = {
            { "AssaultRifle", 10 }, { "M16", 10 }, { "AK", 10 },
            { "HuntingRifle", 8 }, { "VarmintRifle", 7 }, { "Rifle", 7 },
            { "Shotgun", 8 }, { "Pistol", 5 }, { "Revolver", 5 },
            { "Machete", 4 }, { "Axe", 4 }, { "Sledge", 4 }, { "Bat", 3 },
        },
        defaultWeaponScore = 3,

        applyPerBeat = 10,
    },

    pending = {},
    pendingHead = 1,
    metrics = { fights = 0, casualties = 0, wipes = 0, dropped = 0, deferred = 0 },
}
ProjectALife.OfflineCombat = Combat

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then
        pcall(Telemetry.emit, category, fields)
    end
end

function Combat.weaponScore(primary, settings)
    settings = settings or Combat.settings
    local name = tostring(primary or "")
    for _, pair in ipairs(settings.weaponScores) do
        if string.find(name, pair[1], 1, true) then return pair[2] end
    end
    return settings.defaultWeaponScore
end

local function primaryOf(profileId)
    if type(Combat.adapters.primaryOf) == "function" then return Combat.adapters.primaryOf(profileId) end
    local primary
    pcall(function()
        local catalog = ProjectALife.Catalog
        local profile = catalog and catalog.npc(profileId) or nil
        primary = profile and profile.weapons and profile.weapons.primary or nil
    end)
    return primary
end

function Combat.power(squad, wobble, scorer)
    local total = 0
    for _, member in ipairs(squad.members or {}) do
        local health = math.max(0.1, (tonumber(member.health) or 100) / 100)
        total = total + health * scorer(member.profileId)
    end
    local morale = tonumber(squad.morale) or 0.65
    return total * (0.65 + morale * 0.7) * (tonumber(wobble) or 1)
end

local function distance(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function nearPlayer(squad, players, keepOut)
    for _, p in ipairs(players or {}) do
        if distance(squad, p) <= keepOut then return true end
    end
    return false
end

local function hostile(a, b)
    if type(Combat.adapters.hostile) == "function" then return Combat.adapters.hostile(a, b) end
    local relations = ProjectALife.Relations
    if relations == nil then return a.factionId ~= b.factionId end
    return relations.hostile({ uid = a.id, factionId = a.factionId },
        { uid = b.id, factionId = b.factionId })
end

function Combat.pairKey(a, b)
    if a.id < b.id then return a.id .. "|" .. b.id end
    return b.id .. "|" .. a.id
end

function Combat.resolve(squads, hours, players, rolls, scorer, settings)
    settings = settings or Combat.settings
    local size = math.max(1, settings.meetDistance)
    local cells, cellX, cellY = {}, {}, {}
    for i = 1, #squads do
        local a = squads[i]
        if a.state == "offline" and (a.route == nil or #a.route == 0)
                and a.members ~= nil and #a.members > 0
                and not nearPlayer(a, players, settings.playerKeepOut) then
            local cx, cy = math.floor((a.x or 0) / size), math.floor((a.y or 0) / size)
            local cell = cx * 131072 + cy

            if cell == cell and cell ~= math.huge and cell ~= -math.huge then
                local list = cells[cell]
                if list == nil then list = {}; cells[cell] = list end
                list[#list + 1] = i
                cellX[i], cellY[i] = cx, cy
            end
        end
    end
    local outcomes, fought, candidates = {}, {}, {}
    for i = 1, #squads do
        local a = squads[i]
        if cellX[i] ~= nil and not fought[a.id] then
            local count, cx, cy = 0, cellX[i], cellY[i]
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local list = cells[(cx + dx) * 131072 + cy + dy]
                    if list ~= nil then
                        for _, j in ipairs(list) do
                            if j > i then count = count + 1; candidates[count] = j end
                        end
                    end
                end
            end
            for k = #candidates, count + 1, -1 do candidates[k] = nil end
            table.sort(candidates)
            for _, j in ipairs(candidates) do
                local b = squads[j]
                if not fought[b.id] and distance(a, b) <= settings.meetDistance and hostile(a, b) then
                    local key = Combat.pairKey(a, b)
                    local cooldown = (a.pairCooldowns or {})[key] or (b.pairCooldowns or {})[key]
                    if cooldown == nil or hours >= cooldown then
                        local r = rolls(2)
                        local wobbleA = settings.wobbleMinimum + (settings.wobbleMaximum - settings.wobbleMinimum) * r[1]
                        local wobbleB = settings.wobbleMinimum + (settings.wobbleMaximum - settings.wobbleMinimum) * r[2]
                        local powerA, powerB = Combat.power(a, wobbleA, scorer), Combat.power(b, wobbleB, scorer)
                        local winner, loser, ratio
                        if powerA >= powerB then winner, loser, ratio = a, b, powerA / math.max(0.01, powerB)
                        else winner, loser, ratio = b, a, powerB / math.max(0.01, powerA) end
                        outcomes[#outcomes + 1] = {
                            key = key, winner = winner.id, loser = loser.id, ratio = ratio, first = a.id,
                            loserCasualties = math.min(#loser.members, ratio > 2 and 2 or 1),
                            winnerCasualties = (ratio < 1.3 and #winner.members > 1) and 1 or 0,
                            cooldownUntil = hours + settings.pairCooldownHours,
                            x = (a.x + b.x) / 2, y = (a.y + b.y) / 2,
                        }
                        fought[a.id], fought[b.id] = true, true
                        break
                    end
                end
            end
        end
    end
    return outcomes
end

local function retreatRoute(loser, winner)
    local here = loser.nodeId or Graph.nearest(loser.x, loser.y)
    if here == nil then return {} end
    local best, bestDistance = nil, -1
    for other in pairs(Graph.adjacency[here] or {}) do
        local node = Graph.nodes[other]
        local d = distance(node, winner)
        if d > bestDistance then best, bestDistance = other, d end
    end
    return best and { best } or {}
end

local function shed(q, count, hours)
    local lost = {}
    for _ = 1, count do
        if #q.members == 0 then break end
        local index = #q.members
        lost[#lost + 1] = q.members[index]
        table.remove(q.members, index)
    end
    if #q.members == 0 then
        q.state = "wiped"
        q.wipedHours = hours
    end
    return lost
end

function Combat.pruneCooldowns(q, hours)
    local cooldowns = q.pairCooldowns
    if type(cooldowns) ~= "table" then q.pairCooldowns = {}; return 0 end
    local expired
    for key, untilHours in pairs(cooldowns) do
        if not (hours < (tonumber(untilHours) or 0)) then
            expired = expired or {}
            expired[#expired + 1] = key
        end
    end
    if expired == nil then return 0 end
    for _, key in ipairs(expired) do cooldowns[key] = nil end
    return #expired
end

function Combat.stillMeets(outcome, players)
    local winner, loser = Ledger.peek(outcome.winner), Ledger.peek(outcome.loser)
    if winner == nil or loser == nil then return false end
    if winner.state ~= "offline" or loser.state ~= "offline" then return false end

    if (winner.route ~= nil and #winner.route > 0) or (loser.route ~= nil and #loser.route > 0) then return false end
    if #(winner.members or {}) == 0 or #(loser.members or {}) == 0 then return false end
    local settings = Combat.settings
    if not (distance(winner, loser) <= settings.meetDistance) then return false end

    if outcome.first == loser.id then
        if not hostile(loser, winner) then return false end
    elseif not hostile(winner, loser) then
        return false
    end
    return not nearPlayer(winner, players, settings.playerKeepOut)
        and not nearPlayer(loser, players, settings.playerKeepOut)
end

function Combat.noteLosses(loserFaction, loserLost, winnerFaction, winnerLost, hours)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusLoss) ~= "function" then return false end
    if loserLost > 0 then census.censusLoss(loserFaction, loserLost, hours) end
    if winnerLost > 0 then census.censusLoss(winnerFaction, winnerLost, hours) end
    return true
end

function Combat.noteRegion(outcome, count, hours)
    local regions = ProjectALife.RegionLedger
    if regions == nil or type(regions.noteDeaths) ~= "function" or type(outcome) ~= "table" then return false end
    return regions.noteDeaths(outcome.x, outcome.y, count, hours)
end

function Combat.noteDead(squad, dead, outcome, hours)
    local war = ProjectALife.WarDead
    if war == nil or type(war.record) ~= "function" or type(dead) ~= "table" or #dead == 0 then return 0 end
    local ok, count = pcall(war.record, squad, dead, outcome.x, outcome.y, hours)
    return ok and tonumber(count) or 0
end

function Combat.apply(outcome, hours)
    local settings = Combat.settings

    local winner, loser = Ledger.peek(outcome.winner), Ledger.peek(outcome.loser)
    if winner == nil or loser == nil then return false end
    if winner.state ~= "offline" or loser.state ~= "offline" then return false end
    local wiped, lost = false, { loser = 0, winner = 0 }
    Ledger.update(loser.id, loser.revision, function(q)
        lost.loserDead = shed(q, outcome.loserCasualties, hours)
        lost.loser = #lost.loserDead
        q.morale = math.max(settings.moraleFloor, (q.morale or 0.65) + settings.loserMorale)
        Combat.pruneCooldowns(q, hours)
        q.pairCooldowns[outcome.key] = outcome.cooldownUntil
        if q.state ~= "wiped" then
            q.route = retreatRoute(q, winner)
            q.task = { kind = "withdraw", label = "withdraw", dest = q.route[1] }
            q.legFrom = q.nodeId or Graph.nearest(q.x, q.y)
            q.legStartedHours, q.legHours = hours, nil
        else
            wiped = true
        end
    end, true)
    Ledger.update(winner.id, winner.revision, function(q)
        lost.winnerDead = shed(q, outcome.winnerCasualties, hours)
        lost.winner = #lost.winnerDead
        q.morale = math.min(1, (q.morale or 0.65) + settings.winnerMorale)
        Combat.pruneCooldowns(q, hours)
        q.pairCooldowns[outcome.key] = outcome.cooldownUntil
    end, true)
    Combat.noteLosses(loser.factionId, lost.loser, winner.factionId, lost.winner, hours)
    Combat.noteDead(loser, lost.loserDead, outcome, hours)
    Combat.noteDead(winner, lost.winnerDead, outcome, hours)
    Combat.noteRegion(outcome, lost.loser + lost.winner, hours)
    Combat.metrics.fights = Combat.metrics.fights + 1
    Combat.metrics.casualties = Combat.metrics.casualties + outcome.loserCasualties + outcome.winnerCasualties
    if wiped then Combat.metrics.wipes = Combat.metrics.wipes + 1 end
    Ledger.record("fight", { winner = outcome.winner, loser = outcome.loser,
        ratio = math.floor(outcome.ratio * 100) / 100, x = math.floor(outcome.x), y = math.floor(outcome.y),
        casualties = outcome.loserCasualties + outcome.winnerCasualties, wiped = wiped })
    return true
end

function Combat.drain(hours, players)
    local queue, head = Combat.pending, Combat.pendingHead
    if queue[head] == nil then return 0 end
    local metrics = Combat.metrics

    Ledger.peek(queue[head].winner)
    if Ledger.storage ~= Combat.pendingStore then
        metrics.dropped = metrics.dropped + #queue - head + 1
        Combat.reset()
        return 0
    end
    local budget = math.max(1, math.floor(tonumber(Combat.settings.applyPerBeat) or 10))
    local casualties, wipes = metrics.casualties, metrics.wipes
    local applied, examined = 0, 0
    while applied < budget and examined < budget * 4 and queue[head] ~= nil do
        local outcome = queue[head]
        head, examined = head + 1, examined + 1
        if Combat.stillMeets(outcome, players) and Combat.apply(outcome, hours) then
            applied = applied + 1
        else
            metrics.dropped = metrics.dropped + 1
        end
    end
    local left = 0
    if queue[head] == nil then
        Combat.pending, Combat.pendingHead = {}, 1
    else
        Combat.pendingHead = head
        left = #queue - head + 1
        metrics.deferred = metrics.deferred + 1
    end
    if applied > 0 then
        emit("offline_fights", { squad = "-", fights = applied, pending = left,
            task = "fights=" .. applied .. " casualties=" .. (metrics.casualties - casualties)
                .. " wiped=" .. (metrics.wipes - wipes) .. " pending=" .. left })
    end
    return applied
end

function Combat.reset()
    Combat.pending, Combat.pendingHead, Combat.pendingStore = {}, 1, nil
    return true
end

local function rollsOf(n)
    local result = {}
    for index = 1, n do
        if type(Combat.adapters.roll) == "function" then result[index] = Combat.adapters.roll()
        elseif type(ZombRandFloat) == "function" then result[index] = ZombRandFloat(0, 1)
        else result[index] = math.random() end
    end
    return result
end

function Combat.tick(hours, players)

    if Combat.pending[Combat.pendingHead] ~= nil then return Combat.drain(hours, players) end
    local squads = {}
    Ledger.eachLive(function(q) squads[#squads + 1] = q end)
    if #squads < 2 then return 0 end

    local scores = {}
    local scorer = function(profileId)
        if profileId == nil then return Combat.weaponScore(primaryOf(nil)) end
        local score = scores[profileId]
        if score == nil then
            score = Combat.weaponScore(primaryOf(profileId))
            scores[profileId] = score
        end
        return score
    end
    Combat.pending, Combat.pendingHead = Combat.resolve(squads, hours, players or {}, rollsOf, scorer), 1
    Combat.pendingStore = Ledger.storage
    return Combat.drain(hours, players)
end

return Combat
