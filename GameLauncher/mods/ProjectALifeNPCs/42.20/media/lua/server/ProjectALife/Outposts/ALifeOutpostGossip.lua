require "ProjectALife/Core/ALifeTelemetry"

ProjectALife = ProjectALife or {}

local Chatter = {
    adapters = {},
    settings = {

        beatMs = 4000,

        playerRadius = 60,

        candidateCap = 12,
    },

    topics = {
        guard = "outpost_guard", gate = "outpost_guard", tower = "outpost_guard",
        roof = "outpost_guard", window = "outpost_guard", sniper = "outpost_guard",
        patrol = "outpost_guard", squad = "outpost_guard",
        farm = "outpost_farm", work = "outpost_farm",
        mechanic = "outpost_mechanic",
        sit = "outpost_fire", eat = "outpost_fire", drink = "outpost_fire",
        guitar = "outpost_fire", rest = "outpost_fire", fire = "outpost_fire",
        medic = "outpost_medic", healer = "outpost_medic",
    },
    state = { nextBeatMs = 0, cursor = 0 },
    metrics = { attempts = 0, started = 0, refused = 0 },
}
ProjectALife.OutpostGossip = Chatter

local function nowMs()
    if type(Chatter.adapters.nowMs) == "function" then
        return math.floor(tonumber(Chatter.adapters.nowMs()) or 0)
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Chatter.topicFor(stanceRole)
    local role = tostring(stanceRole or "")
    return Chatter.topics[role] or "any"
end

Chatter.siteTopics = { bridge_checkpoint = "checkpoint" }

function Chatter.siteTopicFor(site, stanceRole)
    local topic = Chatter.topicFor(stanceRole)
    local own = type(site) == "table" and Chatter.siteTopics[tostring(site.presetId or "")] or nil
    if own ~= nil and topic == "outpost_guard" then return own end
    return topic
end

function Chatter.resident(record, siteId)
    if type(record) ~= "table" or record.lifecycle ~= "active" then return false end
    local memory = type(record.memory) == "table" and record.memory or {}
    return memory.outpostId == siteId and memory.outpostSquadId == nil
end

local function shellFor(uid)
    local watchdog = Chatter.adapters.watchdog or ProjectALife.Watchdog
    local bindings = watchdog ~= nil and watchdog.bindings or nil
    local binding = bindings ~= nil and bindings[uid] or nil
    if binding ~= nil then return binding.shell end
    return ProjectALife.Talk and ProjectALife.Talk.shellFor(uid) or nil
end

