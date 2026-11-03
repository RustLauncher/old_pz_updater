require "ProjectALife/Core/ALifeTelemetry"

local Telemetry = ProjectALife.Telemetry

local Theft = {
    adapters = {},
    settings = { pollMs = 8000, insideMargin = 2, barkRadius = 30 },
    nextPollMs = {},
    metrics = { polls = 0, thefts = 0, exempt = 0 },
}
ProjectALife.OutpostTheft = Theft

local function nowMs()
    if type(Theft.adapters.nowMs) == "function" then return Theft.adapters.nowMs() end
    local ok, value = pcall(getTimestampMs)
    return ok and value or 0
end

local function emit(category, fields)
    if type(Theft.adapters.emit) == "function" then return Theft.adapters.emit(category, fields) end
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then pcall(Telemetry.emit, category, fields) end
end

local function registry()
    return Theft.adapters.registry or ProjectALife.OutpostRegistry
end

local function actors()
    return Theft.adapters.actors or ProjectALife.ActorRegistry
end

function Theft.configure(adapters)
    Theft.adapters = adapters or {}
    return true
end

function Theft.reset()
    Theft.nextPollMs = {}
    Theft.metrics = { polls = 0, thefts = 0, exempt = 0 }
    return true
end

function Theft.inside(site, x, y, margin)
    local b = type(site) == "table" and site.bounds or nil
    if type(b) ~= "table" then return false end
    margin = tonumber(margin) or 0
    x, y = tonumber(x) or 0, tonumber(y) or 0
    return x >= (tonumber(b.x1) or 0) - margin and x <= (tonumber(b.x2) or 0) + margin
        and y >= (tonumber(b.y1) or 0) - margin and y <= (tonumber(b.y2) or 0) + margin
end

function Theft.judge(site, counts, playerInside, garrisonFighting)
    if type(site) ~= "table" or site.hostileToPlayers == true then return nil end
    if not playerInside then return nil end
    if type(site.containers) ~= "table" or type(counts) ~= "table" then return nil end
    local dropped = false
    for index, container in ipairs(site.containers) do
        local count = tonumber(counts[index])
        if count ~= nil and count < (tonumber(container.expected) or 0) then dropped = true end
    end
    if not dropped then return nil end
    if garrisonFighting then return "exempt" end
    return "flip"
end

local function engineCounts(site)
    local counts = {}
    for index, container in ipairs(site.containers or {}) do
        local count
        pcall(function()
            local square = getCell():getGridSquare(container.x, container.y, container.z or 0)
            if square == nil then return end
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local object = objects:get(i)
                local inventory = object and object:getContainer() or nil
                if inventory ~= nil then
                    count = inventory:getItems():size()
                    return
                end
            end
        end)
        counts[index] = count
    end
    return counts
end

local function counts(site)
    if type(Theft.adapters.counts) == "function" then return Theft.adapters.counts(site) end
    return engineCounts(site)
end

