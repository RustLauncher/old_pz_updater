ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/Data/ALifeDialogueIndex"
require "ProjectALife/Shells/ALifeWounds"

local Data = {
    loaded = false,
    barks = {},
    scenes = {},
    scenesByTopic = {},
    sceneById = {},
    replies = {},
    yesPools = {},
    noPools = {},
    intents = {},
    intentById = {},
    segments = {},
    segmentsByKind = {},
    segmentById = {},
    gates = {},
    counts = { barks = 0, scenes = 0, turns = 0, replies = 0, intents = 0, patterns = 0, segments = 0, radioLines = 0 },
    errors = {},
}
ProjectALife.DialogueData = Data

local LIST_FIELDS = { reg = true, role = true, tmp = true, st = true, rep = true, r1 = true, r2 = true, r3 = true, world = true }

Data.poolFields = { barks = "barks", replies = "replies", yes = "yesPools", no = "noPools" }
Data.indexMin = 48
Data.streamGapMs = 1500
Data.anyFirst = 2

function Data.parseGate(text)
    text = tostring(text or "")
    local cached = Data.gates[text]
    if cached ~= nil then return cached end
    local gate = {}
    for part in string.gmatch(text, "[^|]+") do
        local key, value = string.match(part, "^([a-z0-9]+)=(.*)$")
        if key ~= nil then
            if LIST_FIELDS[key] then
                local set = {}
                for item in string.gmatch(value, "[^,]+") do set[item] = true end
                gate[key] = set
            elseif key == "day" or key == "hour" then
                local a, b = string.match(value, "^(%d+),(%d+)$")
                if a ~= nil then gate[key] = { tonumber(a), tonumber(b) } end
            else
                gate[key] = value
            end
        end
    end
    Data.gates[text] = gate
    return gate
end

function Data.worldOf(context)
    local world = context.world
    local facts = ProjectALife.WorldFacts
    if context.worldUid == nil or facts == nil or type(facts.read) ~= "function" then
        if type(world) ~= "table" then world = {}; context.world = world end
        return world
    end
    local now = facts.nowMs()
    if type(world) == "table" and now - (context.worldAtMs or 0) < 1000 then return world end
    local read = facts.read(context.worldUid)
    world = type(read) == "table" and read or {}
    context.world, context.worldAtMs = world, now
    return world
end

function Data.allows(gate, context)
    if type(gate) ~= "table" then return true end
    context = type(context) == "table" and context or {}
    if gate.reg ~= nil and (context.register == nil or gate.reg[context.register] ~= true) then return false end
    if gate.role ~= nil and (context.role == nil or gate.role[context.role] ~= true) then return false end
    if gate.tmp ~= nil and (context.temperament == nil or gate.tmp[context.temperament] ~= true) then return false end
    if gate.st ~= nil and (context.stance == nil or gate.st[context.stance] ~= true) then return false end
    if gate.rep ~= nil then
        local accepted = false
        for _, tier in ipairs(type(context.repTiers) == "table" and context.repTiers or {}) do
            if gate.rep[tier] == true then accepted = true; break end
        end
        if not accepted then return false end
    end
    if gate.sex ~= nil and gate.sex ~= context.sex then return false end
    if gate.psex ~= nil and gate.psex ~= (context.psex or "m") then return false end
    if gate.fact ~= nil and (type(context.facts) ~= "table" or context.facts[gate.fact] ~= true) then return false end
    if gate.world ~= nil then
        local world = Data.worldOf(context)
        for tag in pairs(gate.world) do
            if world[tag] ~= true then return false end
        end
    end
    if gate.day ~= nil then
        local day = tonumber(context.day)
        if day == nil or day < gate.day[1] or day > gate.day[2] then return false end
    end
    if gate.hour ~= nil then
        local hour, from, to = tonumber(context.hour), gate.hour[1], gate.hour[2]
        if hour == nil then return false end
        if from <= to then
            if hour < from or hour > to then return false end
        elseif hour < from and hour > to then
            return false
        end
    end
    if context.mood ~= nil and gate.mood ~= nil and gate.mood ~= context.mood then return false end
    return true
