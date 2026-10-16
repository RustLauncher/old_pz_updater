ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/ALifeDialogueData"
require "ProjectALife/Talk/ALifeDialogueRoles"
require "ProjectALife/Talk/ALifeWorldFacts"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Records/ALifeRepLevels"

local Speech = {
    settings = {
        recentPerSpeaker = 40,
        heardPerPlayer = 400,
        earshot = 40,
    },
    adapters = {},
    recent = {},
    heard = {},
    metrics = { said = 0, sent = 0, drawn = 0, picked = 0, exhausted = 0, missing = 0, repTier = {}, repFallback = 0,
        speechRefusedDead = 0 },
}
ProjectALife.Speech = Speech

local function nowMs()
    if type(Speech.adapters.nowMs) == "function" then return Speech.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function random(maximum)
    if maximum <= 1 then return 0 end
    if type(Speech.adapters.random) == "function" then return Speech.adapters.random(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return math.random(0, maximum - 1)
end

function Speech.readModData(shell) return shell:getModData() end
function Speech.readVariable(shell, name) return shell:GetVariable(name) end

function Speech.variable(shell, name)
    if shell == nil then return nil end

    local kind = type(shell)
    if kind == "number" or kind == "string" or kind == "boolean" then return nil end

    if type(shell.getModData) == "function" then
        local okData, data = pcall(Speech.readModData, shell)
        if okData and type(data) == "table" and data["Project" .. name] ~= nil then return data["Project" .. name] end
    end
    if type(shell.GetVariable) == "function" then
        local ok, value = pcall(Speech.readVariable, shell, name)
        if ok and value ~= nil and value ~= "" then return value end
    end
    return nil
end

function Speech.readDead(shell) return shell:isDead() end
function Speech.readHasModData(shell) return shell:hasModData() end

function Speech.alive(shell)
    local kind = type(shell)
    if shell == nil or kind == "number" or kind == "string" or kind == "boolean"
            or type(shell.isDead) ~= "function" then return false end
    local okDead, dead = pcall(Speech.readDead, shell)
    if not okDead or dead == true then return false end
    if type(shell.isReanimatedForGrappleOnly) == "function" then
        if shell:isReanimatedForGrappleOnly() == true then return false end
    end
    if type(shell.isFakeDead) == "function" then
        local okFake, fake = pcall(shell.isFakeDead, shell)
        if okFake and fake == true then return false end
    end
    if type(shell.getModData) ~= "function" then return true end
    if type(shell.hasModData) == "function" then
        local okHas, has = pcall(Speech.readHasModData, shell)
        if okHas and has ~= true then return true end
    end
    local okData, data = pcall(Speech.readModData, shell)
    if not okData then return false end
    if type(data) == "table" and data.ProjectALifeCorpseOf ~= nil then return false end
    return true
end

function Speech.refusedDead(shell)
    if Speech.alive(shell) then return false end
    Speech.metrics.speechRefusedDead = (Speech.metrics.speechRefusedDead or 0) + 1
    return true
end

function Speech.talkable(shell, record, now)
    if type(record) ~= "table" or record.lifecycle ~= "active" then return false, "inactive" end
    local kind = type(shell)
    if shell == nil or kind == "number" or kind == "string" or kind == "boolean"
            or type(shell.isDead) ~= "function" then
        return false, "no_body"
    end
    if not Speech.alive(shell) then return false, "dead" end
    if type(shell.getModData) ~= "function" then return true, nil end
    if type(shell.hasModData) == "function" then
        local okHas, has = pcall(Speech.readHasModData, shell)
        if okHas and has ~= true then return true, nil end
    end
    local okData, data = pcall(Speech.readModData, shell)
    if not okData or type(data) ~= "table" then return true, nil end
    now = tonumber(now) or nowMs()
    if data.ProjectALifeDownedUntilMs ~= nil then
        local rule = ProjectALife.Health
        if rule == nil or type(rule.downedHolds) ~= "function" then rule = ProjectALife.AIFence end
        local held
        if rule ~= nil and type(rule.downedHolds) == "function" then
            held = rule.downedHolds(data.ProjectALifeDownedUntilMs, now) == true
        else
            held = now < (tonumber(data.ProjectALifeDownedUntilMs) or 0)
        end
        if held then return false, "downed" end
    end
    local bleedAt = tonumber(data.ProjectALifeBleedOutAtMs)
    if bleedAt ~= nil then
        local server = type(Speech.adapters.isServer) == "function" and Speech.adapters.isServer()
            or (Speech.adapters.isServer == nil and type(isServer) == "function" and isServer())
        if not server or now < bleedAt then return false, "bleeding" end
    end
    return true, nil
end

local function stable(value)
    local result = 0
    value = tostring(value or "")
    for index = 1, #value do result = (result * 33 + string.byte(value, index)) % 2147483647 end
    return result
end
Speech.stable = stable

function Speech.colorFor(uid, factionId)
    local voice = ProjectALife.Voice
    if voice ~= nil and type(voice.speakerColor) == "function" then
        return voice.speakerColor(uid, factionId)
    end
    local key
    if uid ~= nil and tostring(uid) ~= "" then
        key = "colour:" .. tostring(uid)
    elseif factionId ~= nil and tostring(factionId) ~= "" then
        key = "faction:" .. tostring(factionId)
    else
        return { 0.80, 0.80, 0.80 }
    end
    local hue = stable(key) % 360
    local s, v = 0.55, 0.95
    local c = v * s
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if hue < 60 then r, g, b = c, x, 0 elseif hue < 120 then r, g, b = x, c, 0
    elseif hue < 180 then r, g, b = 0, c, x elseif hue < 240 then r, g, b = 0, x, c
    elseif hue < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
    return { r + m, g + m, b + m }
end

function Speech.authoritative()
    if type(Speech.adapters.authoritative) == "function" then return Speech.adapters.authoritative() end
    local client = type(isClient) == "function" and isClient()
    local server = type(isServer) == "function" and isServer()
    return not (client and not server)
end

local function ring(store, key, size)
    local entry = store[key]
    if entry == nil then
        entry = { list = {}, set = {} }
        store[key] = entry
    end
    return entry, size
end

local function remember(store, key, size, text)
    if key == nil or text == nil then return end
    local entry = ring(store, tostring(key), size)
    if entry.set[text] then
        for index, old in ipairs(entry.list) do
            if old == text then table.remove(entry.list, index); break end
        end
    end
    entry.list[#entry.list + 1] = text
    entry.set[text] = true
    while #entry.list > size do
        local oldest = table.remove(entry.list, 1)
        entry.set[oldest] = nil
    end
end

function Speech.remember(uid, playerKey, text)
    remember(Speech.recent, uid, Speech.settings.recentPerSpeaker, text)
    remember(Speech.heard, playerKey, Speech.settings.heardPerPlayer, text)
end

local function seen(uid, playerKey, text)
    local a = uid ~= nil and Speech.recent[tostring(uid)] or nil
    if a ~= nil and a.set[text] then return true end
    local b = playerKey ~= nil and Speech.heard[tostring(playerKey)] or nil
    return b ~= nil and b.set[text] == true
end

local function recency(store, key, text)
    local entry = key ~= nil and store[tostring(key)] or nil
    if entry == nil then return 0 end
    for index, old in ipairs(entry.list) do
        if old == text then return index / (#entry.list + 1) end
    end
    return 0
end

Speech.intel = { den = true, destination = true, from = true, to = true, faction = true, group = true, count = true }
Speech.intelCache = {}
Speech.noNeeds = {}
function Speech.claimsUnknown(text, vars)
    local needs = Speech.intelCache[text]
    if needs == nil then
        needs = {}
        for key in string.gmatch(tostring(text or ""), "{([a-z]+)}") do
            if Speech.intel[key] then needs[#needs + 1] = key end
        end
        if #needs == 0 then needs = Speech.noNeeds end
        Speech.intelCache[text] = needs
    end
    for _, key in ipairs(needs) do
        if type(vars) ~= "table" or vars[key] == nil then return true end
    end
    return false
end

function Speech.attackFits(record, context)
    local kind = type(record) == "table" and record.a or nil
    if kind == nil then return true end
    local attack = type(context) == "table" and context.attack or nil
    if attack == nil then return false end
    return ProjectALife.Wounds.lineFits(kind, attack)
end

Speech.indexTries = 24

function Speech.lastShortReply(record, uid, enabled)
    if enabled ~= true or uid == nil or record.beats ~= nil or type(record.t) ~= "string" or #record.t > 80 then return false end
    local entry = Speech.recent[tostring(uid)]
    return entry ~= nil and entry.list[#entry.list] == record.t
end

function Speech.countTier(tiers, rank)
    if tiers[rank] ~= nil then
        Speech.metrics.repTier[tiers[rank]] = (Speech.metrics.repTier[tiers[rank]] or 0) + 1
    elseif #tiers > 0 then
        Speech.metrics.repFallback = Speech.metrics.repFallback + 1
    end
end

function Speech.pickIndexed(index, context, uid, playerKey, vars, tiers)
    local data = ProjectALife.DialogueData
    local entry = data.entryFor(index, context)
    local worst = #tiers + 1
    local live, weights, total, bestRank = {}, {}, 0, worst
    for _, group in ipairs(entry.complex) do
        if data.allows(group.g, context) then
            local rank = worst
            local rep = group.g.rep
            if type(rep) == "table" then
                for position, tier in ipairs(tiers) do
                    if rep[tier] == true then rank = position; break end
                end
            end
            if rank <= bestRank then
                if rank < bestRank then live, weights, total, bestRank = {}, {}, 0, rank end
                local weight = group.total * group.spec
                live[#live + 1] = group
                weights[#live] = weight
                total = total + weight
            end
        end
    end
    local simple = bestRank == worst and entry.simple.total > 0 and entry.simple or nil
    local grand = total + (simple ~= nil and simple.total or 0)
    if grand <= 0 then return nil, live, nil end
    for _ = 1, Speech.indexTries do
        local needle = random(math.max(1, math.floor(grand * 100))) / 100
        local group = nil
        if simple ~= nil then
            if needle < simple.total then
                local low, high = 1, #simple.groups
                while low < high do
                    local middle = math.floor((low + high) / 2)
                    if simple.cum[middle] > needle then high = middle else low = middle + 1 end
                end
                group = simple.groups[low]
            else
                needle = needle - simple.total
            end
        end
        if group == nil then
            group = live[#live]
            for position, candidate in ipairs(live) do
                needle = needle - weights[position]
                if needle < 0 then group = candidate; break end
            end
        end
        local count = #group.recs
        local record
        if group.cum == nil then
            record = group.recs[random(count) + 1]
        else
            local roll = random(math.max(1, math.floor(group.total * 100))) / 100
            local low, high = 1, count
            while low < high do
                local middle = math.floor((low + high) / 2)
                if group.cum[middle] > roll then high = middle else low = middle + 1 end
            end
            record = group.recs[low]
        end
        if record ~= nil and not seen(uid, playerKey, record.t) and not Speech.claimsUnknown(record.t, vars)
                and Speech.attackFits(record, context) then
            Speech.countTier(tiers, bestRank)
            Speech.metrics.picked = Speech.metrics.picked + 1
            return record, live, simple
        end
    end
    return nil, live, simple
end

function Speech.pick(records, context, uid, playerKey, vars, noShortRepeat)
    local data = ProjectALife.DialogueData
    if type(records) ~= "table" or data == nil then Speech.metrics.missing = Speech.metrics.missing + 1; return nil end
    local fresh, freshTotal, any = {}, 0, {}
    local tiers = type(context) == "table" and type(context.repTiers) == "table" and context.repTiers or {}
    if #records >= (tonumber(data.indexMin) or 48) and type(data.indexOf) == "function" then
        local index = data.indexOf(records)
        if index ~= nil then
            local chosen, live, simple = Speech.pickIndexed(index, context, uid, playerKey, vars, tiers)
            if chosen ~= nil then return chosen end
            if #live == 0 and simple == nil then Speech.metrics.missing = Speech.metrics.missing + 1; return nil end
            records = {}
            for _, group in ipairs(live) do
                for _, record in ipairs(group.recs) do records[#records + 1] = record end
            end
            for _, group in ipairs(simple ~= nil and simple.groups or {}) do
                for _, record in ipairs(group.recs) do records[#records + 1] = record end
            end
        end
    end
    local bestRank = #tiers + 1
    for _, record in ipairs(records) do
        if data.allows(record.g, context) and not Speech.claimsUnknown(record.t, vars)
                and not Speech.lastShortReply(record, uid, noShortRepeat)
                and Speech.attackFits(record, context) then
            local rank = #tiers + 1
            if type(record.g) == "table" and type(record.g.rep) == "table" then
                for index, tier in ipairs(tiers) do if record.g.rep[tier] == true then rank = index; break end end
            end
            if rank <= bestRank then
                if rank < bestRank then fresh, freshTotal, any, bestRank = {}, 0, {}, rank end
                local weight = (tonumber(record.w) or 1) * data.specificity(record.g)
                any[#any + 1] = { record = record, weight = weight }
                if not seen(uid, playerKey, record.t) then
                    fresh[#fresh + 1] = { record = record, weight = weight }
                    freshTotal = freshTotal + weight
                end
            end
        end
    end
    local pool, total = fresh, freshTotal
    if #pool == 0 then
        if #any == 0 then Speech.metrics.missing = Speech.metrics.missing + 1; return nil end

        pool, total = {}, 0
        local oldest = math.huge
        for _, item in ipairs(any) do
            local age = math.max(recency(Speech.recent, uid, item.record.t), recency(Speech.heard, playerKey, item.record.t))
            if age < oldest then oldest = age; pool, total = {}, 0 end
            if age == oldest then pool[#pool + 1] = item; total = total + item.weight end
        end
        Speech.metrics.exhausted = Speech.metrics.exhausted + 1
    end
    local needle = random(math.max(1, math.floor(total * 100))) / 100
    if tiers[bestRank] ~= nil then
        local tier = tiers[bestRank]
        Speech.metrics.repTier[tier] = (Speech.metrics.repTier[tier] or 0) + 1
    elseif #tiers > 0 then
        Speech.metrics.repFallback = Speech.metrics.repFallback + 1
    end
    for _, item in ipairs(pool) do
        needle = needle - item.weight
        if needle < 0 then
            Speech.metrics.picked = Speech.metrics.picked + 1
            return item.record
        end
    end
    Speech.metrics.picked = Speech.metrics.picked + 1
    return pool[#pool].record
end

Speech.names = {
    "Danny", "Ray", "Earl", "Bobby", "Lyle", "Travis", "Curtis", "Dale", "Wendell", "Hank", "Jimmy", "Luther",
    "Darlene", "Tammy", "Loretta", "Brenda", "Shelby", "Ruth", "Carla", "Jolene", "Missy", "Dottie", "Faye", "Lisa",
}
Speech.streets = {
    "Dixie Highway", "Main Street", "Railroad Avenue", "Church Street", "Rosewood Road", "Elm Street",
    "Old Mill Road", "Ridge Road", "Water Street", "Hill Street", "Knox Lane", "Pike Road",
}
Speech.months = { "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" }
Speech.weekdays = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local function ordinal(n)
    local mod100 = n % 100
    if mod100 >= 11 and mod100 <= 13 then return tostring(n) .. "th" end
    local mod10 = n % 10
    if mod10 == 1 then return tostring(n) .. "st" end
    if mod10 == 2 then return tostring(n) .. "nd" end
    if mod10 == 3 then return tostring(n) .. "rd" end
    return tostring(n) .. "th"
end

function Speech.weekday(year, month, day)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then year = year - 1 end
    local w = (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + t[month] + day) % 7
    return w
end

function Speech.clock()
    if type(Speech.adapters.clock) == "function" then return Speech.adapters.clock() end
    local clock = { year = 1993, month = 7, day = 9, hour = 12, daysSurvived = 0 }
    pcall(function()
        local time = getGameTime()
        clock.year = time:getYear()
        clock.month = time:getMonth() + 1
        clock.day = time:getDay() + 1
        clock.hour = time:getHour()
        clock.daysSurvived = time:getNightsSurvived()
    end)
    return clock
end

function Speech.timeText(hour)
    hour = tonumber(hour) or 12
    if hour == 0 then return "midnight" end
    if hour == 12 then return "noon" end
    if hour < 12 then return tostring(hour) .. " AM" end
    return tostring(hour - 12) .. " PM"
end

function Speech.nearestTown(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" or x == nil then return nil end
    local _, town = regions.distanceToTown({ x = x, y = y })
    return town and town.label or nil
end

function Speech.randomTown(seed)
    local regions = ProjectALife.TownRegions
    local list = regions and regions.definitions or nil
    if type(list) ~= "table" or #list == 0 then return "Muldraugh" end
    local index = seed ~= nil and (stable(seed) % #list) + 1 or random(#list) + 1
    return list[index].label
end

Speech.militaryBlocs = { military = true, elite = true }
function Speech.military(shell)
    if shell == nil then return false end
    local factionId
    pcall(function()
        local data = shell:getModData()
        factionId = type(data) == "table" and data.ProjectALifeFactionId or nil
        if factionId == nil then factionId = shell:GetVariable("ALifeFactionId") end
    end)
    local catalog = ProjectALife.Catalog
    if factionId == nil or factionId == "" or catalog == nil or type(catalog.faction) ~= "function" then return false end
    local ok, faction = pcall(catalog.faction, factionId)
    if not ok or type(faction) ~= "table" then return false end
    local rules = ProjectALife.FactionSpawnRules
    local bloc = rules ~= nil and type(rules.blocOf) == "function" and rules.blocOf(faction)
        or (faction.relations and faction.relations.bloc)
    return Speech.militaryBlocs[tostring(bloc)] == true
end

function Speech.militaryCallsign()
    local companies = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Hotel" }
    local digits = { "One", "Two", "Three", "Four", "Five", "Six" }
    return companies[random(#companies) + 1] .. " " .. digits[random(#digits) + 1]
        .. "-" .. digits[random(#digits) + 1]
end

Speech.addressForms = {
    sir = { "sir", "ma'am" }, mister = { "mister", "miss" }, he = { "he", "she" }, him = { "him", "her" },
    his = { "his", "her" }, hers = { "his", "hers" }, himself = { "himself", "herself" },
}

function Speech.sexCode(value)
    if value == "f" or value == "m" then return value end
    return nil
end

function Speech.sexOf(player)
    local kind = type(player)
    if kind ~= "table" and kind ~= "userdata" then return nil end
    local female = nil
    pcall(function()
        if type(player.isFemale) == "function" then female = player:isFemale() end
    end)
    if female == nil then return nil end
    if female == true then return "f" end
    return "m"
end

function Speech.threatSex(threat, kind)
    if kind == "player" then return Speech.sexOf(threat) end
    if kind == "actor" or kind == "npc" then return "m" end
    return nil
end

function Speech.genderStyle(key, value)
    if #key > 1 and key == string.upper(key) then return string.upper(value) end
    local first = string.sub(key, 1, 1)
    if first ~= string.lower(first) then return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2) end
    return value
end

function Speech.gendered(text, sex, shell)
    if type(text) ~= "string" or string.find(text, "{", 1, true) == nil then return text end
    local known = sex == "f" or sex == "m"
    local female = sex == "f"
    local function pick()
        if not known then
            known = true
            female = Speech.sexNear(shell) == "f"
        end
        return female
    end
    text = string.gsub(text, "{g:([^{}]*)}", function(body)
        local bar = string.find(body, "|", 1, true)
        if bar == nil or string.find(body, "|", bar + 1, true) ~= nil then return "{g:" .. body .. "}" end
        if pick() then return string.sub(body, bar + 1) end
        return string.sub(body, 1, bar - 1)
    end)
    text = string.gsub(text, "{(%a+)}", function(key)
        local forms = Speech.addressForms[string.lower(key)]
        if forms == nil then return "{" .. key .. "}" end
        local index = 1
        if pick() then index = 2 end
        return Speech.genderStyle(key, forms[index])
    end)
    return text
end

function Speech.genderedFor(text, player)
    if type(text) ~= "string" then return text end
    return Speech.gendered(text, Speech.sexOf(player))
end

function Speech.render(text, vars, shell, psex)
    if type(text) ~= "string" then return nil end
    vars = type(vars) == "table" and vars or {}
    text = Speech.gendered(text, Speech.sexCode(psex) or Speech.sexCode(vars.psex), shell)
    local clock = nil
    local sx, sy = nil, nil
    if shell ~= nil then pcall(function() sx, sy = shell:getX(), shell:getY() end) end
    local function value(key)
        if vars[key] ~= nil then return tostring(vars[key]) end
        if key == "town" then return Speech.nearestTown(sx, sy) or "this county" end

        if key == "destination" then return "somewhere quieter" end
        if key == "den" then return "a place I won't go back to" end
        clock = clock or Speech.clock()
        if key == "day" then return tostring((tonumber(clock.daysSurvived) or 0) + 1) end
        if key == "date" then return (Speech.months[clock.month] or "July") .. " " .. ordinal(clock.day) end
        if key == "time" then return Speech.timeText(clock.hour) end
        if key == "weekday" then return Speech.weekdays[Speech.weekday(clock.year, clock.month, clock.day) + 1] end
        if key == "weapon" then return "that gun" end
        if key == "faction" or key == "group" then return "some crew" end
        if key == "name" then return Speech.names[random(#Speech.names) + 1] end
        if key == "street" then return Speech.streets[random(#Speech.streets) + 1] end
        if key == "address" then return tostring(100 + random(8900)) .. " " .. Speech.streets[random(#Speech.streets) + 1] end
        if key == "unit" or key == "callsign" then
            if Speech.military(shell) then return Speech.militaryCallsign() end
            local letters = { "Adam", "Boy", "Charles", "David", "Edward", "Frank", "George", "Henry", "Lincoln", "Mary", "Nora", "Robert", "Sam", "Tom" }
            return tostring(1 + random(9)) .. "-" .. letters[random(#letters) + 1] .. "-" .. tostring(10 + random(80))
        end
        if key == "from" or key == "to" then return "down the road" end
        if key == "count" then return "a few" end
        if key == "where" then return "not far from here" end
        if key == "kind" then return "place" end
        return key
    end
    local rendered = string.gsub(text, "{([a-z]+)}", value)

    local first = string.find(rendered, "%a")
    if first ~= nil then
        rendered = string.sub(rendered, 1, first - 1)
            .. string.upper(string.sub(rendered, first, first)) .. string.sub(rendered, first + 1)
    end
    return rendered
end

function Speech.mayTurn(shell)
    local guest = ProjectALife.ModuleVisitorLife
    if guest ~= nil and type(guest.holdsPose) == "function" and guest.holdsPose(shell) then return false end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.drivesBody) == "function" then return fence.drivesBody(shell) == true end
    local simulation = ProjectALife.ShellSimulation
    return simulation == nil or type(simulation.isOwner) ~= "function" or simulation.isOwner(shell) == true
end

function Speech.face(shell, target)
    if shell == nil or target == nil then return false end
    if not Speech.mayTurn(shell) then return false end
    return pcall(function()
        local x, y
        if type(target) == "table" then x, y = target.x, target.y else x, y = target:getX(), target:getY() end
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then
            guard.faceAimPoint(shell, x, y, nowMs())
        else
            shell:faceLocationF(x, y)
        end
    end) == true
end

local function players()
    if type(Speech.adapters.players) == "function" then return Speech.adapters.players() end
    local list = {}
    pcall(function()
        local online = getOnlinePlayers and getOnlinePlayers() or nil
        if online ~= nil then
            for index = 0, online:size() - 1 do list[#list + 1] = online:get(index) end
        end
    end)
    return list
end

Speech.kinds = { directed = true, ambient = true, final = true }
Speech.finalEvents = { INJURED_DEATH = true }

function Speech.engineLine(shell, text, color)
    shell:addLineChatElement(text, color[1], color[2], color[3])
end

function Speech.engineSay(shell, text)
    shell:Say(text)
end

function Speech.mirror(shell, text, color, kind, uid)
    local chat = ProjectALife.NpcChat
    local sent = false
    if chat ~= nil and type(chat.mirror) == "function" then
        sent = pcall(chat.mirror, shell, text, color, kind, uid) == true
    end
    local prompt = ProjectALife.TalkPrompt
    if prompt ~= nil and type(prompt.note) == "function" then pcall(prompt.note, shell, text, kind, uid) end
    return sent
end

function Speech.display(shell, text, color, kind, uid)
    local bubbles = ProjectALife.SpeechBubbles
    if bubbles ~= nil and type(bubbles.show) == "function" then
        local ok, handled = pcall(bubbles.show, shell, text, color, kind, uid)
        if ok and handled == true then
            Speech.mirror(shell, text, color, kind, uid)
            return true
        end
    end
    local ok = pcall(Speech.engineLine, shell, text, color)
    if ok then Speech.mirror(shell, text, color, kind, uid) end
    return ok
end

function Speech.sayLine(shell, text, kind)
    local bubbles = ProjectALife.SpeechBubbles
    if bubbles ~= nil and type(bubbles.show) == "function" then
        local ok, handled = pcall(bubbles.show, shell, text, nil, kind, nil)
        if ok and handled == true then
            Speech.mirror(shell, text, nil, kind, nil)
            return true
        end
    end
    local ok = pcall(Speech.engineSay, shell, text)
    if ok then Speech.mirror(shell, text, nil, kind, nil) end
    return ok
end

function Speech.kindFor(event)
    if Speech.finalEvents[event] == true then return "final" end
    if Speech.ambientEvents[event] == true then return "ambient" end
    return "directed"
end

local function draw(shell, text, uid, kind)
    if Speech.refusedDead(shell) then return false end
    text = ProjectALife.AudioPolicy.caption(text)
    if text == nil then return false end
    if type(Speech.adapters.draw) == "function" then return Speech.adapters.draw(shell, text, uid) ~= false end
    local factionId = nil
    if uid == nil or tostring(uid) == "" then factionId = Speech.variable(shell, "ALifeFactionId") end
    local color = Speech.colorFor(uid, factionId)
    local ok = Speech.display(shell, text, color, kind, uid)
    if ok then Speech.metrics.drawn = Speech.metrics.drawn + 1 end
    if ok and type(ProjectALife.TalkClientReceive) == "function" then
        ProjectALife.TalkClientReceive("ProjectALife", "speech", { uid = uid, text = text })
    end
    return ok
end

function Speech.sexNear(shell)
    local sx, sy
    if shell ~= nil then pcall(function() sx, sy = shell:getX(), shell:getY() end) end
    local bestSex, bestDistance = nil, nil
    for _, player in ipairs(players()) do
        local sex = Speech.sexOf(player)
        if sex ~= nil then
            local distance = 0
            local px, py
            if sx ~= nil then pcall(function() px, py = player:getX(), player:getY() end) end
            if px ~= nil then distance = (px - sx) ^ 2 + (py - sy) ^ 2 end
            if bestDistance == nil or distance < bestDistance then bestSex, bestDistance = sex, distance end
        end
    end
    if bestSex == nil and type(getSpecificPlayer) == "function" then
        local ok, local0 = pcall(getSpecificPlayer, 0)
        if ok then bestSex = Speech.sexOf(local0) end
    end
    return bestSex
end

Speech.downedEvents = { HURT = true, PLEAD = true, SURRENDER = true, PANIC = true, KNOCKED_DOWN = true,
    INJURED = true, GETTING_UP = true, ALLY_DOWN = true }
Speech.chatEvents = {
    SAFE_MOMENT = true, LOCATION_COMMENT = true, LONG_WALK = true, HOME_MEMORY = true, FOOD_MEMORY = true,
    MORALE_LOW = true, MORALE_HIGH = true, CHECK_IN = true, STATUS_OK = true, PATROL_CHECKPOINT = true, JOKE = true,
    CAMP_CHATTER = true, GREET_PLAYER = true, PASSING_PLAYER = true, STARE_PLAYER = true, GOSSIP_VISITOR = true,
    GOSSIP_VISITORS = true, SPOT_STRANGER = true, SHOUT_HEARD_FRIENDLY = true, SHOUT_HEARD_NEUTRAL = true,
    SHOUT_HEARD_CAREFUL = true, SHOUT_HEARD_HOSTILE = true, TALK_FALLBACK_1 = true, TALK_FALLBACK_2 = true,
    TALK_FALLBACK_3 = true, TALK_FALLBACK_END = true, COME_WITH_ME_REFUSE = true, TENSE_SILENCE = true,
    IDLE = true, BANTER_INTRO = true, BANTER_REACTION = true, ANNOUNCE_ENTRY = true, PATROL_START = true,
    THIRSTY = true, HUNGRY = true, TIRED = true, COLD = true, HOT = true, WET = true, NEED_SMOKE = true,
    DRINK_START = true, DRINK_END = true, EAT_START = true, EAT_END = true, SMOKE_START = true, SMOKE_END = true,
    REST_START = true, REST_END = true, SQUAD_REST_CALLED = true, SQUAD_REST_READY = true, LOCAL_MEMORY = true,
    DAILY_NEEDS = true, WEATHER_RAIN = true, WEATHER_STORM = true, WEATHER_FOG = true, NIGHTFALL = true, DAWN = true,
    SHIVER = true, SNEEZE = true, COUGH = true, SICK_COMPLAINT = true, SICK_RECOVERED = true, SEEK_WARMTH = true,
    WARMING = true, WARMED_UP = true, DRESS_WARM = true, SNOW_FALLING = true, SNOW_GROUND = true,
    SEASON_WINTER = true, SEASON_SPRING = true, SEASON_SUMMER = true, SEASON_AUTUMN = true,
    PASSING_NPC_GREET = true,
}
Speech.chatCategories = { ambient = true, scavenge = true, archive = true }
Speech.quietHitMs = 5000

function Speech.readGrounded(shell)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.grounded) ~= "function" then return false end
    return fence.grounded(shell) == true
end

function Speech.quietReason(shell, record, now)
    local kind = type(shell)
    if shell == nil or kind == "number" or kind == "string" or kind == "boolean" then return nil end
    now = tonumber(now) or nowMs()
    local data = nil
    if type(shell.getModData) == "function" then
        local okHas, has = true, true
        if type(shell.hasModData) == "function" then okHas, has = pcall(Speech.readHasModData, shell) end
        if okHas and has == true then
            local okData, read = pcall(Speech.readModData, shell)
            if okData and type(read) == "table" then data = read end
        end
    end
    if data ~= nil then
        if data.ProjectALifeBleedOutAtMs ~= nil then return "downed" end
        if now < (tonumber(data.ProjectALifeDownedUntilMs) or 0) then return "downed" end
    end
    local okGround, grounded = pcall(Speech.readGrounded, shell)
    if okGround and grounded == true then return "downed" end
    if data ~= nil then
        if now < (tonumber(data.ProjectALifeStaggerUntilMs) or 0) then return "fighting" end
        if now - (tonumber(data.ProjectALifeLastHitAtMs) or -1e12) < Speech.quietHitMs then return "fighting" end
        if data.ProjectALifeCombatActive == true then return "fighting" end
    end
    if record == nil and data ~= nil and type(data.ProjectALifeUID) == "string" then
        local registry = ProjectALife.ActorRegistry
        if registry ~= nil and type(registry.peek) == "function" then record = registry.peek(data.ProjectALifeUID) end
    end
    local talk = ProjectALife.Talk
    if type(record) == "table" and talk ~= nil and type(talk.busy) == "function" and talk.busy(record, now) == true then
        return "fighting"
    end
    return nil
end

function Speech.eventFits(event, category, reason)
    if reason == nil or event == nil then return true end
    if reason == "downed" then return Speech.downedEvents[event] == true end
    if Speech.chatEvents[event] == true or Speech.chatCategories[tostring(category)] == true then return false end
    return true
end

function Speech.mayVoice(shell, chat)
    local reason = Speech.quietReason(shell, nil, nil)
    if reason == "downed" or (reason ~= nil and chat == true) then
        Speech.metrics.quieted = (Speech.metrics.quieted or 0) + 1
        return false
    end
    return true
end

function Speech.allows(shell, record, event, category, now)
    local reason = Speech.quietReason(shell, record, now)
    if Speech.eventFits(event, category, reason) then return true, reason end
    Speech.metrics.quieted = (Speech.metrics.quieted or 0) + 1
    return false, reason
end

Speech.gestureRules = {
    { id = "stop", chance = 70, words = { "stop", "freeze", "hold it", "don't move", "back off", "stay back",
        "far enough", "not another step", "easy now" } },
    { id = "follow", chance = 70, words = { "follow me", "stay close", "stick with", "with me" } },
    { id = "come_here", chance = 70, words = { "come here", "come on", "over here", "this way", "come with" } },
    { id = "shout", chance = 70, words = { "look out", "watch out", "get down", "behind you", "incoming", "run" } },
    { id = "no_thanks", chance = 60, words = { "no thanks", "no thank", "not interested", "forget it", "no deal",
        "can't help", "not for sale", "i'll pass", "not happening", "keep it" } },
    { id = "shrug", chance = 60, words = { "don't know", "dunno", "not sure", "couldn't say", "who knows", "can't say",
        "no idea", "maybe", "hard to say", "beats me", "wouldn't know" } },
    { id = "undecided", chance = 50, words = { "hmm", "let me think", "depends", "i suppose", "don't like" } },
    { id = "yes", chance = 45, words = { "yes", "yeah", "sure", "okay", "alright", "all right", "fair enough", "deal",
        "got it", "understood", "of course", "thanks", "thank you", "welcome", "hello", "good to see" } },
}
Speech.gestureAtMs = setmetatable({}, { __mode = "k" })
Speech.gestureCooldownMs = 4500
Speech.gestureTiles = 12

function Speech.gestureFor(text)
    local lowered = string.lower(tostring(text or ""))
    local padded = " " .. string.gsub(lowered, "[^%a']+", " ") .. " "
    local rules = Speech.gestureRules
    for index = 1, #rules do
        local rule = rules[index]
        for _, word in ipairs(rule.words) do
            if string.find(padded, " " .. word .. " ", 1, true) ~= nil then return rule.id, rule.chance end
        end
    end
    local _, shouts = string.gsub(lowered, "!", "")
    if shouts >= 2 then return "shout", 50 end
    return nil
end

function Speech.gestureOpen(shell, now)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or type(animations.presetOf) ~= "function" then return false end
    local clientOnly = type(isClient) == "function" and isClient() and not (type(isServer) == "function" and isServer())
    if clientOnly then return false end
    return now - (Speech.gestureAtMs[shell] or -1e12) >= Speech.gestureCooldownMs
end

function Speech.gestureFit(shell, target, now)
    local animations = ProjectALife.Animations
    if animations.current[shell] ~= nil or animations.active[shell] ~= nil then return false end
    if animations.combatHold[shell] == true or animations.readyCarry[shell] == true then return false end
    if animations.blocksLocomotion(shell) then return false end
    local combat = ProjectALife.Combat
    local postured = combat ~= nil and type(combat.postureUntilMs) == "table" and (combat.postureUntilMs[shell] or 0) > now
    if postured then return false end
    local ok, moving = pcall(function() return shell:isMoving() end)
    if not ok or moving == true then return false end
    local dx, dy
    pcall(function() dx, dy = shell:getX() - target:getX(), shell:getY() - target:getY() end)
    return dx ~= nil and dx * dx + dy * dy <= Speech.gestureTiles * Speech.gestureTiles
end

function Speech.gesture(shell, text, target)
    if type(instanceof) ~= "function" or not instanceof(target, "IsoPlayer") then return false end
    local now = nowMs()
    if not Speech.gestureOpen(shell, now) then return false end
    local id, chance = Speech.gestureFor(text)
    if id == nil or random(100) >= chance then return false end
    if not Speech.gestureFit(shell, target, now) then return false end
    Speech.gestureAtMs[shell] = now
    return ProjectALife.Animations.apply(shell, id) == true
end

function Speech.gestureNow(shell, id, target)
    local now = nowMs()
    if shell == nil or target == nil or not Speech.gestureOpen(shell, now) then return false end
    if not Speech.gestureFit(shell, target, now) then return false end
    Speech.gestureAtMs[shell] = now
    return ProjectALife.Animations.apply(shell, id) == true
end

Speech.scopes = { visitor = true, ambient = true }
Speech.settings.textRange = 14
Speech.metrics.textShown, Speech.metrics.textSuppressedFar = 0, 0

Speech.ambientEvents = {}
for event in pairs(Speech.chatEvents) do Speech.ambientEvents[event] = true end
for _, event in ipairs({ "GREET_PLAYER", "PASSING_PLAYER", "STARE_PLAYER", "SPOT_STRANGER", "SHOUT_HEARD_FRIENDLY",
        "SHOUT_HEARD_NEUTRAL", "SHOUT_HEARD_CAREFUL", "SHOUT_HEARD_HOSTILE", "TALK_FALLBACK_1", "TALK_FALLBACK_2",
        "TALK_FALLBACK_3", "TALK_FALLBACK_END", "COME_WITH_ME_REFUSE", "TENSE_SILENCE", "ANNOUNCE_ENTRY" }) do
    Speech.ambientEvents[event] = nil
end

function Speech.textRange()
    local value = nil
    if type(Speech.adapters.textRange) == "function" then value = tonumber(Speech.adapters.textRange()) end
    if value == nil then
        local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
        value = type(vars) == "table" and tonumber(vars.Text_VisitorRangeTiles) or nil
    end
    if value == nil or value ~= value then return Speech.settings.textRange end
    return math.max(0, math.min(60, math.floor(value)))
end

function Speech.scopeOf(options)
    local scope = type(options) == "table" and options.scope or nil
    if scope ~= nil and Speech.scopes[scope] == true then return scope end
    return nil
end

function Speech.pointOf(object)
    if object == nil then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, type(z) == "number" and z or 0
end

function Speech.sees(player, shell)
    if type(Speech.adapters.sees) == "function" then return Speech.adapters.sees(player, shell) == true end
    if LosUtil == nil or type(LosUtil.lineClear) ~= "function" or type(getCell) ~= "function" then return true end
    local px, py, pz = Speech.pointOf(player)
    local sx, sy, sz = Speech.pointOf(shell)
    if px == nil or sx == nil then return false end
    local ok, ray = pcall(function() return LosUtil.lineClear(getCell(), math.floor(px), math.floor(py), math.floor(pz),
        math.floor(sx), math.floor(sy), math.floor(sz), false) end)
    return ok and tostring(ray) ~= "Blocked"
end

function Speech.hearable(shell, player, options, range)
    local px, py, pz = Speech.pointOf(player)
    local sx, sy, sz = Speech.pointOf(shell)
    if px == nil or sx == nil or (px - sx) ^ 2 + (py - sy) ^ 2 > range * range then return false end
    if type(options.near) == "function" then
        local ok, near = pcall(options.near, player, shell)
        if ok and near == true then return true end
    end
    return math.floor(pz) == math.floor(sz) and Speech.sees(player, shell) == true
end

Speech.orderSettings = { marginTiles = 4, capTiles = 25, floorTiles = 6, minMs = 1000, maxMs = 120000, cap = 8 }
Speech.orders = {}
Speech.orderMetrics = { orders = 0, answeredFar = 0, refusedRange = 0, maxRange = 0 }

function Speech.orderReach(distance)
    local s = Speech.orderSettings
    local reach = math.ceil(tonumber(distance) or 0) + s.marginTiles
    if reach < s.floorTiles then reach = s.floorTiles end
    if reach > s.capTiles then reach = s.capTiles end
    return reach
end

function Speech.orderRule(entry, player, shell, now)
    if type(entry) ~= "table" then return false, "no_order" end
    if now > (tonumber(entry.untilMs) or 0) then return false, "order_expired" end
    if not Speech.alive(shell) then return false, "dead" end
    if type(shell.isAsleep) == "function" and shell:isAsleep() == true then return false, "asleep" end
    local px, py, pz = Speech.pointOf(player)
    local sx, sy, sz = Speech.pointOf(shell)
    if px == nil or sx == nil then return false, "no_body" end
    if math.floor(pz) ~= math.floor(sz) then return false, "other_floor" end
    local reach = math.min(Speech.orderSettings.capTiles, tonumber(entry.reach) or 0)
    if (px - sx) ^ 2 + (py - sy) ^ 2 > reach * reach then return false, "too_far" end
    if Speech.sees(player, shell) ~= true then return false, "blocked" end
    return true, nil
end

function Speech.orderNote(args, now)
    if type(args) ~= "table" or type(args.uid) ~= "string" or args.uid == "" or #args.uid > 160 then return false end
    if args.clear == true then
        Speech.orders[args.uid] = nil
        return true
    end
    local s = Speech.orderSettings
    local reach, ttl = tonumber(args.reach), tonumber(args.ttlMs)
    if reach == nil or ttl == nil or reach ~= reach or ttl ~= ttl then return false end
    reach = math.max(s.floorTiles, math.min(s.capTiles, reach))
    ttl = math.max(s.minMs, math.min(s.maxMs, ttl))
    now = tonumber(now) or nowMs()
    local count = 0
    for uid, entry in pairs(Speech.orders) do
        if now > entry.untilMs then Speech.orders[uid] = nil else count = count + 1 end
    end
    if Speech.orders[args.uid] == nil and count >= s.cap then return false end
    Speech.orders[args.uid] = { uid = args.uid, kind = tostring(args.kind or "order"), reach = reach, untilMs = now + ttl }
    return true
end

function Speech.orderLive(now)
    now = tonumber(now) or nowMs()
    for uid, entry in pairs(Speech.orders) do
        if now > entry.untilMs then Speech.orders[uid] = nil end
    end
    for _ in pairs(Speech.orders) do return true end
    return false
end

function Speech.orderOkFor(uid, player, shell, now)
    local entry = Speech.orders[tostring(uid)]
    if entry == nil then return false, "no_order" end
    return Speech.orderRule(entry, player, shell, tonumber(now) or nowMs())
end

function Speech.orderQaLine()
    local m = Speech.orderMetrics
    return "[ALIFE-QA] OrderRange: orders=" .. tostring(m.orders) .. " answeredFar=" .. tostring(m.answeredFar)
        .. " refusedRange=" .. tostring(m.refusedRange) .. " maxRange=" .. tostring(m.maxRange)
end

function Speech.localPlayers()
    if type(Speech.adapters.localPlayers) == "function" then return Speech.adapters.localPlayers() or {} end
    local list = {}
    if type(getSpecificPlayer) ~= "function" then return list end
    for index = 0, 3 do
        local ok, player = pcall(getSpecificPlayer, index)
        if ok and player ~= nil then list[#list + 1] = player end
    end
    return list
end

function Speech.textQaLine()
    return "[ALIFE-QA] Text: shown=" .. tostring(Speech.metrics.textShown or 0) .. " suppressedFar="
        .. tostring(Speech.metrics.textSuppressedFar or 0) .. " range=" .. tostring(Speech.textRange())
end

function Speech.say(shell, text, options)
    options = type(options) == "table" and options or {}
    text = ProjectALife.AudioPolicy.caption(text)
    if shell == nil or type(text) ~= "string" or text == "" then return false end
    if Speech.refusedDead(shell) then return false end
    text = Speech.gendered(text, Speech.sexCode(options.psex) or Speech.sexOf(options.face), shell)

    if options.downedOk ~= true then
        local reason = Speech.quietReason(shell, nil, nil)
        if reason == "downed" or (reason ~= nil and options.chat == true) then
            Speech.metrics.quieted = (Speech.metrics.quieted or 0) + 1
            return false
        end
    end
    local uid = Speech.variable(shell, "ALifeUID")
    if options.face ~= nil then
        Speech.face(shell, options.face)
        if options.gesture ~= false then pcall(Speech.gesture, shell, text, options.face) end
    end
    Speech.metrics.said = Speech.metrics.said + 1
    local kind = "directed"
    if options.final == true then
        kind = "final"
    elseif Speech.scopeOf(options) == "ambient" then
        kind = "ambient"
    end
    local range = Speech.scopeOf(options) ~= nil and Speech.textRange() or 0
    local server = type(Speech.adapters.isServer) == "function" and Speech.adapters.isServer()
        or (Speech.adapters.isServer == nil and type(isServer) == "function" and isServer())
    if not server then
        if range > 0 then
            local viewers = Speech.localPlayers()
            local visible = #viewers == 0
            for _, viewer in ipairs(viewers) do
                if Speech.hearable(shell, viewer, options, range) then visible = true; break end
            end
            if not visible then
                Speech.metrics.textSuppressedFar = Speech.metrics.textSuppressedFar + 1
                return true
            end
            Speech.metrics.textShown = Speech.metrics.textShown + 1
        end
        return draw(shell, text, uid, kind)
    end
    local sx, sy
    pcall(function() sx, sy = shell:getX(), shell:getY() end)
    if sx == nil then return false end

    local radius = math.max(1, math.min(120, tonumber(options.earshot) or Speech.settings.earshot))
    local reach = radius * radius
    local sent, eligible = 0, 0
    for _, player in ipairs(players()) do
        local px, py
        pcall(function() px, py = player:getX(), player:getY() end)
        if px ~= nil and (px - sx) ^ 2 + (py - sy) ^ 2 <= reach then
            eligible = eligible + 1
            if range <= 0 or Speech.hearable(shell, player, options, range) then
                local payload = { uid = tostring(uid or ""), text = text, x = sx, y = sy, kind = kind }
                local ok = false
                if type(Speech.adapters.send) == "function" then
                    ok = pcall(Speech.adapters.send, player, "ProjectALife", "speech", payload)
                elseif type(sendServerCommand) == "function" then
                    ok = pcall(sendServerCommand, player, "ProjectALife", "speech", payload)
                end
                if ok then sent = sent + 1 end
            end
        end
    end
    Speech.metrics.sent = Speech.metrics.sent + sent
    if range > 0 then
        if sent > 0 then
            Speech.metrics.textShown = Speech.metrics.textShown + 1
        elseif eligible > 0 then
            Speech.metrics.textSuppressedFar = Speech.metrics.textSuppressedFar + 1
            return true
        end
    end
    return sent > 0
end

function Speech.findShell(uid)
    if uid == nil or uid == "" then return nil end
    local watchdog = ProjectALife.Watchdog
    local bound = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    if bound ~= nil and bound.shell ~= nil then return bound.shell end
    local found = nil
    pcall(function()
        local list = getCell():getZombieList()
        for index = 0, list:size() - 1 do
            local shell = list:get(index)
            if tostring(Speech.variable(shell, "ALifeUID") or "") == uid then found = shell; return end
        end
    end)
    return found
end

function Speech.onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "speech" or type(arguments) ~= "table" then return end
    local shell = Speech.findShell(tostring(arguments.uid or ""))
    if shell == nil or type(arguments.text) ~= "string" then return end
    local kind = arguments.kind
    if type(kind) ~= "string" or Speech.kinds[kind] ~= true then kind = "directed" end
    draw(shell, arguments.text, arguments.uid, kind)
end

if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function"
        and type(isClient) == "function" and isClient() then
    Events.OnServerCommand.Add(Speech.onServerCommand)
end

function Speech.standingTiers(tier)
    if tier == "hated" then return { "worst", "bad", "neutral" } end
    if tier == "hostile" or tier == "careful" then return { "bad", "neutral" } end
    if tier == "friendly" or tier == "allied" then return { "good", "neutral" } end
    if tier == "neutral" then return { "neutral" } end
    return nil
end

function Speech.reputationTiers(record, player)
    if player == nil or type(record) ~= "table" or not Speech.authoritative() then return nil end
    local standing, personal = ProjectALife.Standing, ProjectALife.PersonalRep
    local factionEnabled = standing ~= nil and type(standing.enabledHere) == "function" and standing.enabledHere()
    if not factionEnabled and (personal == nil or personal.enabled ~= true) then return nil end
    local key = Speech.playerKey(player)
    if key == nil then return nil end
    if factionEnabled and type(standing.tierFor) == "function" then
        local ok, tier = pcall(standing.tierFor, key, record.factionId)
        if not ok then return nil end
        if tier ~= nil then return Speech.standingTiers(tier) end
    end
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.recordedStatus) == "function" then
        local ok, tier = pcall(reputation.recordedStatus, player, record)
        if not ok then return nil end
        if tier ~= nil then return Speech.standingTiers(tier) end
    end
    local levels = ProjectALife.RepLevels
    if personal ~= nil and type(personal.view) == "function" and levels ~= nil and type(levels.tiers) == "function" then
        local ok, view = pcall(personal.view, player)
        if ok and type(view) == "table" and view.level ~= nil then return levels.tiers(view.level) end
    end
    return nil
end

function Speech.contextFor(record, player, overrides)
    local clock = Speech.clock()
    local roles = ProjectALife.DialogueRoles
    local who = roles.describe(record, clock.daysSurvived)
    local context = { role = who.role, register = who.register, temperament = who.temperament, sex = who.sex,
        day = clock.daysSurvived, hour = clock.hour, voice = who.voice, worldUid = type(record) == "table" and record.uid or nil }
    if player ~= nil then
        context.psex = Speech.sexOf(player)
        context.repTiers = Speech.reputationTiers(record, player)
        local relations = ProjectALife.Relations
        if relations ~= nil and type(relations.playerStance) == "function" then
            local ok, stance = pcall(relations.playerStance, record, player)
            if ok and stance ~= nil then context.stance = stance == "allied" and "friendly" or stance end
        end
    end
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do context[key] = value end
    end
    return context
end

function Speech.playerKey(player)
    if player == nil or type(player.getUsername) ~= "function" then return nil end
    local reputation = ProjectALife.Reputation
    if player ~= nil and reputation ~= nil and type(reputation.playerKey) == "function" then
        local ok, key = pcall(reputation.playerKey, player)
        if ok and key ~= nil then return tostring(key) end
    end
    local ok, name = pcall(player.getUsername, player)
    return ok and name and tostring(name) or nil
end

function Speech.combatFallback(event)
    if event == "HURT" then return "Aagh--!" end
    if event == "COMBAT_ATTACK" then return "Get back!" end
    return nil
end

function Speech.bark(record, shell, event, options)
    options = type(options) == "table" and options or {}
    local data = ProjectALife.DialogueData
    if data == nil or shell == nil then return nil end
    data.load()
    local allowed, reason = Speech.allows(shell, type(record) == "table" and record or nil, event, nil, nil)
    if not allowed then return nil end
    local context = options.contextValue or Speech.contextFor(record, options.player, options.context)
    local uid = type(record) == "table" and record.uid or Speech.variable(shell, "ALifeUID")
    local playerKey = options.player ~= nil and Speech.playerKey(options.player) or nil
    local chosen = Speech.pick(options.records or data.barks[event], context, uid, playerKey, options.vars)
    if chosen == nil then
        local fallback = Speech.combatFallback(event)
        if fallback == nil then return nil end
        chosen = { t = fallback }
    end
    local text = Speech.render(chosen.t, options.vars, shell, type(context) == "table" and context.psex or nil)
    local scope = options.scope
    if scope == nil and Speech.ambientEvents[event] == true then scope = "ambient" end
    if not Speech.say(shell, text, { face = options.face or options.player, downedOk = reason == "downed",
            scope = scope, near = options.near, final = Speech.finalEvents[event] == true }) then return nil end
    Speech.remember(uid, playerKey, chosen.t)

    return text
end

Speech.combatBarks = setmetatable({}, { __mode = "k" })
Speech.combatGroups = {}
Speech.combatPruneAtMs = 0

function Speech.combatBark(shell, event, attack, now)
    if not Speech.authoritative() or not Speech.alive(shell) then return nil end
    if event ~= "HURT" and event ~= "COMBAT_ATTACK" then return nil end
    local registry = ProjectALife.ActorRegistry
    local uid = Speech.variable(shell, "ALifeUID")
    if uid == nil or registry == nil or type(registry.read) ~= "function" then return nil end
    local record = registry.read(tostring(uid))
    if record == nil or record.lifecycle ~= "active" then return nil end
    now = tonumber(now) or nowMs()
    local state = Speech.combatBarks[shell] or {}
    if now < (state[event] or 0) then return nil end
    local memory = type(record.memory) == "table" and record.memory or {}
    local groupKey = tostring(memory.groupId or ("solo:" .. tostring(uid))) .. ":" .. event
    if now < (Speech.combatGroups[groupKey] or 0) then return nil end
    local context = { attack = attack }
    if type(memory.person) == "table" then context.register = "civilian" end
    local text = Speech.bark(record, shell, event, { context = context, scope = "ambient" })
    if text == nil then return nil end
    state[event] = now + (event == "HURT" and 6000 or 12000)
    Speech.combatBarks[shell] = state
    Speech.combatGroups[groupKey] = now + (event == "HURT" and 2000 or 4000)
    if now >= Speech.combatPruneAtMs then
        for key, untilMs in pairs(Speech.combatGroups) do
            if now >= untilMs then Speech.combatGroups[key] = nil end
        end
        Speech.combatPruneAtMs = now + 30000
    end
    return text
end

function Speech.corpusCaption(shell, event, uid, attack, psex)
    local data = ProjectALife.DialogueData
    local registry = ProjectALife.ActorRegistry
    if data == nil or registry == nil or type(registry.read) ~= "function" or event == nil then return Speech.combatFallback(event) end
    data.load()
    local pool = data.barks[event]
    if pool == nil or #pool == 0 then return Speech.combatFallback(event) end
    uid = uid or Speech.variable(shell, "ALifeUID")
    local record = uid ~= nil and registry.read(tostring(uid)) or nil
    if record == nil then return Speech.combatFallback(event) end
    local context = Speech.contextFor(record, nil)
    context.psex = Speech.sexCode(psex) or Speech.sexNear(shell)
    context.attack = attack
    local chosen = Speech.pick(pool, context, record.uid, nil)
    if chosen == nil then return Speech.combatFallback(event) end
    Speech.remember(record.uid, nil, chosen.t)
    return Speech.render(chosen.t, nil, shell, context.psex)
end

Speech.corpseQueue = { list = {}, searchMs = 8000, budget = 3 }

function Speech.shellPosition(shell)
    return shell:getX(), shell:getY(), shell:getZ()
end

function Speech.noteDeath(shell)
    if shell == nil or type(shell.isSpeaking) ~= "function" then return false end
    local readOk, speaking = pcall(shell.isSpeaking, shell)
    if not readOk or speaking ~= true then return false end
    local ok, x, y, z = pcall(Speech.shellPosition, shell)
    if not ok or tonumber(x) == nil or tonumber(y) == nil then return false end
    local queue = Speech.corpseQueue
    queue.list[#queue.list + 1] = { x = x, y = y, z = tonumber(z) or 0, atMs = nowMs() }
    Speech.metrics.hushQueued = (Speech.metrics.hushQueued or 0) + 1
    return true
end

function Speech.hushNear(entry)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local bx, by, bz = math.floor(entry.x), math.floor(entry.y), math.floor(entry.z)
    local hushed = false
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(bx + dx, by + dy, bz)
            local bodies = square ~= nil and type(square.getDeadBodys) == "function" and square:getDeadBodys() or nil
            local count = bodies ~= nil and type(bodies.size) == "function" and bodies:size() or 0
            for index = 0, count - 1 do
                local body = bodies:get(index)
                if body ~= nil and type(body.IsSpeaking) == "function" and type(body.Say) == "function"
                        and body:IsSpeaking() == true then
                    body:Say(" ")
                    Speech.metrics.corpsesHushed = (Speech.metrics.corpsesHushed or 0) + 1
                    hushed = true
                end
            end
        end
    end
    return hushed
end

function Speech.settleCorpses(now)
    local queue = Speech.corpseQueue
    local checked, index = 0, 1
    while checked < queue.budget and index <= #queue.list do
        local entry = queue.list[index]
        checked = checked + 1
        if Speech.hushNear(entry) then
            table.remove(queue.list, index)
        elseif (tonumber(now) or 0) - entry.atMs > queue.searchMs then
            Speech.metrics.hushLost = (Speech.metrics.hushLost or 0) + 1
            table.remove(queue.list, index)
        else
            index = index + 1
        end
    end
    return checked
end

function Speech.tickCorpses()
    if #Speech.corpseQueue.list == 0 then return end
    Speech.settleCorpses(nowMs())
end

if type(Events) == "table" then
    if Events.OnZombieDead ~= nil and type(Events.OnZombieDead.Add) == "function" then
        Events.OnZombieDead.Add(Speech.noteDeath)
    end
    if Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
        Events.OnTick.Add(Speech.tickCorpses)
    end
end

function Speech.reset()
    Speech.combatBarks = setmetatable({}, { __mode = "k" })
    Speech.combatGroups = {}
    Speech.combatPruneAtMs = 0
    Speech.recent = {}
    Speech.heard = {}
    Speech.metrics = { said = 0, sent = 0, drawn = 0, picked = 0, exhausted = 0, missing = 0, repTier = {}, repFallback = 0,
        speechRefusedDead = 0, textShown = 0, textSuppressedFar = 0 }
    Speech.corpseQueue.list = {}
end

return Speech
