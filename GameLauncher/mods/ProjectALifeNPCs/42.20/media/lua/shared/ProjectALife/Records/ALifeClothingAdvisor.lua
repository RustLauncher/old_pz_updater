require "ProjectALife/Records/ALifeClothingMaster"

ProjectALife = ProjectALife or {}

local Advisor = {
    SLOT_CATEGORY = {
        Hat = "hat", Top = "top", Tshirt = "top", Sweater = "top", Jacket = "jacket", Vest = "vest",
        Pants = "bottom", Shoes = "shoes", Scarf = "scarf", Hands = "gloves", FullSuit = "fullbody",
        Socks = "socks", Mask = "mask", Eyes = "glasses", Neck = "neckwear", Back = "bag", Belt = "belt",
    },
    CATEGORY_SLOT = {
        hat = "Hat", jacket = "Jacket", top = "Top", bottom = "Pants", shoes = "Shoes", scarf = "Scarf",
        gloves = "Hands", vest = "Vest",
    },
    HOOD = { ["base:jackethat"] = true, ["base:jackethat_bulky"] = true, ["base:sweaterhat"] = true },
    OTHER_HEAD = { ["base:eartop"] = true, ["base:fullsuithead"] = true, ["base:fullsuitheadscba"] = true },
    UNIFORMS = { "military", "law", "fire", "medical", "prison" },
    SEASON_TITLE = { "SPRING", "SUMMER", "AUTUMN", "WINTER" },
    SEASON_NAME = { "Spring", "Summer", "Autumn", "Winter" },
    SCORE_WORD = { "never", "mixed outfit only", "good", "ideal" },
    HIDE_WORD = { novelty = "NOVELTY", role = "OTHER ROLE", era = "OUT OF ERA", offseason = "OFF-SEASON" },
    WARMTH_WORD = { none = "cool", light = "light", medium = "warm", heavy = "heavy" },
    GROUP_TITLE = {
        ideal = "IDEAL FOR %s", good = "GOOD FOR %s", mixed = "MIXED OUTFIT ONLY",
        allyear = "ALL YEAR", warm = "WARM WEATHER", cold = "COLD WEATHER", mild = "SPRING AND AUTUMN",
        unrated = "NOT RATED (MODDED OR NEW ITEMS)", hoods = "HOODS AND PONCHOS (THEY ALSO TAKE THE JACKET SLOT)",
        other = "NOT HATS (OTHER BODY LOCATIONS)", offseason = "NOT FOR %s", role = "NOT FOR THIS ROLE",
        era = "OUT OF ERA OR CRAFTED", novelty = "NOVELTY AND COSTUME", neutral = "NO WEATHER EFFECT",
    },
    GROUP_ORDER = { "ideal", "good", "allyear", "warm", "cold", "mild", "mixed", "neutral", "unrated", "hoods", "other",
        "offseason", "role", "era", "novelty" },
    MODE_GROUP = { any = "allyear", warmOnly = "warm", coolOnly = "cold", winterOnly = "cold", transitional = "mild",
        marginal = "mixed" },
    ISSUE_WORDS = {
        military = "military army soldier", law = "law police cop sheriff trooper", fire = "fire fireman firefighter",
        medical = "medical medic doctor nurse ems", prison = "prison inmate guard", work = "work workwear",
        sports = "sports sporty", formal = "formal suit", civilian = "civilian",
    },
    SEASON_WORDS = { "spring", "summer", "autumn fall", "winter cold" },
    stats = { rated = 0, built = 0 },
    cache = { count = 0, byKey = {} },
}
ProjectALife.ClothingAdvisor = Advisor

function Advisor.master()
    return ProjectALife.ClothingMaster
end

function Advisor.suffix(location)
    local text = tostring(location or "")
    if string.sub(text, 1, 5) == "base:" then return string.sub(text, 6) end
    return text
end