function Chatter.speakAt(site, players, now)
    if type(site) ~= "table" or site.state ~= "garrisoned" then return false end
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.tryStart) ~= "function" then return false end
    local actors = Chatter.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.list) ~= "function" then return false end

    local near = false
    for _, player in ipairs(players or {}) do
        local dx, dy = site.x - player.x, site.y - player.y
        if dx * dx + dy * dy <= Chatter.settings.playerRadius * Chatter.settings.playerRadius then
            near = true
            break
        end
    end
    if not near then return false end
    local ids, candidates = {}, {}
    local function collect(record)
        if Chatter.resident(record, site.id) then ids[#ids + 1] = record.uid end
    end
    if actors.each then actors.each(collect) else
        for _, record in ipairs(actors.list()) do collect(record) end
    end
    if #ids < 2 then return false end
    local first = Chatter.state.cursor % #ids
    for offset = 0, math.min(#ids, Chatter.settings.candidateCap) - 1 do
        local id = ids[(first + offset) % #ids + 1]
        if actors.read then candidates[#candidates + 1] = actors.read(id) else
            for _, record in ipairs(actors.list()) do if record.uid == id then candidates[#candidates + 1] = record; break end end
        end
    end

    local start = (Chatter.state.cursor % #candidates) + 1
    Chatter.state.cursor = Chatter.state.cursor + 1
    for offset = 0, #candidates - 1 do
        local record = candidates[((start + offset - 1) % #candidates) + 1]
        local shell = shellFor(record.uid)
        local memory = type(record.memory) == "table" and record.memory or {}
        if shell ~= nil then
            Chatter.metrics.attempts = Chatter.metrics.attempts + 1
            local ok = gossip.tryStart(shell, {
                context = "ambient",
                groupId = memory.groupId or ("outpost:" .. tostring(site.id)),
                topic = Chatter.siteTopicFor(site, memory.stanceRole),
                now = now,
            })
            if ok then
                Chatter.metrics.started = Chatter.metrics.started + 1
                return true
            end
            Chatter.metrics.refused = Chatter.metrics.refused + 1
        end
    end
    return false
end

Chatter.encounterTopics = { car_crash = "crash_talk", broken_car = "breakdown_talk" }

function Chatter.encounterTopicFor(encounterId)
    return Chatter.encounterTopics[tostring(encounterId or "")]
end

function Chatter.roadTopic(memory)
    if type(memory) ~= "table" then return nil end
    return Chatter.encounterTopicFor(memory.encounterKind or memory.encounter)
end

function Chatter.speakOnTheRoad(players, now)
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.tryStart) ~= "function" then return false end
    local actors = Chatter.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.list) ~= "function" then return false end
    local candidates = {}
    for _, record in ipairs(actors.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        if record.lifecycle == "active" and memory.outpostId == nil
                and Chatter.roadTopic(memory) ~= nil
                and type(memory.groupId) == "string" then
            candidates[#candidates + 1] = record
            if #candidates >= Chatter.settings.candidateCap then break end
        end
    end
    if #candidates < 2 then return false end
    local start = (Chatter.state.cursor % #candidates) + 1
    Chatter.state.cursor = Chatter.state.cursor + 1
    for offset = 0, #candidates - 1 do
        local record = candidates[((start + offset - 1) % #candidates) + 1]
        local memory = record.memory
        local near = false
        local p = record.worldPosition
        for _, player in ipairs(players or {}) do
            if p ~= nil and (p.x - player.x) ^ 2 + (p.y - player.y) ^ 2
                    <= Chatter.settings.playerRadius * Chatter.settings.playerRadius then
                near = true
                break
            end
        end
        local shell = near and shellFor(record.uid) or nil
        if shell ~= nil then
            Chatter.metrics.attempts = Chatter.metrics.attempts + 1
            local ok = gossip.tryStart(shell, {
                context = "ambient", groupId = memory.groupId,
                topic = Chatter.roadTopic(memory), now = now,
            })
            if ok then
                Chatter.metrics.started = Chatter.metrics.started + 1
                Chatter.metrics.roadside = (Chatter.metrics.roadside or 0) + 1
                return true
            end
            Chatter.metrics.refused = Chatter.metrics.refused + 1
        end
    end
    return false
end

function Chatter.tick(sites, players)
    local now = nowMs()
    if now < Chatter.state.nextBeatMs then return false end
    Chatter.state.nextBeatMs = now + Chatter.settings.beatMs
    Chatter.state.beat = (Chatter.state.beat or 0) + 1
    if Chatter.state.beat % 2 == 0 then
        local spoke = false
        pcall(function() spoke = Chatter.speakOnTheRoad(players, now) == true end)
        return spoke
    end
    if type(sites) ~= "table" or #sites == 0 then return false end
    local garrisoned = {}
    for _, site in ipairs(sites) do
        if site.state == "garrisoned" then garrisoned[#garrisoned + 1] = site end
    end
    if #garrisoned == 0 then return false end
    local index = (Chatter.state.cursor % #garrisoned) + 1
    local spoke = false
    pcall(function() spoke = Chatter.speakAt(garrisoned[index], players, now) == true end)
    return spoke
end

function Chatter.configure(adapters)
    Chatter.adapters = adapters or {}
    Chatter.state = { nextBeatMs = 0, cursor = 0 }
    Chatter.metrics = { attempts = 0, started = 0, refused = 0 }
    return true
end

return Chatter
