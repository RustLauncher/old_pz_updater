require "radio/ISDynamicRadio"
require "ProjectALife/Talk/ALifeDialogueData"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Radio = {
    channelUUID = "PAL-KNOX-1993",
    settings = { enabled = true },
    metrics = { aired = 0, busy = 0, empty = 0, unavailable = 0 },
}
ProjectALife.KnoxRadio = Radio

function Radio.reset()
    Radio.settings = { enabled = true }
    Radio.metrics = { aired = 0, busy = 0, empty = 0, unavailable = 0 }
end

function Radio.frequency()
    local options = SandboxVars and SandboxVars.ALife
    local frequency = tonumber(options and options.Radio_KnoxFrequency) or 99600
    return math.max(88000, math.min(108000, math.floor(frequency)))
end

function Radio.enabled()
    if type(isClient) == "function" and isClient() then return false end
    if Radio.settings.enabled ~= true then return false end
    local options = SandboxVars and SandboxVars.ALife
    return options == nil or options.Radio_KnoxCounty ~= false
end

function Radio.state(time)
    local data = time:getModData()
    if type(data.ProjectALifeKnoxRadio_v1) ~= "table" then
        data.ProjectALifeKnoxRadio_v1 = { recent = {} }
    end
    local state = data.ProjectALifeKnoxRadio_v1
    if type(state.recent) ~= "table" then state.recent = {} end
    while #state.recent > 24 do table.remove(state.recent, 1) end
    return state
end

Radio.clockKeys = { date = true, time = true, weekday = true, day = true }
Radio.factKeys = { from = true, to = true, faction = true, group = true, count = true, town = true, den = true }