end

function Data.specificity(gate)
    if type(gate) ~= "table" then return 1 end
    local weight = 1
    if gate.role ~= nil then weight = weight * 3 end
    if gate.tmp ~= nil then weight = weight * 2 end
    if gate.st ~= nil then weight = weight * 1.5 end
    if gate.day ~= nil then weight = weight * 1.5 end
    return weight
end

local function append(map, key, record)
    local list = map[key]
    if list == nil then list = {}; map[key] = list end
    list[#list + 1] = record
end

Data.attackEvents = { HURT = true, HIT_BY_PLAYER = true, HIT_BY_PLAYER_AGAIN = true, MATE_HIT_BY_PLAYER = true,
    PLEAD = true, SURRENDER = true, RETREAT = true, PANIC = true }

function Data.attackOf(event, text)
    if not Data.attackEvents[event] then return nil end
    return ProjectALife.Wounds.textAttack(text)
end

function Data.bark(event, text, gate, weight)
    append(Data.barks, event, { t = text, g = Data.parseGate(gate), w = tonumber(weight) or 1,
        a = Data.attackOf(event, text) })
    Data.counts.barks = Data.counts.barks + 1
end

Data.askedTopics = {
    any = true, patrol_departure = true, rest = true, scavenge = true, after_fight = true,
    outpost_guard = true, outpost_farm = true, outpost_mechanic = true, outpost_fire = true,
    outpost_medic = true, checkpoint = true, crash_talk = true, breakdown_talk = true, meet = true,
    plan = true, shelter = true, walk = true, panic_days = true, fishing = true,
}

function Data.scene(id, topic, minimum, gate, ...)
    local args = { ... }
    local turns = {}
    local index = 1
    while index + 1 <= #args do
        turns[#turns + 1] = { s = tonumber(args[index]) or 1, t = args[index + 1] }
        index = index + 2
    end
    local scene = { id = id, topic = topic, min = tonumber(minimum) or 1, g = Data.parseGate(gate), turns = turns }
    Data.scenes[#Data.scenes + 1] = scene
    append(Data.scenesByTopic, topic, scene)
    if not Data.askedTopics[topic] then append(Data.scenesByTopic, "any", scene) end
    Data.sceneById[id] = scene
    Data.counts.scenes = Data.counts.scenes + 1
    Data.counts.turns = Data.counts.turns + #turns
end

function Data.reply(intent, text, gate, ask, beats)
    append(Data.replies, intent, { t = text, g = Data.parseGate(gate), ask = ask, beats = beats })
    Data.counts.replies = Data.counts.replies + 1 + (type(beats) == "table" and #beats or 0)
end

function Data.yes(intent, text, gate)
    append(Data.yesPools, intent, { t = text, g = Data.parseGate(gate) })
    Data.counts.replies = Data.counts.replies + 1
end

function Data.no(intent, text, gate)
    append(Data.noPools, intent, { t = text, g = Data.parseGate(gate) })
    Data.counts.replies = Data.counts.replies + 1
end

local function groups(text)
    local result = {}
    for group in string.gmatch(tostring(text or ""), "[^;]+") do
        local words = {}
        for word in string.gmatch(group, "[^,]+") do words[#words + 1] = word end
        if #words > 0 then result[#result + 1] = words end
    end
    return result
end

function Data.intent(id, priority, patterns, keywords)
    local entry = Data.intentById[id]
    if entry == nil then
        entry = { id = id, priority = tonumber(priority) or 50, patterns = {}, all = {}, none = {} }
        Data.intentById[id] = entry
        Data.intents[#Data.intents + 1] = entry
        Data.counts.intents = Data.counts.intents + 1
    end
    for pattern in string.gmatch(tostring(patterns or ""), "[^|]+") do
        entry.patterns[#entry.patterns + 1] = pattern
        Data.counts.patterns = Data.counts.patterns + 1
    end
    for part in string.gmatch(tostring(keywords or ""), "[^|]+") do
        local key, value = string.match(part, "^([a-z0-9]+)=(.*)$")
        if key == "all" then
            for _, group in ipairs(groups(value)) do entry.all[#entry.all + 1] = group end
        elseif key == "none" then
            for _, group in ipairs(groups(value)) do entry.none[#entry.none + 1] = group end
        end
    end
end

function Data.registerIntentRows(rows)
    for r = 1, #rows do
        local row = rows[r]
        local entry = Data.intentById[row[1]]
        if entry == nil then
            entry = { id = row[1], priority = tonumber(row[2]) or 50, patterns = {}, all = {}, none = {} }
            Data.intentById[row[1]] = entry
            Data.intents[#Data.intents + 1] = entry
            Data.counts.intents = Data.counts.intents + 1
        end
        local patterns = row[3]
        for i = 1, #patterns do entry.patterns[#entry.patterns + 1] = patterns[i] end
        Data.counts.patterns = Data.counts.patterns + #patterns
        for _, group in ipairs(row[4] or {}) do entry.all[#entry.all + 1] = group end
        for _, group in ipairs(row[5] or {}) do entry.none[#entry.none + 1] = group end
    end
end

function Data.segment(id, kind, dayMin, dayMax, hourFrom, hourTo, weight, ...)
    local args = { ... }
    local lines = {}
    local index = 1
    while index + 1 <= #args do
        lines[#lines + 1] = { sp = args[index], t = args[index + 1] }
        index = index + 2
    end
    local segment = {
        id = id, kind = kind, day = { tonumber(dayMin) or 0, tonumber(dayMax) or 9999 },
        hour = { tonumber(hourFrom) or 0, tonumber(hourTo) or 23 }, weight = tonumber(weight) or 1, lines = lines,
    }
    Data.segments[#Data.segments + 1] = segment
    append(Data.segmentsByKind, kind, segment)
    Data.segmentById[id] = segment
    Data.counts.segments = Data.counts.segments + 1
    Data.counts.radioLines = Data.counts.radioLines + #lines
end

function Data.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Data.shardList(kind, key)
    local index = Data.index
    local map = index ~= nil and index[kind] or nil
    local entry = map ~= nil and map[key] or nil
    if type(entry) == "string" then return { entry } end
    return entry
end

function Data.rowsOf(id)
    local store = ProjectALife.DialogueShards
    local rows = store ~= nil and store[id] or nil
    if rows == nil then
        require("ProjectALife/Talk/Data/ALifeDialogue_" .. tostring(id))
        store = ProjectALife.DialogueShards
        rows = store ~= nil and store[id] or nil
    end
    if type(rows) ~= "table" then error("shard_missing") end
    return rows
end

function Data.registerPoolRows(pools, rows)
    for r = 1, #rows do
        local row = rows[r]
        local key = row[1]
        local list = pools[key]
        if list == nil then list = {}; pools[key] = list end
        local gate = Data.parseGate(row[2])
        local texts, weights, asks, beats, kinds = row[3], row[4], row[5], row[6], row[7]
        local size = #list
        for i = 1, #texts do
            local record = { t = texts[i], g = gate, w = 1 }
            if weights then record.w = weights[i] or 1 end
            if asks then record.ask = asks[i] end
            if beats then record.beats = beats[i] end
            if kinds then record.a = kinds[i] end
            size = size + 1
            list[size] = record
        end
    end
end

function Data.loadShard(kind, id)
    if Data.shardDone[id] then return true end
    Data.shardDone[id] = true
    local ok, err = pcall(function()
        Data.registerPoolRows(Data[Data.poolFields[kind]], Data.rowsOf(id))
    end)
    if not ok then
        Data.errors[#Data.errors + 1] = tostring(id) .. ":" .. tostring(err)
        return false
    end
    return true
end

function Data.openPool(kind, pools, key)
    if key == nil then return nil end
    local shards = Data.shardList(kind, key)
    if shards == nil then return nil end
    local pool = {}
    pools[key] = pool
    for _, id in ipairs(shards) do Data.loadShard(kind, id) end
    return pool
end

Data.sceneMeta = {}
Data.sceneMeta.__index = function(scene, key)
    if key ~= "turns" then return nil end
    local raw = scene.raw
    local turns = {}
    if type(raw) == "table" then
        for i = 1, #raw, 2 do turns[#turns + 1] = { s = raw[i], t = raw[i + 1] } end
    end
    scene.turns = turns
    scene.raw = nil
    return turns
end

Data.segmentMeta = {}
Data.segmentMeta.__index = function(segment, key)
    if key == "day" then
        local value = { segment.d1, segment.d2 }
        segment.day = value
        return value
    elseif key == "hour" then
        local value = { segment.h1, segment.h2 }
        segment.hour = value
        return value
    elseif key == "lines" then
        local raw = segment.raw
        local lines = {}
        if type(raw) == "table" then
            for i = 1, #raw, 2 do lines[#lines + 1] = { sp = raw[i], t = raw[i + 1] } end
        end
        segment.lines = lines
        segment.raw = nil
        return lines
    end
    return nil
end

function Data.sceneRecords(id)
    local cached = Data.sceneShards[id]
    if cached ~= nil then return cached end
    local list = {}
    Data.sceneShards[id] = list
    local ok, err = pcall(function()
        local rows = Data.rowsOf(id)
        for r = 1, #rows do
            local row = rows[r]
            local scene = setmetatable({ id = row[1], topic = row[2], min = row[3], g = Data.parseGate(row[4]),
                raw = row[5] }, Data.sceneMeta)
            list[#list + 1] = scene
            Data.scenes[#Data.scenes + 1] = scene
            Data.sceneLive[scene.id] = scene
            Data.sceneById[scene.id] = scene
        end
    end)
    if not ok then Data.errors[#Data.errors + 1] = tostring(id) .. ":" .. tostring(err) end
    return list
end

function Data.inAny(topic)
    return topic == "any" or not Data.askedTopics[topic]
end

function Data.openTopic(pools, topic)
    if topic == nil then return nil end
    if topic == "any" then return Data.openAny(pools) end
    local shards = Data.shardList("scenes", topic)
    if shards == nil then return nil end
    local pool = {}
    pools[topic] = pool
    for _, id in ipairs(shards) do
        for _, scene in ipairs(Data.sceneRecords(id)) do
            if scene.topic == topic then pool[#pool + 1] = scene end
        end
    end
    return pool
end

function Data.consumeAny(id)
    local pool = Data.anyPool
    for _, scene in ipairs(Data.sceneRecords(id)) do
        if Data.inAny(scene.topic) and not scene.inAny then
            scene.inAny = true
            pool[#pool + 1] = scene
        end
    end
end

function Data.openAny(pools)
    local index = Data.index
    local pool = {}
    pools.any = pool
    Data.anyPool = pool
    Data.anyOpen = true
    Data.streamWork = true
    local order = index ~= nil and index.sceneOrder or nil
    if type(order) == "table" then
        local first = math.min(#order, Data.anyFirst)
        for i = 1, first do Data.consumeAny(order[i]) end
        Data.anyPos = first
    end
    return pool
end

function Data.anyStep()
    local order = Data.index ~= nil and Data.index.sceneOrder or nil
    if not Data.anyOpen or type(order) ~= "table" or Data.anyPos >= #order then return false end
    Data.anyPos = Data.anyPos + 1
    Data.consumeAny(order[Data.anyPos])
    return true
end

function Data.findScene(id)
    if type(id) ~= "string" then return nil end
    local live = Data.sceneLive[id]
    if live ~= nil then return live end
    if Data.sceneDirectory == nil then
        require "ProjectALife/Talk/Data/ALifeDialogueSceneIds"
        Data.sceneDirectory = ProjectALife.DialogueSceneIds or {}
    end
    local needle = " " .. id .. " "
    for shard, text in pairs(Data.sceneDirectory) do
        if string.find(text, needle, 1, true) ~= nil then
            Data.sceneRecords(shard)
            return Data.sceneLive[id]
        end
    end
    return nil
end

function Data.radioRecords(id)
    Data.radioLoading = true
    local ok, err = pcall(function()
        local rows = Data.rowsOf(id)
        for r = 1, #rows do
            local row = rows[r]
            local segment = setmetatable({ id = row[1], kind = row[2], d1 = row[3], d2 = row[4], h1 = row[5],
                h2 = row[6], weight = row[7], raw = row[8] }, Data.segmentMeta)
            Data.segments[#Data.segments + 1] = segment
            append(Data.segmentsByKind, segment.kind, segment)
            Data.segmentById[segment.id] = segment
        end
    end)
    Data.radioLoading = false
    if not ok then Data.errors[#Data.errors + 1] = tostring(id) .. ":" .. tostring(err) end
end

function Data.radioAll()
    if Data.segments ~= Data.segmentsOwn then return end
    if Data.radioDay < 1000000 then Data.radioDay = 1000000 end
    while Data.radioStep() do end
end

function Data.radioStep()
    local list = Data.index ~= nil and Data.index.radio or nil
    if type(list) ~= "table" or Data.segments ~= Data.segmentsOwn then return false end
    while Data.radioPos < #list do
        local entry = list[Data.radioPos + 1]
        if entry[1] > Data.radioDay then return false end
        Data.radioPos = Data.radioPos + 1
        Data.radioRecords(entry[2])
        return true
    end
    return false
end

function Data.needDay(day)
    if Data.segments ~= Data.segmentsOwn then return end
    day = tonumber(day) or 0
    if day > Data.radioDay then Data.radioDay = day end
    Data.streamWork = true
    if not Data.radioStarted then
        Data.radioStarted = true
        Data.radioStep()
    end
end

function Data.streamStep()
    if Data.radioStep() then return true end
    if Data.anyStep() then return true end
    Data.streamWork = false
    return false
end

function Data.stream()
    local now = Data.nowMs()
    if now - Data.streamAt < Data.streamGapMs then return end
    Data.streamAt = now
    Data.streamStep()
end

function Data.indexOf(pool)
    if type(pool) ~= "table" then return nil end
    local size = #pool
    if size < Data.indexMin then return nil end
    local index = pool.index
    if index ~= nil and index.size == size then return index end
    local list, byGate = {}, {}
    for i = 1, size do
        local record = pool[i]
        local gate = record.g
        local group = byGate[gate]
        if group == nil then
            group = { g = gate, recs = {}, total = 0, uniform = true, spec = Data.specificity(gate) }
            byGate[gate] = group
            list[#list + 1] = group
        end
        group.recs[#group.recs + 1] = record
        group.total = group.total + record.w
        if record.w ~= 1 then group.uniform = false end
    end
    for _, group in ipairs(list) do
        if not group.uniform then
            local cum, run = {}, 0
            for i, record in ipairs(group.recs) do run = run + record.w; cum[i] = run end
            group.cum = cum
        end
        group.simple = true
        for key in pairs(group.g) do
            if key ~= "reg" and key ~= "tmp" and key ~= "st" and key ~= "mood" then group.simple = false; break end
        end
    end
    index = { size = size, groups = list, cache = {}, cacheCount = 0 }
    pool.index = index
    return index
end

Data.cacheMax = 48

function Data.entryFor(index, context)
    context = type(context) == "table" and context or {}
    local register, temperament, stance, mood = context.register, context.temperament, context.stance, context.mood
    local key = tostring(register) .. "|" .. tostring(temperament) .. "|" .. tostring(stance) .. "|" .. tostring(mood)
    local entry = index.cache[key]
    if entry ~= nil then return entry end
    if index.cacheCount >= Data.cacheMax then index.cache, index.cacheCount = {}, 0 end
    local complex, groups, cum, run = {}, {}, {}, 0
    for _, group in ipairs(index.groups) do
        local gate = group.g
        if (gate.reg == nil or (register ~= nil and gate.reg[register] == true))
                and (gate.tmp == nil or (temperament ~= nil and gate.tmp[temperament] == true))
                and (gate.st == nil or (stance ~= nil and gate.st[stance] == true))
                and (mood == nil or gate.mood == nil or gate.mood == mood) then
            if group.simple then
                groups[#groups + 1] = group
                run = run + group.total * group.spec
                cum[#groups] = run
            else
                complex[#complex + 1] = group
            end
        end
    end
    entry = { complex = complex, simple = { groups = groups, cum = cum, total = run } }
    index.cache[key] = entry
    index.cacheCount = index.cacheCount + 1
    return entry
end

function Data.install()
    local function lazy(kind)
        return setmetatable({}, { __index = function(pools, key) return Data.openPool(kind, pools, key) end })
    end
    Data.barks, Data.replies, Data.yesPools, Data.noPools = lazy("barks"), lazy("replies"), lazy("yes"), lazy("no")
    Data.scenesByTopic = setmetatable({}, { __index = function(pools, key) return Data.openTopic(pools, key) end })
    Data.sceneById = setmetatable({}, { __index = function(_, key) return Data.findScene(key) end })
    Data.scenes, Data.intents, Data.intentById = {}, {}, {}
    local function radioLazy()
        return setmetatable({}, { __index = function(map, key)
            if Data.radioLoading or key == nil or Data.segments ~= Data.segmentsOwn then return nil end
            setmetatable(map, nil)
            Data.radioAll()
            return map[key]
        end })
    end
    Data.segments, Data.segmentsByKind, Data.segmentById = {}, radioLazy(), radioLazy()
    Data.segmentsOwn = Data.segments
    Data.radioLoading = false
    Data.sceneShards, Data.sceneLive, Data.shardDone = {}, {}, {}
    Data.sceneDirectory, Data.anyPool = nil, nil
    Data.anyOpen, Data.anyPos = false, 0
    Data.radioDay, Data.radioPos, Data.radioStarted = -1, 0, false
    Data.streamWork, Data.streamAt = false, 0
    Data.gates = {}
    Data.counts = { barks = 0, scenes = 0, turns = 0, replies = 0, intents = 0, patterns = 0, segments = 0, radioLines = 0 }
    Data.errors = {}
    Data.index = ProjectALife.DialogueDataIndex
end

function Data.reset()
    Data.loaded = false
    Data.install()
end

function Data.loadAll()
    Data.load()
    local index = Data.index
    if index == nil then return #Data.errors == 0 end
    for kind, field in pairs(Data.poolFields) do
        local pools = Data[field]
        for key in pairs(index[kind] or {}) do
            local pool = pools[key]
        end
    end
    for topic in pairs(index.scenes or {}) do
        local pool = Data.scenesByTopic[topic]
    end
    local pool = Data.scenesByTopic.any
    while Data.anyStep() do end
    if Data.segments == Data.segmentsOwn then
        Data.radioDay = 1000000
        while Data.radioStep() do end
    end
    return #Data.errors == 0
end

function Data.load()
    if Data.loaded then
        if Data.streamWork then Data.stream() end
        return true
    end
    Data.loaded = true
    local modules = ProjectALife.DialogueDataModules
    if type(modules) ~= "table" then
        Data.errors[#Data.errors + 1] = "dialogue_index_missing"
        return false
    end
    for _, id in ipairs(modules) do
        local ok, err = pcall(function()
            require("ProjectALife/Talk/Data/ALifeDialogue_" .. tostring(id))
            local register = ProjectALife["DialogueDataRegister_" .. tostring(id)]
            if type(register) ~= "function" then error("register_missing") end
            register(Data)
        end)
        if not ok then Data.errors[#Data.errors + 1] = tostring(id) .. ":" .. tostring(err) end
    end
    local index = ProjectALife.DialogueDataIndex
    if type(index) == "table" then
        Data.index = index
        for _, id in ipairs(index.intents or {}) do
            local ok, err = pcall(function() Data.registerIntentRows(Data.rowsOf(id)) end)
            if not ok then Data.errors[#Data.errors + 1] = tostring(id) .. ":" .. tostring(err) end
        end
        for key, value in pairs(index.counts or {}) do
            Data.counts[key] = (Data.counts[key] or 0) + value
        end
    end
    return #Data.errors == 0
end

Data.install()

return Data
