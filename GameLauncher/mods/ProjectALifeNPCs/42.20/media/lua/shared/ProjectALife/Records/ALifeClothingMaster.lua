ProjectALife = ProjectALife or {}

local Master = {
    PATH = "alife_runtime/clothing/clothing_master.alife",
    FALLBACK_MOD_ID = "ProjectALifeNPCs",
    VERSION = 1,
    SEASONS = { "spring", "summer", "autumn", "winter" },
    LETTERS = { A = 1, B = 2, C = 3, D = 4 },
    WARM = { n = "none", l = "light", m = "medium", h = "heavy" },
    COOL = { n = "neutral", i = "insulating", b = "breathable" },
    RAIN = { n = "none", s = "some", g = "good" },
    CONF = { l = "low", m = "medium", h = "high" },
    ISSUE = { m = "military", l = "law", f = "fire", d = "medical", p = "prison", w = "work", s = "sports", o = "formal", c = "civilian" },
    FLAG = { n = "novelty", c = "costume", i = "improvised", d = "special", h = "debug", A = "animal", u = "uniqueModel",
        s = "serious", p = "protective", H = "heavy", ["*"] = "hero" },
    MODE = { a = "any", w = "winterOnly", m = "warmOnly", c = "coolOnly", t = "transitional", g = "marginal" },
    state = nil,
    stats = { loads = 0, parsed = 0, lookups = 0 },
}
ProjectALife.ClothingMaster = Master

function Master.modId()
    local catalog = ProjectALife.Catalog
    if type(catalog) == "table" and type(catalog.MOD_ID) == "string" and catalog.MOD_ID ~= "" then
        return catalog.MOD_ID
    end
    return Master.FALLBACK_MOD_ID
end

function Master.newState()
    return {
        ok = false, rules = {}, locations = {}, locationIndex = {}, categories = {}, subcategories = {},
        whys = {}, reasons = {}, roles = {}, styles = {}, avoids = {}, exclusions = {}, lines = {}, order = {},
        roleSets = {}, issueSets = {}, flagSets = {},
        parsed = {}, short = {}, excludeCache = {}, count = 0,
    }
end

