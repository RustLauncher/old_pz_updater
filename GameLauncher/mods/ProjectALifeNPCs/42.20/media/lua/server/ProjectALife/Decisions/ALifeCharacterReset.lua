require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Core/ALifePlayerLocator"

ProjectALife = ProjectALife or {}
if ProjectALife.CharacterReset then return ProjectALife.CharacterReset end

local Reputation = ProjectALife.Reputation
local Gate = ProjectALife.FeatureGate
local PlayerLocator = ProjectALife.PlayerLocator

local Reset = {
    TAG = "ProjectALife.Characters.v1",
    SCHEMA = 1,
    option = "Reputation_ResetOnNewCharacter",
    freshHours = 1,
    backwardHours = 0.25,
    shieldMs = 120000,
    sliceBudget = 256,
    adapters = {},
    storage = nil,
    dirty = false,
    jobs = {},
    shield = {},
    mapFields = { "hostileToPlayerKeys", "carefulPlayerKeys", "tolerateUntil", "robberyTruce", "opinion", "social",
        "recognized", "engagedAt", "hitByAt", "fairOpened" },
    metrics = { checked = 0, idsIssued = 0, newCharacters = 0, repCleared = 0, standingCleared = 0,
        personalRenewed = 0, actorsScrubbed = 0, keysCleared = 0, jobsOpen = 0, disabled = 0, lastKey = nil },
}
ProjectALife.CharacterReset = Reset

local function nowMs()
    if type(Reset.adapters.nowMs) == "function" then return tonumber(Reset.adapters.nowMs()) or 0 end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Reset.enabled()
    return Gate.flag(Reset.option, true)
end

function Reset.authoritative()
    local value = Reset.adapters.authoritative
    if type(value) == "function" then return value() == true end
    if value ~= nil then return value == true end
    return not (type(isClient) == "function" and isClient()
        and (type(isServer) ~= "function" or not isServer()))
end

function Reset.store()
    if Reset.storage ~= nil then return Reset.storage end
    local state
    if type(Reset.adapters.getOrCreate) == "function" then
        state = Reset.adapters.getOrCreate(Reset.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        state = ModData.getOrCreate(Reset.TAG)
    end
    if type(state) ~= "table" then return nil, "mod_data_unavailable" end
    if state.schema == nil then
        state.schema, state.chars = Reset.SCHEMA, {}
        Reset.dirty = true
    elseif state.schema ~= Reset.SCHEMA then
        return nil, "characters_schema_unsupported"
    end
    if type(state.chars) ~= "table" then state.chars = {} end
    Reset.storage = state
    return state
end

function Reset.hoursOf(player)
    if player == nil or type(player) == "string" or type(player.getHoursSurvived) ~= "function" then return nil end
    local ok, hours = pcall(player.getHoursSurvived, player)
    hours = ok and tonumber(hours) or nil
    if hours == nil or hours ~= hours then return nil end
    return hours
end

function Reset.newId(key)
    local roll = type(ZombRand) == "function" and ZombRand(1000000) or 0
    return tostring(key) .. ":" .. tostring(nowMs()) .. ":" .. tostring(roll)
end

function Reset.dataOf(player)
    if player == nil or type(player) == "string" or type(player.getModData) ~= "function" then return nil end
    local ok, data = pcall(player.getModData, player)
    if ok and type(data) == "table" then return data end
    return nil
end

function Reset.strip(map)
    if type(map) ~= "table" then return map end
    local now = nowMs()
    for key, stamp in pairs(Reset.shield) do
        if now - stamp > Reset.shieldMs or now < stamp then
            Reset.shield[key] = nil
        elseif map[key] ~= nil then
            map[key] = nil
        end
    end
    return map
end

function Reset.scrubRecord(record, key)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) ~= "table" then return 0 end
    local found = 0
    for _, field in ipairs(Reset.mapFields) do
        local map = memory[field]
        if type(map) == "table" and map[key] ~= nil then found = found + 1 end
    end
    return found
end

function Reset.scrub(uid, key)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then return 0 end
    local record = registry.read(uid)
    if Reset.scrubRecord(record, key) == 0 then return 0 end
    local cleared = 0
    local updated = registry.update(record.uid, record.revision, function(row)
        local memory = type(row.memory) == "table" and row.memory or nil
        if memory == nil then return end
        for _, field in ipairs(Reset.mapFields) do
            local map = memory[field]
            if type(map) == "table" and map[key] ~= nil then
                map[key] = nil
                cleared = cleared + 1
            end
        end
    end)
    if updated == nil then return 0 end
    Reset.metrics.actorsScrubbed = Reset.metrics.actorsScrubbed + 1
    Reset.metrics.keysCleared = Reset.metrics.keysCleared + cleared
    return cleared
end