function Radio.townOf(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" or tonumber(x) == nil then return nil end
    local distance, town = regions.distanceToTown({ x = tonumber(x), y = tonumber(y) })
    if town == nil or (tonumber(distance) or math.huge) > 600 then return nil end
    return town.label
end

function Radio.factionLabel(id)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(id) or nil
    local name = faction and faction.general and faction.general.name or nil
    if name == nil or tostring(name) == "" then return nil end
    return tostring(name)
end

function Radio.squadFact(squad, graph)
    local task = type(squad.task) == "table" and squad.task or {}
    if (task.kind ~= "travel" and task.kind ~= "reinforce") or task.dest == nil then return nil end
    local node = graph ~= nil and type(graph.nodes) == "table" and graph.nodes[task.dest] or nil
    local from = Radio.townOf(squad.x, squad.y)
    local to = node ~= nil and (Radio.townOf(node.x, node.y) or node.name) or nil
    local faction = Radio.factionLabel(squad.factionId)
    if from == nil or to == nil or tostring(to) == from or faction == nil then return nil end
    local count = type(squad.members) == "table" and #squad.members or tonumber(squad.size)
    return { from = from, to = tostring(to), faction = faction, group = faction,
        count = count and count > 0 and tostring(count) or nil, town = from }
end

function Radio.facts()
    local facts = {}
    pcall(function()
        local ledger, graph = ProjectALife.SquadLedger, ProjectALife.RoadGraph
        if ledger == nil then return end
        local function visit(squad)
            local fact = Radio.squadFact(squad, graph)
            if fact ~= nil then facts[#facts + 1] = fact end
        end

        if type(ledger.eachLive) == "function" then ledger.eachLive(visit)
        elseif type(ledger.list) == "function" then
            for _, squad in ipairs(ledger.list()) do visit(squad) end
        end
    end)
    pcall(function()
        local sites = ProjectALife.OutpostRegistry
        if sites == nil or type(sites.list) ~= "function" then return end
        for _, site in ipairs(sites.list()) do
            local town, faction = Radio.townOf(site.x, site.y), Radio.factionLabel(site.factionId)
            if town ~= nil and faction ~= nil then facts[#facts + 1] = { faction = faction, group = faction, town = town } end
        end
    end)
    pcall(function()
        local rumors = ProjectALife.Rumors
        local state = rumors ~= nil and type(rumors.store) == "function" and rumors.store() or nil
        for _, den in ipairs(state and state.dens or {}) do
            if den.where ~= nil then facts[#facts + 1] = { den = den.where, town = den.town } end
        end
    end)
    return facts
end

function Radio.bind(segment, facts)
    local needs, factNeeded = {}, false
    for _, line in ipairs(segment.lines or {}) do
        for _, text in ipairs({ tostring(line.t or ""), tostring(line.sp or "") }) do
            for key in string.gmatch(text, "{([a-z]+)}") do
                if Radio.factKeys[key] then needs[key] = true; factNeeded = true
                elseif not Radio.clockKeys[key] then return nil end
            end
            if string.find(string.gsub(text, "{[a-z]+}", ""), "[{}]") then return nil end
        end
    end
    if not factNeeded then return {} end
    local list = type(facts) == "table" and facts or {}
    if #list == 0 then return nil end
    local start = type(ZombRand) == "function" and ZombRand(#list) or 0
    for step = 0, #list - 1 do
        local fact = list[(start + step) % #list + 1]
        local fits = true
        for key in pairs(needs) do
            if fact[key] == nil then fits = false; break end
        end
        if fits then
            local vars = {}
            for key, value in pairs(fact) do vars[key] = value end
            return vars
        end
    end
    return nil
end

function Radio.eligible(segment, day, hour, facts)
    if not ProjectALife.DialogueData.allows({ day = segment.day, hour = segment.hour }, { day = day, hour = hour }) then
        return false
    end
    if type(segment.lines) ~= "table" or #segment.lines == 0 then return false end
    return Radio.bind(segment, facts) ~= nil
end

function Radio.pick(day, hour, state, facts)
    local data = ProjectALife.DialogueData
    if not data.load() then return nil end
    if type(data.needDay) == "function" then data.needDay(day) end
    local recent, candidates = {}, {}
    for index, id in ipairs(state.recent) do recent[id] = index end
    local oldest = nil
    for _, segment in ipairs(data.segments) do
        if Radio.eligible(segment, day, hour, facts) then
            if recent[segment.id] == nil then
                candidates[#candidates + 1] = segment
            elseif oldest == nil or recent[segment.id] < recent[oldest.id] then
                oldest = segment
            end
        end
    end

    if #candidates == 0 then return oldest end
    local total = 0
    for _, segment in ipairs(candidates) do total = total + segment.weight end
    local roll = ZombRand(total)
    for _, segment in ipairs(candidates) do
        roll = roll - segment.weight
        if roll < 0 then return segment end
    end
    return candidates[#candidates]
end

function Radio.OnEveryHour(channel, time)
    if not Radio.enabled() or channel == nil then return end
    local day, hour = time:getNightsSurvived(), time:getHour()
    local state = Radio.state(time)
    local slot = day * 24 + hour
    if state.lastSlot == slot then return end
    if channel:getAiringBroadcast() ~= nil then
        Radio.metrics.busy = Radio.metrics.busy + 1
        return
    end
    local personal = ProjectALife.PersonalRep
    if personal ~= nil and type(personal.nextMention) == "function" and type(time.getWorldAgeHours) == "function" then
        local mention = personal.nextMention(time:getWorldAgeHours())
        if mention ~= nil then
            local aired = RadioBroadCast.new(Radio.channelUUID .. "-m" .. tostring(slot), -1, -1)
            aired:AddRadioLine(RadioLine.new("Knox County Radio: " .. mention, 0.85, 0.9, 0.8))
            channel:setAiringBroadcast(aired)
            state.lastSlot = slot
            Radio.metrics.aired = Radio.metrics.aired + 1
            Radio.metrics.mentions = (Radio.metrics.mentions or 0) + 1
            return
        end
    end
    local facts = Radio.facts()
    local segment = Radio.pick(day, hour, state, facts)
    if segment == nil then
        Radio.metrics.empty = Radio.metrics.empty + 1
        return
    end

    local vars = Radio.bind(segment, facts) or {}
    local speech = ProjectALife.Speech
    local function fill(text)
        if speech == nil or type(speech.render) ~= "function" or not string.find(text, "{", 1, true) then return text end
        return speech.render(text, vars) or text
    end
    local broadcast = RadioBroadCast.new(Radio.channelUUID .. "-" .. tostring(slot), -1, -1)
    for _, line in ipairs(segment.lines) do
        broadcast:AddRadioLine(RadioLine.new(fill(line.sp) .. ": " .. fill(line.t), 0.85, 0.9, 0.8))
    end
    channel:setAiringBroadcast(broadcast)
    state.lastSlot = slot

    for index = #state.recent, 1, -1 do
        if state.recent[index] == segment.id then table.remove(state.recent, index) end
    end
    state.recent[#state.recent + 1] = segment.id
    while #state.recent > 24 do table.remove(state.recent, 1) end
    Radio.metrics.aired = Radio.metrics.aired + 1
end

function Radio.register()
    if type(isClient) == "function" and isClient() then return end

    for index = #DynamicRadio.channels, 1, -1 do
        if DynamicRadio.channels[index].uuid == Radio.channelUUID then
            table.remove(DynamicRadio.channels, index)
        end
    end
    for index, script in ipairs(DynamicRadio.scripts) do
        if script.channelUUID == Radio.channelUUID then
            DynamicRadio.scripts[index] = Radio
            return
        end
    end
    table.insert(DynamicRadio.scripts, Radio)
end

Radio.register()

function Radio.start()
    if not Radio.enabled() then return end
    local channel = Radio.channel
    if channel ~= nil and type(getGameTime) == "function" then Radio.OnEveryHour(channel, getGameTime()) end
end

function Radio.load(manager)
    Radio.channel = nil
    DynamicRadio.cache[Radio.channelUUID] = nil
    if not Radio.enabled() or manager == nil then return false end
    local frequency = Radio.frequency()
    local channel = manager:getRadioChannel(Radio.channelUUID)
    if channel == nil then
        local candidate = DynamicRadioChannel.new("Knox County Radio", frequency,
            ChannelCategory.Radio, Radio.channelUUID)
        manager:AddChannel(candidate, false)
        channel = manager:getRadioChannel(Radio.channelUUID)
    end

    if channel == nil or channel:GetFrequency() ~= frequency then
        Radio.metrics.unavailable = Radio.metrics.unavailable + 1
        print("[ALIFE-RADIO] Could not register Knox County Radio at " .. tostring(frequency / 1000)
            .. " MHz; the frequency may be occupied. Choose an unused ALife.Radio_KnoxFrequency and restart the server.")
        return false
    end
    Radio.channel = channel
    DynamicRadio.cache[Radio.channelUUID] = channel
    Radio.start()
    return true
end

if type(Events) == "table" then
    if Events.OnLoadRadioScripts ~= nil then Events.OnLoadRadioScripts.Add(Radio.load) end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(Radio.start) end
end
return Radio
