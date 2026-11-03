require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Records/ALifeRepIcons"
require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}

local Levels = ProjectALife.RepLevels
local Icons = ProjectALife.RepIcons
local Reputation = ProjectALife.Reputation
local Track = { ringSize = 16, metrics = { humans = 0, duplicates = 0, pvp = 0 } }
ProjectALife.RepTrack = Track

function Track.data(player, create)
    if player == nil or type(player) == "string" or type(player.getModData) ~= "function" then return nil end
    if create ~= true and type(player.hasModData) == "function" and player:hasModData() ~= true then return nil end
    local data = player:getModData()
    if type(data) ~= "table" then return nil end
    return data
end

function Track.reach(player, levelId)
    local index = Levels.indexOf(levelId)
    local data = Track.data(player, index ~= nil)
    local low, high
    if data ~= nil then low, high = tonumber(data.repReachedMin), tonumber(data.repReachedMax) end
    local newLow, newHigh = Icons.reach(low, high, index)
    if data ~= nil and (low ~= newLow or high ~= newHigh) then
        data.repReachedMin, data.repReachedMax = newLow, newHigh
    end
    return newLow, newHigh
end

function Track.humans(player)
    local data = Track.data(player, false)
    if data == nil then return 0 end
    return math.max(0, math.floor(tonumber(data.palHumansKilled) or 0))
end

function Track.tokenOf(actor)
    return tostring(actor.uid) .. ":" .. tostring(actor.generation)
end

function Track.noteHuman(killer, token)
    local data = Track.data(killer, true)
    if data == nil then return false, "no_player_data" end
    if token ~= nil then
        local ring = type(data.palHumanRing) == "table" and data.palHumanRing or {}
        for index = 1, #ring do
            if ring[index] == token then
                Track.metrics.duplicates = Track.metrics.duplicates + 1
                return false, "counted"
            end
        end
        ring[#ring + 1] = token
        while #ring > Track.ringSize do table.remove(ring, 1) end
        data.palHumanRing = ring
    end
    local total = Track.humans(killer) + 1
    data.palHumansKilled = total
    Track.metrics.humans = Track.metrics.humans + 1
    return true, total
end

function Track.livePlayer(killer, key)
    if killer ~= nil then return killer end
    local personal = ProjectALife.PersonalRep
    if type(key) == "string" and personal ~= nil and type(personal.playerFor) == "function" then
        return personal.playerFor(key)
    end
    return nil
end

function Track.refresh(player, force)
    local personal = ProjectALife.PersonalRep
    if force ~= true and personal ~= nil and personal.enabled == true then return false end
    if player == nil or type(Reputation.sync) ~= "function" then return false end
    local ok = pcall(Reputation.sync, player)
    return ok
end

function Track.onActorKilled(killer, actor, key)
    if type(actor) ~= "table" or actor.uid == nil then return false, "actor_required" end
    local live = Track.livePlayer(killer, key)
    local counted, total = Track.noteHuman(live, Track.tokenOf(actor))
    if counted then Track.refresh(live) end
    return counted, total
end

function Track.onPlayerDied(victim)
    local attribution = ProjectALife.KillAttribution
    if victim == nil or attribution == nil or type(attribution.classify) ~= "function"
            or type(victim.getAttackedBy) ~= "function" then return false, "not_applicable" end
    local victimKey = Reputation.playerKey(victim)
    if victimKey == nil then return false, "not_a_player" end
    local ok, attacker = pcall(victim.getAttackedBy, victim)
    if not ok or attacker == nil or attacker == victim then return false, "no_attacker" end
    local kind, _, _, _, killer = attribution.classify(attacker)
    if kind ~= "player" or killer == nil then return false, "not_pvp" end
    local hours = 0
    if type(victim.getHoursSurvived) == "function" then hours = math.floor((tonumber(victim:getHoursSurvived()) or 0) * 10) end
    local counted, total = Track.noteHuman(killer, "player:" .. victimKey .. ":" .. tostring(hours))
    if counted then
        Track.metrics.pvp = Track.metrics.pvp + 1
        Track.refresh(killer, true)
    end
    return counted, total
end

function Track.decorate(player, view)
    if type(view) ~= "table" then return view end
    if Levels.indexOf(view.level) ~= nil then
        view.reachedMin, view.reachedMax = Track.reach(player, view.level)
    end
    view.humans = Track.humans(player)
    return view
end

return Track