function Master.ingest(state, line)
    if line == "" then return end
    if string.sub(line, 1, 14) == "alife-clothing" then
        local version, research, count = string.match(line, "^alife%-clothing (%d+) (%S+) (%d+)")
        state.version = tonumber(version)
        state.research = research
        state.count = tonumber(count) or 0
        return
    end
    if string.sub(line, 2, 2) ~= "\t" then return end
    local tag, rest = string.sub(line, 1, 1), string.sub(line, 3)
    if tag == "i" then
        local id = string.match(rest, "^([^\t]+)\t")
        if id ~= nil then
            id = "Base." .. id
            if state.lines[id] == nil then state.order[#state.order + 1] = id end
            state.lines[id] = line
        end
    elseif tag == "x" then
        local a, b, z = string.match(rest, "^(%d+)\t(%d+)\t(%d+)")
        a, b, z = tonumber(a), tonumber(b), tonumber(z)
        if a ~= nil and b ~= nil and z ~= nil then
            local row = state.exclusions[a]
            if row == nil then
                row = {}
                state.exclusions[a] = row
            end
            row[b] = z
        end
    elseif tag == "t" then
        local season, role, category, ids = string.match(rest, "^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
        if season ~= nil then state.short[season .. "|" .. role .. "|" .. category] = ids end
    elseif tag == "r" then
        local key, value = string.match(rest, "^([^\t]+)\t(.*)$")
        if key ~= nil then state.rules[key] = value end
    elseif tag == "l" then
        state.locations[#state.locations + 1] = rest
        state.locationIndex[rest] = #state.locations
    elseif tag == "c" then
        state.categories[#state.categories + 1] = rest
    elseif tag == "s" then
        state.subcategories[#state.subcategories + 1] = rest
    elseif tag == "w" then
        state.whys[#state.whys + 1] = rest
    elseif tag == "z" then
        state.reasons[#state.reasons + 1] = rest
    elseif tag == "p" then
        state.roles[#state.roles + 1] = rest
    elseif tag == "y" then
        state.styles[#state.styles + 1] = rest
    elseif tag == "a" then
        state.avoids[#state.avoids + 1] = rest
    end
end

function Master.finish(state)
    state.ok = state.version == Master.VERSION and #state.order > 0 and #state.locations > 0
    state.items = #state.order
    return state
end

function Master.readFile(state)
    if type(getModFileReader) ~= "function" then return false, "mod_file_reader_unavailable" end
    local opened, reader = pcall(getModFileReader, Master.modId(), Master.PATH, false)
    if not opened or reader == nil or reader.readLine == nil then return false, "not_found" end
    local ok, failure = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            Master.ingest(state, tostring(line))
        end
    end)
    if reader.close ~= nil then pcall(reader.close, reader) end
    if not ok then return false, tostring(failure) end
    return true
end

function Master.load()
    local current = Master.state
    if current ~= nil and (current.ok or current.modId == Master.modId()) then return current.ok end
    local state = Master.newState()
    state.modId = Master.modId()
    Master.stats.loads = Master.stats.loads + 1
    local read, reason = Master.readFile(state)
    if read then Master.finish(state) else state.failure = reason end
    Master.state = state
    return state.ok
end

function Master.loadText(text)
    local state = Master.newState()
    Master.stats.loads = Master.stats.loads + 1
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do Master.ingest(state, line) end
    Master.finish(state)
    Master.state = state
    return state.ok
end

function Master.reset()
    Master.state = nil
    Master.stats.parsed = 0
    Master.stats.lookups = 0
end

function Master.available()
    return Master.load() == true
end

function Master.count()
    if not Master.load() then return 0 end
    return Master.state.items
end

function Master.rule(key)
    if not Master.load() then return nil end
    local value = Master.state.rules[key]
    if value == nil then return nil end
    local number = tonumber(value)
    if number ~= nil then return number end
    return value
end

function Master.ruleList(key)
    local list = {}
    local value = Master.rule(key)
    if type(value) ~= "string" then return list end
    for item in string.gmatch(value .. ",", "([^,]*),") do
        if item ~= "" then list[#list + 1] = item end
    end
    return list
end

function Master.ruleSet(key)
    local set = {}
    for _, item in ipairs(Master.ruleList(key)) do set[item] = true end
    return set
end

function Master.fullType(value)
    value = tostring(value or "")
    if value == "" or value == "none" or value == "remove" then return nil end
    if string.find(value, ".", 1, true) == nil then return "Base." .. value end
    return value
end

function Master.normalizeLocation(value)
    if value == nil then return nil end
    local text = string.lower(tostring(value))
    if text == "" then return nil end
    if string.find(text, ":", 1, true) == nil then text = "base:" .. text end
    return text
end

function Master.seasonIndex(season)
    if type(season) == "number" then
        if season >= 1 and season <= 4 then return math.floor(season) end
        return nil
    end
    if type(season) ~= "string" then return nil end
    local lower = string.lower(season)
    for index, name in ipairs(Master.SEASONS) do
        if name == lower then return index end
    end
    if lower == "fall" then return 3 end
    return Master.LETTERS[string.upper(season)]
end

function Master.numberOrNil(text)
    if text == nil or text == "" then return nil end
    return tonumber(text)
end

function Master.cached(cache, text, fill)
    local set = cache[text]
    if set == nil then
        set = {}
        fill(text, set)
        cache[text] = set
    end
    return set
end

function Master.fillRoles(text, set)
    for role in string.gmatch(text .. ",", "([^,]*),") do
        if role ~= "" then set[role] = true end
    end
end

function Master.fillIssue(text, set)
    for letter in string.gmatch(text, ".") do
        local name = Master.ISSUE[letter]
        if name ~= nil then set[name] = true end
    end
end

function Master.fillFlags(text, set)
    for letter in string.gmatch(text, ".") do
        local name = Master.FLAG[letter]
        if name ~= nil then set[name] = true end
    end
end

function Master.fillClimate(item)
    local insulation, wind, water, ideal = string.match(item.climateText, "^([^;]*);([^;]*);([^;]*);([^;]*)$")
    item.insulation = tonumber(insulation) or 0
    item.wind = Master.numberOrNil(wind) or false
    item.water = Master.numberOrNil(water) or false
    item.idealC = Master.numberOrNil(ideal) or false
    item.climateDone = true
end

function Master.fillClass(item)
    local text = item.classText
    item.warmth = Master.WARM[string.sub(text, 1, 1)] or "none"
    item.cooling = Master.COOL[string.sub(text, 2, 2)] or "neutral"
    item.rain = Master.RAIN[string.sub(text, 3, 3)] or "none"
    item.assumed = string.sub(text, 4, 4) == "1"
    item.classDone = true
end

function Master.fillProtection(item)
    local bite, scratch, bullet = string.match(item.protectionText, "^(%-?%d+),(%-?%d+),(%-?%d+)")
    item.bite, item.scratch, item.bullet = tonumber(bite) or 0, tonumber(scratch) or 0, tonumber(bullet) or 0
    item.protectionDone = true
end

function Master.fillWhy(item)
    local list, position = {}, 0
    for number in string.gmatch(item.whyText .. ",", "([^,]*),") do
        position = position + 1
        list[position] = tonumber(number)
    end
    item.whyIndex = list
    item.whyDone = true
end

Master.LAZY = {
    insulation = { "climateDone", Master.fillClimate }, wind = { "climateDone", Master.fillClimate },
    water = { "climateDone", Master.fillClimate }, idealC = { "climateDone", Master.fillClimate },
    warmth = { "classDone", Master.fillClass }, cooling = { "classDone", Master.fillClass },
    rain = { "classDone", Master.fillClass }, assumed = { "classDone", Master.fillClass },
    bite = { "protectionDone", Master.fillProtection }, scratch = { "protectionDone", Master.fillProtection },
    bullet = { "protectionDone", Master.fillProtection }, whyIndex = { "whyDone", Master.fillWhy },
}
Master.LAZY_META = {
    __index = function(item, key)
        local rule = Master.LAZY[key]
        if rule == nil or item[rule[1]] == true then return nil end
        rule[2](item)
        return item[key]
    end,
}

function Master.parse(state, id, line)
    local f, count = {}, 0
    for field in string.gmatch(line .. "\t", "([^\t]*)\t") do
        count = count + 1
        f[count] = field
    end
    local s1, s2, s3, s4 = string.byte(f[8] or "2222", 1, 4)
    local roleIndex = tonumber(f[14])
    local roleText = state.roles[roleIndex or 0] or ""
    local item = { id = id, name = f[3], location = state.locations[tonumber(f[4]) or 0],
        category = state.categories[tonumber(f[5]) or 0], subcategory = state.subcategories[tonumber(f[6]) or 0],
        layer = f[7], seasons = { (s1 or 50) - 48, (s2 or 50) - 48, (s3 or 50) - 48, (s4 or 50) - 48 },
        ruleIndex = tonumber(f[10]), whyText = f[9] or "", climateText = f[11] or "", classText = f[12] or "nnn0",
        protectionText = f[13] or "", roleIndex = roleIndex, roleText = roleText,
        roles = Master.cached(state.roleSets, roleText, Master.fillRoles),
        issue = Master.cached(state.issueSets, f[15] or "", Master.fillIssue),
        flags = Master.cached(state.flagSets, f[16] or "", Master.fillFlags),
        anachronism = Master.CONF[f[17] or ""], styleIndex = tonumber(f[18]) or 0, avoidIndex = tonumber(f[19]) or 0,
        mode = Master.MODE[f[21] or "a"] or "any", confidence = Master.CONF[f[22] or "h"] or "high" }
    if f[20] ~= nil and f[20] ~= "" then
        local variants = {}
        for part in string.gmatch(f[20] .. ";", "([^;]*);") do
            if part ~= "" then variants[#variants + 1] = Master.fullType(part) end
        end
        item.variants = variants
        item.variant = variants[1]
    end
    return setmetatable(item, Master.LAZY_META)
end

function Master.get(fullType)
    if not Master.load() then return nil end
    fullType = Master.fullType(fullType)
    if fullType == nil then return nil end
    local state = Master.state
    Master.stats.lookups = Master.stats.lookups + 1
    local item = state.parsed[fullType]
    if item ~= nil then return item end
    local line = state.lines[fullType]
    if line == nil then return nil end
    item = Master.parse(state, fullType, line)
    Master.stats.parsed = Master.stats.parsed + 1
    state.parsed[fullType] = item
    return item
end

function Master.has(fullType)
    if not Master.load() then return false end
    fullType = Master.fullType(fullType)
    return fullType ~= nil and Master.state.lines[fullType] ~= nil
end

function Master.score(fullType, season)
    local item = Master.get(fullType)
    local index = Master.seasonIndex(season)
    if item == nil or index == nil then return nil end
    return item.seasons[index]
end

function Master.roleFit(fullType)
    local item = Master.get(fullType)
    if item == nil then return nil end
    return item.roles
end

function Master.whyOf(item, season)
    local index = Master.seasonIndex(season)
    if item == nil or index == nil or not Master.load() then return nil end
    return Master.state.whys[item.whyIndex[index] or 0]
end

function Master.ruleTextOf(item)
    if item == nil or not Master.load() then return nil end
    return Master.state.whys[item.ruleIndex or 0]
end

function Master.stylesOf(item)
    local list = {}
    if item == nil or not Master.load() then return list end
    local text = Master.state.styles[item.styleIndex or 0]
    if text == nil then return list end
    for tag in string.gmatch(text .. ",", "([^,]*),") do
        if tag ~= "" then list[#list + 1] = tag end
    end
    return list
end

function Master.avoidOf(item)
    local list = {}
    if item == nil or not Master.load() then return list end
    local text = Master.state.avoids[item.avoidIndex or 0]
    if text == nil then return list end
    for reason in string.gmatch(text .. "|", "([^|]*)|") do
        if reason ~= "" then list[#list + 1] = reason end
    end
    return list
end

function Master.excludes(location)
    if not Master.load() then return nil end
    local state = Master.state
    location = Master.normalizeLocation(location)
    if location == nil then return nil end
    local cached = state.excludeCache[location]
    if cached ~= nil then return cached or nil end
    local index = state.locationIndex[location]
    local row = index ~= nil and state.exclusions[index] or nil
    if row == nil then
        state.excludeCache[location] = false
        return nil
    end
    local result = {}
    for other, reason in pairs(row) do
        result[state.locations[other] or tostring(other)] = state.reasons[reason] or ""
    end
    state.excludeCache[location] = result
    return result
end

function Master.collision(first, second)
    local row = Master.excludes(first)
    second = Master.normalizeLocation(second)
    if row == nil or second == nil then return nil end
    return row[second]
end

function Master.shortlist(season, role, category)
    if not Master.load() then return nil end
    local index = Master.seasonIndex(season)
    if index == nil then return nil end
    local text = Master.state.short[Master.SEASONS[index] .. "|" .. tostring(role) .. "|" .. tostring(category)]
    if text == nil then return nil end
    local list = {}
    for id in string.gmatch(text .. ",", "([^,]*),") do
        if id ~= "" then list[#list + 1] = Master.fullType(id) end
    end
    return list
end

function Master.each(visit)
    if not Master.load() then return 0 end
    local order = Master.state.order
    for index = 1, #order do
        local item = Master.get(order[index])
        if item ~= nil and visit(item) == true then return index end
    end
    return #order
end

return Master
