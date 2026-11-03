require "ProjectALife/Records/ALifeClothingMaster"

ProjectALife = ProjectALife or {}

local Master = ProjectALife.ClothingMaster

Master.GROUPS = {
    underwearbottom = "under", underweartop = "under", underwear = "under", underwearextra1 = "under",
    underwearextra2 = "under", torso1legs1 = "under", legs1 = "under",
    torso1 = "top", tshirt = "top", shortsleeveshirt = "top", tanktop = "top", shirt = "top", sweater = "top",
    jersey = "top", jacket = "top", jacket_down = "top", jacket_bulky = "top", jackethat = "top",
    jackethat_bulky = "top", sweaterhat = "top", vesttexture = "top", torsoextra = "top", torsoextravest = "top",
    torsoextravestbullet = "top", cuirass = "top", sportshoulderpad = "top", sportshoulderpadontop = "top",
    pants = "bottom", pants_skinny = "bottom", shortpants = "bottom", shortsshort = "bottom", skirt = "bottom",
    longskirt = "bottom", pantsextra = "bottom",
    dress = "full", longdress = "full", fullsuit = "full", fullsuithead = "full", fullsuitheadscba = "full",
    boilersuit = "full", bodycostume = "full", bathrobe = "full", fullrobe = "full", jacketsuit = "full",
    fulltop = "full",
    hat = "head", fullhat = "head", mask = "head", maskeyes = "head", maskfull = "head", ears = "head",
    eartop = "head", nose = "head", lefteye = "head", righteye = "head", eyes = "head",
    shoes = "feet", socks = "feet", gaiter_left = "feet", gaiter_right = "feet", calf_left_texture = "feet",
    calf_right_texture = "feet",
    hands = "hands", handsleft = "hands", handsright = "hands", forearm_left = "hands", forearm_right = "hands",
    neck = "neck", neck_texture = "neck", necklace = "neck", necklace_long = "neck", scarf = "neck",
    back = "back", satchel = "back", fannypackfront = "back", fannypackback = "back", webbing = "back",
    ammostrap = "back", shoulderholster = "back", ankleholster = "back", scba = "back", scbanotank = "back",
}

Master.OUTER_LOCATIONS = { jacket = true, jacket_down = true, jacket_bulky = true, jackethat = true,
    jackethat_bulky = true, vesttexture = true, torsoextravest = true, torsoextravestbullet = true, cuirass = true }

Master.LAYERS = { u = "underwear", a = "accessory", b = "base", m = "mid", o = "outer" }

Master.DEFAULT_UNDER = {
    f = { bottom = "Base.Underpants_White", top = "Base.Bra_Straps_White" },
    m = { bottom = "Base.Briefs_White" },
}

Master.ROLES = { "civilian", "formal", "work", "rural", "sports", "law", "medical", "fire", "military" }

Master.SEASON_JACKET = { spring = 35, summer = 8, autumn = 55, winter = 88 }
Master.SEASON_SCARF = { spring = 0, summer = 0, autumn = 10, winter = 35 }
Master.SEASON_GLOVES = { spring = 0, summer = 0, autumn = 8, winter = 40 }
Master.SKIP_FLAGS = { "novelty", "costume", "debug", "animal", "improvised" }
Master.TAGS = {
    surplus_jacket = { category = "jacket", words = { "army", "field", "coatarmy", "military", "surplus" } },
    cap = { category = "hat", words = { "cap", "baseball" } },
    hat = { category = "hat", words = {} },
    scarf = { category = "scarf", words = {} },
    gloves = { category = "gloves", words = {} },
    vest = { category = "vest", words = {} },
}

function Master.entryType(entry)
    if type(entry) == "string" then return entry end
    if type(entry) ~= "table" then return nil end
    return entry.itemType or entry[1]
end

function Master.entryTint(entry)
    if type(entry) ~= "table" then return "" end
    local tint = entry.tint
    if tint == nil then tint = entry[2] end
    if type(tint) ~= "string" then return "" end
    return tint
end

function Master.locationName(location)
    if type(location) ~= "string" then return nil end
    return string.match(location, "^[^:]*:(.*)$") or location
end

function Master.rank(location)
    if not Master.load() then return 0 end
    return Master.state.locationIndex[Master.normalizeLocation(location) or ""] or 0
end

Master.layers, Master.layersFor = {}, nil