function Advisor.listToSet(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

function Advisor.explicitKinds(npcClass)
    if npcClass == "police" then return { law = true }, "law", nil end
    if npcClass == "military" then return { military = true }, "military", nil end
    if npcClass == "rescue" then return { fire = true, medical = true }, "fire", nil end
    if npcClass == "criminal" then return nil, "civilian", "crime" end
    if npcClass == "worker" then return nil, "civilian", "worker" end
    if npcClass == "civilian" then return nil, "civilian", nil end
    return nil, nil, nil
end

function Advisor.role(profile, faction)
    local Master = Advisor.master()
    local Generator = ProjectALife.SeasonalOutfitGenerator
    local general = type(profile) == "table" and type(profile.general) == "table" and profile.general or {}
    local kinds, kind, bloc = Advisor.explicitKinds(general.npcClass)
    local factionBloc
    if Generator ~= nil and type(Generator.blocOf) == "function" then
        local ok, value = pcall(Generator.blocOf, faction)
        if ok and type(value) == "string" then factionBloc = value end
    end
    if kind == nil then
        kind = "civilian"
        if Generator ~= nil and type(Generator.classOf) == "function" then
            local ok, value = pcall(Generator.classOf, profile, faction)
            if ok and type(value) == "string" then kind = value end
        end
    end
    bloc = bloc or factionBloc
    if kinds == nil then kinds = { [kind] = true } end
    local serious = Advisor.listToSet(Master.ruleList("seriousKinds"))
    local seriousBlocs = Advisor.listToSet(Master.ruleList("seriousBlocs"))
    local civilianBlocs = Advisor.listToSet(Master.ruleList("civilianBlocs"))
    local exempt = Advisor.listToSet(Master.ruleList("eraExemptBlocs"))
    local isSerious = false
    for name in pairs(kinds) do
        if serious[name] then isSerious = true end
    end
    if bloc ~= nil and seriousBlocs[bloc] then isSerious = true end
    local civilian = bloc ~= nil and civilianBlocs[bloc] == true
    if bloc == nil and kind == "civilian" then civilian = true end
    local key = kind
    if bloc == "worker" then key = "work" end
    return { kind = kind, kinds = kinds, bloc = bloc, serious = isSerious, civilianBloc = civilian,
        eraExempt = bloc ~= nil and exempt[bloc] == true, key = key,
        uniformed = kinds.law == true or kinds.military == true or kinds.fire == true or kinds.medical == true }
end

function Advisor.setSeason(profile, letter, fixed)
    local Master = Advisor.master()
    local tag = type(profile) == "table" and type(profile.outfitSeason) == "table" and profile.outfitSeason[letter] or nil
    if type(tag) == "string" and tag ~= "" then
        local lower = string.lower(tag)
        for index, name in ipairs(Master.SEASONS) do
            if name == lower then return index end
        end
        if lower == "fall" then return 3 end
        return nil
    end
    if fixed == true then return Master.LETTERS[letter] end
    return nil
end

function Advisor.context(slot, season, role, showAll)
    local Master = Advisor.master()
    return { slot = slot, season = season, role = role, showAll = showAll == true,
        forbiddenLocations = Advisor.listToSet(Master.ruleList("forbiddenLocations")),
        forbiddenTokens = Master.ruleList("forbiddenTokens"),
        neutral = Advisor.listToSet(Master.ruleList("neutralCategories")),
        seasonTitle = season ~= nil and Advisor.SEASON_TITLE[season] or nil }
end

function Advisor.contextKey(ctx)
    local role = ctx.role
    local kinds = {}
    if role ~= nil then
        for name in pairs(role.kinds) do kinds[#kinds + 1] = name end
        table.sort(kinds)
    end
    return table.concat({ tostring(ctx.slot), tostring(ctx.season), table.concat(kinds, "+"),
        role ~= nil and role.serious and "s" or "-", role ~= nil and role.civilianBloc and "c" or "-",
        role ~= nil and role.eraExempt and "e" or "-", role ~= nil and role.uniformed and "u" or "-" }, "|")
end

function Advisor.ratingsFor(ctx)
    local cache = Advisor.cache
    local state = Advisor.master().state
    if cache.state ~= state then
        cache.state, cache.byKey, cache.count = state, {}, 0
    end
    local key = Advisor.contextKey(ctx)
    local ratings = cache.byKey[key]
    if ratings == nil then
        if cache.count >= 16 then cache.byKey, cache.count = {}, 0 end
        ratings = {}
        cache.byKey[key] = ratings
        cache.count = cache.count + 1
    end
    return ratings
end

function Advisor.isNovelty(rec)
    return rec.flags.novelty == true or rec.flags.costume == true
end

function Advisor.forbiddenForSerious(rec, ctx)
    if ctx.forbiddenLocations[Advisor.suffix(rec.location)] then return true end
    local lower = string.lower(rec.id)
    for _, token in ipairs(ctx.forbiddenTokens) do
        if string.find(lower, token, 1, true) ~= nil then return true end
    end
    return rec.category == "bottom" and rec.subcategory == "short shorts"
end

function Advisor.protectiveOnCivilian(rec)
    local suffix = Advisor.suffix(rec.location)
    if rec.bullet > 0 or suffix == "cuirass" or suffix == "torsoextravestbullet" or rec.flags.heavy == true then
        return true
    end
    return rec.category == "hat" and rec.subcategory == "helmet" and not Advisor.isNovelty(rec)
        and rec.issue.military == true
end

function Advisor.issuedElsewhere(rec, role)
    local issued, matches = false, false
    for _, name in ipairs(Advisor.UNIFORMS) do
        if rec.issue[name] then
            issued = true
            if role.kinds[name] then matches = true end
        end
    end
    return issued and not matches and rec.issue.civilian ~= true
end

function Advisor.roleMismatch(rec, ctx)
    local role = ctx.role
    if role == nil then return false end
    if rec.flags.heavy and not (role.eraExempt or role.bloc == "elite") then return true end
    if role.serious and Advisor.forbiddenForSerious(rec, ctx) then return true end
    if role.civilianBloc and Advisor.protectiveOnCivilian(rec) then return true end
    if role.uniformed and Advisor.issuedElsewhere(rec, role) then return true end
    return false
end

function Advisor.eraProblem(rec, ctx)
    if rec.anachronism == "medium" or rec.anachronism == "high" then return true end
    if rec.flags.improvised and not (ctx.role ~= nil and ctx.role.eraExempt) then return true end
    return false
end

function Advisor.roleMatch(rec, role)
    if role == nil then return false end
    for name in pairs(role.kinds) do
        if rec.issue[name] or rec.roles[name] then return true end
    end
    if role.kind == "civilian" and (rec.roles.civilian or rec.issue.civilian) then return true end
    return false
end

function Advisor.hoodSuffix(rec)
    if rec == nil then return nil end
    if Advisor.HOOD[rec.location] then return "hood up" end
    if rec.variant ~= nil then
        local other = Advisor.master().get(rec.variant)
        if other ~= nil and Advisor.HOOD[other.location] then return "hood down" end
    end
    return nil
end

function Advisor.fullName(rec, fallback)
    if rec == nil then return tostring(fallback or "") end
    local suffix = Advisor.hoodSuffix(rec)
    if suffix ~= nil then return rec.name .. " (" .. suffix .. ")" end
    return rec.name
end

function Advisor.nameOf(fullType)
    local rec = Advisor.master().get(fullType)
    if rec ~= nil then return Advisor.fullName(rec) end
    return tostring(string.match(tostring(fullType or ""), "^[^.]+%.(.+)$") or fullType or "")
end

function Advisor.scoreGroup(rec, ctx)
    if ctx.neutral[rec.category] and rec.seasons[1] == 2 and rec.seasons[2] == 2 and rec.seasons[3] == 2
            and rec.seasons[4] == 2 then
        return "neutral"
    end
    if ctx.season ~= nil then
        local score = rec.seasons[ctx.season]
        if score >= 3 then return "ideal" end
        if score == 2 then return "good" end
        return "mixed"
    end
    return Advisor.MODE_GROUP[rec.mode] or "allyear"
end

function Advisor.rate(entry, ctx)
    local rating = { roleMatch = false, hero = false, sortId = tostring(entry.id) }
    Advisor.stats.rated = Advisor.stats.rated + 1
    if entry.id == "none" or entry.id == "remove" then
        rating.fixed = true
        rating.visible = true
        return rating
    end
    local rec = Advisor.master().get(entry.id)
    rating.rec = rec
    if rec == nil then
        rating.group, rating.fullGroup, rating.visible = "unrated", "unrated", true
        return rating
    end
    if rec.flags.debug or rec.flags.animal then
        rating.excluded = true
        return rating
    end
    rating.roleMatch = Advisor.roleMatch(rec, ctx.role)
    rating.hero = rec.flags.hero == true
    local hide
    if Advisor.isNovelty(rec) then
        hide = "novelty"
    elseif Advisor.roleMismatch(rec, ctx) then
        hide = "role"
    elseif Advisor.eraProblem(rec, ctx) then
        hide = "era"
    elseif ctx.season ~= nil and rec.seasons[ctx.season] == 0 then
        hide = "offseason"
    end
    local natural = Advisor.scoreGroup(rec, ctx)
    if ctx.slot == "Hat" then
        if Advisor.HOOD[rec.location] then natural = "hoods"
        elseif Advisor.OTHER_HEAD[rec.location] then natural = "other" end
    end
    rating.hideReason = hide
    rating.fullGroup = hide or natural
    rating.group = hide == nil and natural or nil
    rating.visible = hide == nil
    return rating
end

function Advisor.warmthWord(rec)
    return Advisor.WARMTH_WORD[rec.warmth] or "cool"
end

function Advisor.flagWords(rec)
    local words = {}
    if rec.flags.novelty then words[#words + 1] = "NOVELTY" end
    if rec.flags.costume then words[#words + 1] = "COSTUME" end
    if rec.anachronism ~= nil then words[#words + 1] = "OUT OF ERA" end
    if rec.flags.improvised then words[#words + 1] = "CRAFTED" end
    if rec.flags.heavy then words[#words + 1] = "HEAVY ARMOR"
    elseif rec.flags.protective then words[#words + 1] = "PROTECTIVE" end
    if Advisor.HOOD[rec.location] then words[#words + 1] = "HOOD UP" end
    return words
end

function Advisor.tags(rec)
    return { dots = rec.seasons, warmth = Advisor.warmthWord(rec), wind = (rec.wind or 0) >= 0.6,
        rain = rec.rain ~= "none", flags = Advisor.flagWords(rec) }
end

function Advisor.searchText(rec)
    if rec.search ~= nil then return rec.search end
    local Master = Advisor.master()
    local parts = { string.lower(rec.name), string.lower(rec.id), string.lower(tostring(rec.category)),
        string.lower(tostring(rec.subcategory)), rec.roleText }
    for index = 1, 4 do
        if rec.seasons[index] >= 2 then parts[#parts + 1] = Advisor.SEASON_WORDS[index] end
    end
    if rec.warmth == "medium" or rec.warmth == "heavy" then parts[#parts + 1] = "warm" end
    if rec.warmth == "heavy" then parts[#parts + 1] = "heavy" end
    if rec.warmth == "light" then parts[#parts + 1] = "light" end
    if rec.warmth == "none" then parts[#parts + 1] = "thin cool" end
    if (rec.wind or 0) >= 0.6 then parts[#parts + 1] = "wind windproof" end
    if rec.rain ~= "none" then parts[#parts + 1] = "rain waterproof wet" end
    for name in pairs(rec.issue) do parts[#parts + 1] = Advisor.ISSUE_WORDS[name] or name end
    for _, tag in ipairs(Master.stylesOf(rec)) do parts[#parts + 1] = tag end
    if rec.flags.novelty then parts[#parts + 1] = "novelty" end
    if rec.flags.costume then parts[#parts + 1] = "costume" end
    if rec.flags.improvised then parts[#parts + 1] = "crafted improvised" end
    if rec.flags.protective then parts[#parts + 1] = "protective armor" end
    if rec.flags.heavy then parts[#parts + 1] = "heavy armor" end
    if rec.anachronism ~= nil then parts[#parts + 1] = "era anachronism" end
    if Advisor.HOOD[rec.location] then parts[#parts + 1] = "hood hooded" end
    rec.search = string.lower(table.concat(parts, " "))
    return rec.search
end

function Advisor.tooltip(entry, rating, ctx, found)
    local Master = Advisor.master()
    local rec = rating ~= nil and rating.rec or nil
    local title = tostring(entry.label or entry.id)
    local lines = { title .. "  (" .. tostring(entry.id) .. ")" }
    if rec == nil then
        lines[#lines + 1] = "Not in the clothing guide (modded or new item): listed without a season or role rating."
    else
        local water = rec.water and tostring(rec.water) or "none"
        local wind = rec.wind and tostring(rec.wind) or "none"
        lines[#lines + 1] = "Warmth: " .. Advisor.warmthWord(rec) .. " (insulation " .. tostring(rec.insulation)
            .. (rec.assumed and ", assumed" or "") .. "), wind " .. wind .. ", water " .. water
        for index = 1, 4 do
            local score = rec.seasons[index]
            local mark = ctx ~= nil and ctx.season == index and "  (this set)" or ""
            lines[#lines + 1] = Advisor.SEASON_NAME[index] .. " " .. tostring(score) .. " (" .. Advisor.SCORE_WORD[score + 1]
                .. "): " .. tostring(Master.whyOf(rec, index) or "") .. mark
        end
        lines[#lines + 1] = "Role fit: " .. rec.roleText
        local issued = {}
        for _, name in ipairs(Advisor.UNIFORMS) do
            if rec.issue[name] then issued[#issued + 1] = name end
        end
        if #issued > 0 then lines[#lines + 1] = "Issued to: " .. table.concat(issued, ", ") end
        local styles = Master.stylesOf(rec)
        if #styles > 0 then lines[#lines + 1] = "Style: " .. table.concat(styles, ", ") end
        local words = Advisor.flagWords(rec)
        if #words > 0 then lines[#lines + 1] = "Marked: " .. table.concat(words, ", ") end
        for _, note in ipairs(Master.avoidOf(rec)) do lines[#lines + 1] = "Note: " .. note end
        if rating.hideReason ~= nil then
            lines[#lines + 1] = "Hidden by default: " .. (Advisor.HIDE_WORD[rating.hideReason] or rating.hideReason)
        end
    end
    if found ~= nil and ProjectALife.ClothingHealth ~= nil then
        lines[#lines + 1] = "COLLIDES: " .. ProjectALife.ClothingHealth.collisionMessage(title, found)
    end
    return table.concat(lines, "\n")
end

function Advisor.tokens(query)
    local list = {}
    for word in string.gmatch(string.lower(tostring(query or "")), "%S+") do list[#list + 1] = word end
    return list
end

function Advisor.matches(entry, rating, query, tokens)
    if query == nil or query == "" then return true end
    local label = rating ~= nil and rating.sortKey or string.lower(tostring(entry.label))
    local id = rating ~= nil and rating.idLower or string.lower(tostring(entry.id))
    if string.find(label, query, 1, true) ~= nil or string.find(id, query, 1, true) ~= nil then return true end
    local rec = rating ~= nil and rating.rec or nil
    if rec == nil or tokens == nil or #tokens == 0 then return false end
    local text = Advisor.searchText(rec)
    for _, word in ipairs(tokens) do
        if string.find(text, word, 1, true) == nil and string.find(label, word, 1, true) == nil then return false end
    end
    return true
end

function Advisor.before(a, b)
    local x, y = a.rating, b.rating
    if x.roleMatch ~= y.roleMatch then return x.roleMatch == true end
    if x.hero ~= y.hero then return x.hero == true end
    if x.sortKey ~= y.sortKey then return x.sortKey < y.sortKey end
    return x.sortId < y.sortId
end

function Advisor.title(group, ctx)
    local text = Advisor.GROUP_TITLE[group] or string.upper(tostring(group))
    if string.find(text, "%s", 1, true) == nil then return text end
    local season = ctx.seasonTitle or "THIS SEASON"
    local head, tail = string.match(text, "^(.-)%%s(.*)$")
    return head .. season .. tail
end

function Advisor.arrange(entries, ctx, ratings)
    Advisor.stats.built = Advisor.stats.built + 1
    ratings = ratings or {}
    local fixed, groups, hidden = {}, {}, {}
    for _, entry in ipairs(entries) do
        local rating = ratings[entry.id]
        if rating == nil then
            rating = Advisor.rate(entry, ctx)
            ratings[entry.id] = rating
        end
        if not rating.excluded then
            if rating.sortKey == nil then
                rating.sortKey = string.lower(tostring(entry.label))
                rating.idLower = string.lower(tostring(entry.id))
            end
            local pair = { entry = entry, rating = rating }
            if rating.fixed then
                fixed[#fixed + 1] = pair
            else
                local group = ctx.showAll and rating.fullGroup or rating.group
                if group == nil then
                    hidden[#hidden + 1] = pair
                else
                    local bucket = groups[group]
                    if bucket == nil then
                        bucket = {}
                        groups[group] = bucket
                    end
                    bucket[#bucket + 1] = pair
                end
            end
        end
    end
    for _, bucket in pairs(groups) do table.sort(bucket, Advisor.before) end
    return { fixed = fixed, groups = groups, hidden = hidden, ctx = ctx, ratings = ratings }
end

function Advisor.narrow(arranged, query)
    local ctx = arranged.ctx
    local tokens = Advisor.tokens(query)
    local sections, shown, hiddenMatches = {}, 0, 0
    local fixedItems = {}
    for _, pair in ipairs(arranged.fixed) do
        if Advisor.matches(pair.entry, pair.rating, query, tokens) then fixedItems[#fixedItems + 1] = pair.entry end
    end
    if #fixedItems > 0 then sections[1] = { id = "fixed", items = fixedItems } end
    for _, group in ipairs(Advisor.GROUP_ORDER) do
        local bucket = arranged.groups[group]
        if bucket ~= nil then
            local items = {}
            for _, pair in ipairs(bucket) do
                if Advisor.matches(pair.entry, pair.rating, query, tokens) then items[#items + 1] = pair.entry end
            end
            if #items > 0 then
                sections[#sections + 1] = { id = group, title = Advisor.title(group, ctx), items = items }
                shown = shown + #items
            end
        end
    end
    for _, pair in ipairs(arranged.hidden) do
        if Advisor.matches(pair.entry, pair.rating, query, tokens) then hiddenMatches = hiddenMatches + 1 end
    end
    return { sections = sections, shown = shown, hidden = hiddenMatches, ratings = arranged.ratings }
end

function Advisor.build(entries, ctx, query, ratings)
    return Advisor.narrow(Advisor.arrange(entries, ctx, ratings), query)
end

return Advisor