function Reset.tick(budget)
    budget = math.max(1, math.floor(tonumber(budget) or Reset.sliceBudget))
    local spent = 0
    for key, job in pairs(Reset.jobs) do
        while spent < budget and job.index <= #job.uids do
            local uid = job.uids[job.index]
            job.index = job.index + 1
            spent = spent + 1
            pcall(Reset.scrub, uid, key)
        end
        if job.index > #job.uids then
            Reset.jobs[key] = nil
            Reset.metrics.jobsOpen = math.max(0, Reset.metrics.jobsOpen - 1)
        end
        if spent >= budget then break end
    end
    return spent
end

function Reset.queue(key)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    local uids = {}
    registry.each(function(record)
        if Reset.scrubRecord(record, key) > 0 then uids[#uids + 1] = record.uid end
        return false
    end)
    if #uids == 0 then return 0 end
    if Reset.jobs[key] == nil then Reset.metrics.jobsOpen = Reset.metrics.jobsOpen + 1 end
    Reset.jobs[key] = { uids = uids, index = 1 }
    return #uids
end

function Reset.forget(key, player)
    local metrics = Reset.metrics
    if Reputation ~= nil and type(Reputation.forgetPlayer) == "function" then
        local ok, cleared = pcall(Reputation.forgetPlayer, key)
        if ok and cleared == true then metrics.repCleared = metrics.repCleared + 1 end
    end
    local standing = ProjectALife.Standing
    if standing ~= nil and type(standing.forgetPlayer) == "function" then
        local ok, cleared = pcall(standing.forgetPlayer, key)
        if ok and cleared == true then metrics.standingCleared = metrics.standingCleared + 1 end
    end
    local personal = ProjectALife.PersonalRep
    if personal ~= nil and type(personal.forgetPlayer) == "function" then
        local ok, cleared = pcall(personal.forgetPlayer, key)
        if ok and cleared == true then metrics.personalRenewed = metrics.personalRenewed + 1 end
    end
    Reset.shield[key] = nowMs()
    pcall(Reset.queue, key)
    Reset.tick(Reset.sliceBudget)
    metrics.newCharacters = metrics.newCharacters + 1
    metrics.lastKey = key
    return true
end

function Reset.check(player)
    if not Reset.authoritative() then return false, "server_authority_required" end
    if not Reset.enabled() then
        Reset.metrics.disabled = Reset.metrics.disabled + 1
        return false, "disabled"
    end
    local key = Reputation ~= nil and Reputation.playerKey(player) or nil
    if key == nil then return false, "player_required" end
    local data = Reset.dataOf(player)
    if data == nil then return false, "no_mod_data" end
    local state, why = Reset.store()
    if state == nil then return false, why end
    local metrics = Reset.metrics
    metrics.checked = metrics.checked + 1
    local row = state.chars[key]
    if type(row) ~= "table" then row = nil end
    local hours = Reset.hoursOf(player)
    local mine = type(data.ProjectALifeCharId) == "string" and data.ProjectALifeCharId or nil
    local fresh = false
    if mine == nil then
        mine = Reset.newId(key)
        data.ProjectALifeCharId = mine
        metrics.idsIssued = metrics.idsIssued + 1
        if row == nil then
            fresh = hours ~= nil and hours < Reset.freshHours
        else
            fresh = row.dead == true
                or (hours ~= nil and tonumber(row.hours) ~= nil and hours + Reset.backwardHours < tonumber(row.hours))
        end
    elseif row ~= nil and row.id ~= mine then
        fresh = row.dead == true
            or (hours ~= nil and tonumber(row.hours) ~= nil and hours + Reset.backwardHours < tonumber(row.hours))
    end
    local keep = hours
    if row ~= nil and not fresh and tonumber(row.hours) ~= nil and (keep == nil or row.hours > keep) then keep = row.hours end
    state.chars[key] = { id = mine, hours = keep, dead = false }
    Reset.dirty = true
    if fresh then Reset.forget(key, player) end
    return fresh == true, fresh and "new_character" or "same_character"
end

function Reset.checkAll()
    if not Reset.authoritative() then return 0 end
    local count = 0
    for _, player in ipairs(PlayerLocator.list(Reset.adapters.players)) do
        local ok, fresh = pcall(Reset.check, player)
        if ok and fresh == true then count = count + 1 end
    end
    Reset.tick(Reset.sliceBudget)
    return count
end

function Reset.onPlayerDied(player)
    if not Reset.authoritative() then return false, "server_authority_required" end
    local key = Reputation ~= nil and Reputation.playerKey(player) or nil
    if key == nil then return false, "player_required" end
    local state = Reset.store()
    if state == nil then return false, "store_unavailable" end
    local row = state.chars[key]
    if type(row) ~= "table" then return false, "no_row" end
    row.dead = true
    Reset.dirty = true
    return true
end

function Reset.reset()
    Reset.storage, Reset.dirty, Reset.jobs, Reset.shield = nil, false, {}, {}
    Reset.metrics = { checked = 0, idsIssued = 0, newCharacters = 0, repCleared = 0, standingCleared = 0,
        personalRenewed = 0, actorsScrubbed = 0, keysCleared = 0, jobsOpen = 0, disabled = 0, lastKey = nil }
end

return Reset