function Master.layerOf(itemType)
    local item = Master.get(itemType)
    if item == nil or item.location == nil then return nil end
    if Master.layersFor ~= Master.state then Master.layers, Master.layersFor = {}, Master.state end
    local known = Master.layers[item.id]
    if known ~= nil then return known end
    local name = Master.locationName(item.location)
    local layer = Master.LAYERS[item.layer] or "base"
    local group = Master.GROUPS[name] or "accessory"
    if item.layer == "u" and (group == "top" or group == "bottom") then group = "under" end
    local excludes = {}
    local row = Master.excludes(item.location)
    if row ~= nil then
        for other in pairs(row) do excludes[#excludes + 1] = other end
        table.sort(excludes)
    end
    local outer = layer == "outer" or Master.OUTER_LOCATIONS[name] == true
    local info = {
        itemType = item.id, location = item.location, name = name, group = group, layer = layer, outer = outer,
        hides = {}, excludes = excludes, rank = Master.rank(item.location), warmth = tonumber(item.insulation) or 0,
        isUnderwear = group == "under", category = item.category,
    }
    Master.layers[item.id] = info
    return info
end

Master.FALLBACK = {
    { "underweartop", "under", { "Bra_", "BoobTube", "Corset" } },
    { "underwearbottom", "under", { "Underpants", "Briefs", "Boxers", "AthleticCup" } },
    { "underwear", "under", { "Bikini", "Swimsuit", "SwimTrunks" } },
    { "dress", "full", { "Dress", "Boilersuit", "Jumpsuit", "Coveralls" } },
    { "pants", "bottom", { "Trousers", "Pants", "Shorts", "Skirt", "Jeans", "Dungarees" } },
    { "shoes", "feet", { "Shoes", "Boots", "Trainers", "Sandals" } },
    { "hat", "head", { "Hat_", "Cap", "Helmet", "Beret" } },
    { "scarf", "neck", { "Scarf" } },
    { "gloves", "hands", { "Gloves" } },
    { "shirt", "top", { "Tshirt", "Shirt", "Jumper", "Sweater", "Jacket", "Vest", "Hoodie", "Coat", "Blouse" } },
}

function Master.infoOf(itemType)
    local info = Master.layerOf(itemType)
    if info ~= nil then return info end
    local text = tostring(Master.fullType(itemType) or "")
    for _, row in ipairs(Master.FALLBACK) do
        for _, word in ipairs(row[3]) do
            if string.find(text, word, 1, true) ~= nil then
                return { itemType = text, location = "base:" .. row[1], name = row[1], group = row[2], layer = "base",
                    outer = false, hides = {}, excludes = {}, rank = 9000, warmth = 0.2, isUnderwear = row[2] == "under",
                    synthetic = true }
            end
        end
    end
    return { itemType = text, location = "base:item", name = "item", group = "accessory", layer = "accessory", outer = false,
        hides = {}, excludes = {}, rank = 9500, warmth = 0, isUnderwear = false, synthetic = true }
end

function Master.baseKind(itemType)
    local info = Master.layerOf(itemType)
    if info == nil then return nil end
    if info.group == "full" then return "full" end
    if info.layer == "base" and (info.group == "top" or info.group == "bottom") then return info.group end
    return nil
end

function Master.collides(first, second)
    if first == nil or second == nil then return nil end
    if first == second then return "same location" end
    local reason = Master.collision(first, second)
    if reason == nil then reason = Master.collision(second, first) end
    return reason
end

function Master.accepts(entries, itemType, options)
    local want = Master.layerOf(itemType)
    if want == nil then return false, {}, "unknown_item" end
    if want.isUnderwear and not (type(options) == "table" and options.underwear == true) then
        return false, {}, "underwear_item"
    end
    local replaced, why = {}, nil
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local have = Master.layerOf(Master.entryType(entry))
        if have ~= nil then
            local reason = Master.collides(want.location, have.location)
            if reason ~= nil then
                replaced[#replaced + 1] = entry
                if why == nil and reason ~= "" and reason ~= "same location" then why = reason end
            end
        end
    end
    return true, replaced, why
end

function Master.underwear(sex)
    local pair = Master.DEFAULT_UNDER[sex == "f" and "f" or "m"]
    local result = {}
    if pair.bottom ~= nil then result[#result + 1] = { slot = "UnderwearBottom", itemType = pair.bottom, tint = "" } end
    if pair.top ~= nil then result[#result + 1] = { slot = "UnderwearTop", itemType = pair.top, tint = "" } end
    return result
end

function Master.underwearOf(entries)
    local bottom, top = nil, nil
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local info = Master.infoOf(Master.entryType(entry))
        if info ~= nil and info.isUnderwear then
            if info.name == "underwearbottom" or info.name == "underwear" then bottom = bottom or entry end
            if info.name == "underweartop" or info.name == "underwear" then top = top or entry end
        end
    end
    return bottom, top
end

function Master.covered(entries, female)
    local bottom, top = Master.underwearOf(entries)
    if bottom == nil then return false, "no_underwear_bottom" end
    if female == true and top == nil then return false, "no_underwear_top" end
    local lower = false
    for _, entry in ipairs(entries) do
        local info = Master.infoOf(Master.entryType(entry))
        if info ~= nil and (info.group == "bottom" or info.group == "full") then lower = true end
    end
    if not lower then return false, "no_lower_garment" end
    return true
end

function Master.splitForBeat(entries)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    local top, rest, found = {}, {}, false
    for _, entry in ipairs(entries) do
        local info = Master.infoOf(Master.entryType(entry))
        if info == nil then
            rest[#rest + 1] = entry
        elseif info.group == "full" then
            return nil
        elseif info.group == "top" then
            top[#top + 1] = entry
            found = true
        else
            rest[#rest + 1] = entry
        end
    end
    if not found then return nil end
    return { top = top, rest = rest }
end

function Master.cold(entries)
    local total = 0
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local info = Master.infoOf(Master.entryType(entry))
        if info ~= nil and info.group ~= "back" and info.group ~= "accessory" then
            local weight = 1
            if info.group == "top" or info.group == "full" then weight = 2 elseif info.group == "bottom" then weight = 1.5 end
            total = total + math.min(1.5, info.warmth) * weight
        end
    end
    return math.max(0, math.min(10, math.floor(total / 5.5 * 10 + 0.5)))
end

function Master.rng(seed)
    local spread = math.abs(tonumber(seed) or 0) * 0.6180339887498949
    spread = spread - math.floor(spread)
    local state = math.floor(spread * 2147483646) + 1
    for _ = 1, 2 do state = (state * 48271) % 2147483647 end
    return function(count)
        state = (state * 48271) % 2147483647
        count = math.floor(tonumber(count) or 1)
        if count <= 1 then return 1 end
        return math.floor(state / 2147483647 * count) + 1
    end
end

function Master.roleKey(role)
    local lowered = string.lower(tostring(role or ""))
    for _, name in ipairs(Master.ROLES) do
        if string.find(lowered, name, 1, true) ~= nil then return name end
    end
    if string.find(lowered, "doctor", 1, true) or string.find(lowered, "nurse", 1, true) then return "medical" end
    if string.find(lowered, "farm", 1, true) or string.find(lowered, "hunter", 1, true) then return "rural" end
    if string.find(lowered, "army", 1, true) or string.find(lowered, "soldier", 1, true) then return "military" end
    return "civilian"
end

function Master.usable(item, season, sex, avoid)
    if item == nil or avoid[item.id] == true then return false end
    for _, flag in ipairs(Master.SKIP_FLAGS) do
        if item.flags[flag] == true then return false end
    end
    local lowered = string.lower(item.id)
    for _, token in ipairs(Master.ruleList("forbiddenTokens")) do
        if string.find(lowered, token, 1, true) ~= nil then return false end
    end
    if item.mode == "winterOnly" and season ~= "winter" then return false end
    if item.mode == "warmOnly" and season == "winter" then return false end
    if item.mode == "coolOnly" and season == "summer" then return false end
    local info = Master.layerOf(item.id)
    if info == nil or info.isUnderwear then return false end
    if sex == "m" and (info.name == "dress" or info.name == "longdress" or info.name == "skirt" or info.name == "longskirt") then
        return false
    end
    return true
end

function Master.candidates(season, role, category, sex, avoid)
    local list = Master.shortlist(season, role, category)
    local result = {}
    if list == nil then return result end
    for _, fullType in ipairs(list) do
        local item = Master.get(fullType)
        if Master.usable(item, season, sex, avoid) then result[#result + 1] = item end
    end
    return result
end

function Master.tagged(candidates, rule)
    if rule == nil or #rule.words == 0 then return candidates end
    local matched = {}
    for _, item in ipairs(candidates) do
        local text = string.lower(item.id .. " " .. tostring(item.name))
        for _, word in ipairs(rule.words) do
            if string.find(text, word, 1, true) ~= nil then
                matched[#matched + 1] = item
                break
            end
        end
    end
    if #matched == 0 then return candidates end
    return matched
end

function Master.place(entries, item, tint)
    local ok, replaced = Master.accepts(entries, item.id)
    if not ok then return false end
    for _, entry in ipairs(replaced) do
        for position = #entries, 1, -1 do
            if entries[position] == entry then table.remove(entries, position) end
        end
    end
    entries[#entries + 1] = { slot = Master.locationName(item.location) or "Top", itemType = item.id, tint = tint or "" }
    return true
end

function Master.byRank(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.order < b.order
end

function Master.ordered(entries)
    local rows = {}
    for position, entry in ipairs(entries) do
        local info = Master.layerOf(entry.itemType)
        rows[position] = { entry = entry, rank = info ~= nil and info.rank or 9999, order = position }
    end
    table.sort(rows, Master.byRank)
    local result = {}
    for position, row in ipairs(rows) do result[position] = row.entry end
    return result
end

function Master.pickFrom(candidates, roll)
    if #candidates == 0 then return nil end
    return candidates[roll(#candidates)]
end

function Master.pick(season, role, flags)
    flags = type(flags) == "table" and flags or {}
    if not Master.load() then return Master.shim(season, role, flags) end
    local index = Master.seasonIndex(season)
    if index == nil then season, index = "autumn", 3 else season = Master.SEASONS[index] end
    local seed = math.floor(tonumber(flags.seed) or 0)
    local roll = Master.rng(seed)
    local sex = flags.sex == "f" and "f" or "m"
    local key = Master.roleKey(role)
    local avoid = {}
    for _, fullType in ipairs(type(flags.avoid) == "table" and flags.avoid or {}) do avoid[Master.fullType(fullType) or fullType] = true end
    local wanted = {}
    for _, tag in ipairs(type(flags.tags) == "table" and flags.tags or {}) do wanted[tag] = true end
    local entries, tags = {}, {}
    local function add(category, rule, chance)
        if chance ~= nil and roll(100) > chance then return false end
        local pool = Master.candidates(season, key, category, sex, avoid)
        if #pool == 0 and key ~= "civilian" then pool = Master.candidates(season, "civilian", category, sex, avoid) end
        local item = Master.pickFrom(Master.tagged(pool, rule), roll)
        if item == nil then return false end
        return Master.place(entries, item, "")
    end
    local dressed = false
    if sex == "f" and roll(100) <= 30 then dressed = add("dress", nil, nil) end
    if not dressed then
        add("top", nil, nil)
        add("bottom", nil, nil)
    end
    add("shoes", nil, nil)
    local jacketChance = Master.SEASON_JACKET[season] or 40
    if wanted.surplus_jacket then
        if add("jacket", Master.TAGS.surplus_jacket, nil) then tags[#tags + 1] = "surplus_jacket" end
    else
        add("jacket", nil, jacketChance)
    end
    if wanted.cap then
        if add("hat", Master.TAGS.cap, nil) then tags[#tags + 1] = "cap" end
    elseif key == "military" or key == "law" or key == "fire" then
        add("hat", nil, 40)
    end
    local scarf, gloves = Master.SEASON_SCARF[season] or 0, Master.SEASON_GLOVES[season] or 0
    if scarf > 0 then add("scarf", nil, scarf) end
    if gloves > 0 then add("gloves", nil, gloves) end
    local limit = math.floor(tonumber(flags.maxLayers) or 0)
    if limit > 0 then
        while #entries > limit do table.remove(entries) end
    end
    tags[#tags + 1] = key
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.uniformOf) == "function" then
        local uniform = hydrator.uniformOf(entries)
        if uniform ~= nil then tags[#tags + 1] = "uniform:" .. uniform end
    end
    return { entries = Master.ordered(entries), tags = tags, seed = seed }
end

Master.SHIM = {
    top = "Base.Tshirt_DefaultTEXTURE", bottom = "Base.Trousers_Denim", shoes = "Base.Shoes_Black",
    dressTop = "Base.Dress_Normal",
}

function Master.shim(season, role, flags)
    local seed = math.floor(tonumber(flags.seed) or 0)
    local sex = flags.sex == "f" and "f" or "m"
    local entries = {
        { slot = "Tshirt", itemType = Master.SHIM.top, tint = "" },
        { slot = "Pants", itemType = Master.SHIM.bottom, tint = "" },
        { slot = "Shoes", itemType = Master.SHIM.shoes, tint = "" },
    }
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.dressForSeason) == "function" then
        entries = hydrator.dressForSeason(entries, season, tostring(seed)) or entries
    end
    local tags = { Master.roleKey(role), "shim" }
    if hydrator ~= nil and type(hydrator.uniformOf) == "function" then
        local uniform = hydrator.uniformOf(entries)
        if uniform ~= nil then tags[#tags + 1] = "uniform:" .. uniform end
    end
    return { entries = entries, tags = tags, seed = seed, sex = sex }
end

return Master