local function members(site)
    local out = {}
    local list = actors()
    if list == nil or type(list.list) ~= "function" then return out end
    for _, record in ipairs(list.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        if memory.outpostId == site.id and record.lifecycle ~= "dead" then out[#out + 1] = record end
    end
    return out
end

local function fighting(site)
    if type(Theft.adapters.fighting) == "function" then return Theft.adapters.fighting(site) == true end
    for _, record in ipairs(members(site)) do
        if record.activity == "combat" then return true end
    end
    return false
end

local function bark(site, text)
    pcall(function()
        local bindings = Theft.adapters.bindings or (ProjectALife.Watchdog and ProjectALife.Watchdog.bindings)
        if bindings == nil then return end
        for _, record in ipairs(members(site)) do
            local binding = bindings[record.uid]
            local speech = ProjectALife.Speech
            if binding ~= nil and binding.shell ~= nil
                    and (speech == nil or type(speech.mayVoice) ~= "function" or speech.mayVoice(binding.shell, false)) then
                if speech ~= nil and type(speech.sayLine) == "function" then
                    speech.sayLine(binding.shell, text, "directed")
                else
                    pcall(function() binding.shell:Say(text) end)
                end
                return
            end
        end
    end)
end

local function turnHostile(site, current, reason)
    local reg = registry()
    local updated = reg.update(site.id, site.revision, function(s)
        s.hostileToPlayers = true
        s.thefts = (tonumber(s.thefts) or 0) + 1
        for index, container in ipairs(s.containers or {}) do
            if tonumber(current[index]) ~= nil then container.expected = current[index] end
        end
    end)
    if updated == nil then return false end
    local list, turned = actors(), 0
    for _, record in ipairs(members(site)) do
        local ok = list.update(record.uid, record.revision, function(fresh)
            fresh.memory = fresh.memory or {}
            fresh.memory.hostileOverride = true
        end)
        if ok then turned = turned + 1 end
    end
    bark(site, "Hey! HEY! Put that down!")
    Theft.metrics.thefts = Theft.metrics.thefts + 1
    emit("outpost_theft", { site = site.id, reason = reason, count = turned })
    return true
end

function Theft.turnBlamed(site, current, keys)
    local reg = registry()
    local hours = type(getGameTime) == "function" and getGameTime() ~= nil and tonumber(getGameTime():getWorldAgeHours()) or 0
    local updated = reg.update(site.id, site.revision, function(s)
        s.thefts = (tonumber(s.thefts) or 0) + 1
        s.thieves = type(s.thieves) == "table" and s.thieves or {}
        for _, key in ipairs(keys) do s.thieves[key] = hours end
        for index, container in ipairs(s.containers or {}) do
            if tonumber(current[index]) ~= nil then container.expected = current[index] end
        end
    end)
    if updated == nil then return false end
    local list, turned = actors(), 0
    for _, record in ipairs(members(site)) do
        local ok = list.update(record.uid, record.revision, function(fresh)
            fresh.memory = fresh.memory or {}
            fresh.memory.hostileToPlayerKeys = type(fresh.memory.hostileToPlayerKeys) == "table"
                and fresh.memory.hostileToPlayerKeys or {}
            for _, key in ipairs(keys) do fresh.memory.hostileToPlayerKeys[key] = true end
        end)
        if ok then turned = turned + 1 end
    end
    bark(site, "Hey! HEY! Put that down!")
    Theft.metrics.thefts = Theft.metrics.thefts + 1
    local blame = ProjectALife.Blame
    if blame ~= nil then blame.metrics.thievesBlamed = blame.metrics.thievesBlamed + #keys end
    emit("outpost_theft", { site = site.id, reason = "container_looted", count = turned, blamed = #keys })
    return true
end

function Theft.tick(site, list, now)
    if type(site) ~= "table" or site.state ~= "garrisoned" or site.hostileToPlayers == true then return false end
    if type(site.containers) ~= "table" or #site.containers == 0 then return false end
    now = tonumber(now) or nowMs()
    if now < (Theft.nextPollMs[site.id] or 0) then return false end
    local inside, insiders = false, {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        if Theft.inside(site, p.x, p.y, Theft.settings.insideMargin) then
            inside = true
            if p.player ~= nil then insiders[#insiders + 1] = p.player end
        end
    end
    if not inside then return false end
    Theft.nextPollMs[site.id] = now + Theft.settings.pollMs
    Theft.metrics.polls = Theft.metrics.polls + 1
    local current = counts(site)
    local verdict = Theft.judge(site, current, true, fighting(site))
    if verdict == "flip" then
        local blame = ProjectALife.Blame
        local keys = blame ~= nil and blame.keys(insiders) or nil
        if keys ~= nil then return Theft.turnBlamed(site, current, keys) end
        return turnHostile(site, current, "container_looted")
    end
    if verdict == "exempt" then
        Theft.metrics.exempt = Theft.metrics.exempt + 1

        registry().update(site.id, site.revision, function(s)
            for index, container in ipairs(s.containers or {}) do
                if tonumber(current[index]) ~= nil then container.expected = math.min(container.expected or 0, current[index]) end
            end
        end)
    end
    return false
end

return Theft
