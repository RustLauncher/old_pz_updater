require "ProjectALife/Records/ALifeClothingMaster"
require "ProjectALife/Records/ALifeClothingAdvisor"

ProjectALife = ProjectALife or {}

local Health = {
    TORSO = { tshirt = true, tanktop = true, shortsleeveshirt = true, shirt = true, sweater = true, sweaterhat = true,
        jersey = true, jacket = true, jacket_down = true, jacket_bulky = true, jackethat = true, jackethat_bulky = true,
        jacketsuit = true, bathrobe = true, fullrobe = true, torsoextravest = true, torsoextravestbullet = true,
        boilersuit = true, fullsuit = true, vesttexture = true, torso1 = true, dress = true, longdress = true,
        torso1legs1 = true },
    LEGS = { pants = true, pants_skinny = true, pantsextra = true, shortpants = true, shortsshort = true, skirt = true,
        longskirt = true, dress = true, longdress = true, legs1 = true, torso1legs1 = true, boilersuit = true,
        fullsuit = true },
    BREATHABLE = { tanktop = true, shortsshort = true, shortsleeveshirt = true },
    WEIGHT = {
        COLLISION = 4, SERIOUS_FORBIDDEN = 5, SERIOUS_NOVELTY = 4, WINTER_NO_OUTER = 4, WINTER_LOW_TORSO = 3,
        WINTER_COLD_FEET = 3, WINTER_BREATHABLE = 3, WINTER_COLD_HEAD = 2, WINTER_LIGHT_LEGS = 2,
        SUMMER_HEAVY_TORSO = 3, SUMMER_HEAVY_OUTER = 3, SUMMER_WARM_HAT = 2, SUMMER_SCARF = 2,
        SPRING_COLD = 2, SPRING_HOT = 2, AUTUMN_THIN = 2, AUTUMN_HOT = 2, SEASON_ITEM_0 = 3,
        PROTECTIVE_ON_CIVILIAN = 2, IMPROVISED = 1, ANACHRONISM = 1, NO_TORSO = 3, NO_LEGS = 3, NO_SHOES = 2,
    },
    SEASON_WORD = { "Spring", "Summer", "Autumn", "Winter" },
    stats = { evaluated = 0, suggested = 0 },
}
ProjectALife.ClothingHealth = Health

function Health.choices(pool)
    local list, seen, none = {}, {}, false
    for item in string.gmatch(tostring(pool or "") .. "|", "(.-)|") do
        item = string.match(item, "^%s*(.-)%s*$")
        if item == "none" then
            none = true
        elseif item ~= "" and item ~= "remove" then
            local full = ProjectALife.ClothingMaster.fullType(item)
            if not seen[full] then
                seen[full] = true
                list[#list + 1] = full
            end
        end
    end
    return list, none
end

function Health.poolWith(pool, oldId, newId)
    local list, none = Health.choices(pool)
    local out, seen = {}, {}
    local replaced = false
    for _, id in ipairs(list) do
        local use = id
        if oldId ~= nil and id == oldId then
            use = newId
            replaced = true
        end
        if use ~= nil and not seen[use] then
            seen[use] = true
            out[#out + 1] = use
        end
    end
    if newId ~= nil and not replaced and not seen[newId] then out[#out + 1] = newId end
    if #out == 0 then return "none" end
    if none and #out < 4 then out[#out + 1] = "none" end
    return table.concat(out, "|")
end

function Health.signature(pools, order)
    if type(pools) ~= "table" then return "" end
    local parts, count = {}, 0
    for _, slot in ipairs(order) do
        local value = pools[slot]
        if value ~= nil and value ~= "" and value ~= "none" then
            count = count + 1
            parts[count] = slot .. "=" .. tostring(value)
        end
    end
    return table.concat(parts, ";")
end

function Health.locations(id, rec, services)
    local Master = ProjectALife.ClothingMaster
    if services ~= nil and type(services.locationOf) == "function" then
        local raw = services.locationOf(id)
        if raw ~= nil then return Master.normalizeLocation(raw), raw, true end
    end
    if rec ~= nil then return rec.location, rec.location, false end
    return nil, nil, false
end

function Health.collides(rawA, rawB, normA, normB, services, engineA, engineB)
    if normA == nil or normB == nil then return false end
    if engineA and engineB and services ~= nil and type(services.collide) == "function" then
        return services.collide(rawA, rawB) == true
    end
    if normA == normB then return true end
    return ProjectALife.ClothingMaster.collision(normA, normB) ~= nil
end

function Health.alternative(candidate, other, services)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    local options = { { rec = candidate, keep = other, side = "candidate" }, { rec = other, keep = candidate, side = "other" } }
    for _, option in ipairs(options) do
        local rec, keep = option.rec, option.keep
        if rec ~= nil and keep ~= nil and rec.variants ~= nil then
            for _, variantId in ipairs(rec.variants) do
                local variant = Master.get(variantId)
                if variant ~= nil then
                    local normV, rawV, engineV = Health.locations(variant.id, variant, services)
                    local normK, rawK, engineK = Health.locations(keep.id, keep, services)
                    if normV ~= nil and normK ~= nil
                            and not Health.collides(rawV, rawK, normV, normK, services, engineV, engineK) then
                        return { id = variant.id, name = Advisor.fullName(variant), side = option.side, from = rec.id }
                    end
                end
            end
        end
    end
    return nil
end

function Health.collisionFor(entry, outfit, slot, services)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    if type(outfit) ~= "table" then return nil end
    local rec = Master.get(entry.id)
    local normA, rawA, engineA = Health.locations(entry.id, rec, services)
    if entry.bodyLocation ~= nil then
        normA, rawA, engineA = Master.normalizeLocation(entry.bodyLocation), entry.bodyLocation, true
    end
    if normA == nil then return nil end
    local slots = {}
    for otherSlot in pairs(outfit) do slots[#slots + 1] = otherSlot end
    table.sort(slots)
    local found = {}
    for _, otherSlot in ipairs(slots) do
        if otherSlot ~= slot then
            for _, id in ipairs((Health.choices(outfit[otherSlot]))) do
                local other = Master.get(id)
                local normB, rawB, engineB = Health.locations(id, other, services)
                if normB ~= nil and Health.collides(rawA, rawB, normA, normB, services, engineA, engineB) then
                    found[#found + 1] = { slot = otherSlot, id = id, name = Advisor.nameOf(id),
                        reason = Master.collision(normA, normB), same = normA == normB,
                        alternative = Health.alternative(rec, other, services), location = normB }
                end
            end
        end
    end
    if #found == 0 then return nil end
    return found
end

function Health.collisionMessage(entryName, found)
    local first = found[1]
    local text = entryName .. " collides with " .. first.name .. " (" .. first.slot .. " slot)"
    if first.same then
        text = text .. ": both use the same body location."
    elseif first.reason ~= nil and first.reason ~= "" then
        text = text .. ": " .. first.reason .. "."
    else
        text = text .. "."
    end
    if #found > 1 then
        local others = {}
        for index = 2, #found do others[#others + 1] = found[index].name end
        text = text .. " It also collides with " .. table.concat(others, ", ") .. "."
    end
    if first.alternative ~= nil then
        text = text .. " Compatible alternative: " .. first.alternative.name .. "."
    end
    return text
end

function Health.rules()
    local Master = ProjectALife.ClothingMaster
    local function number(key, default)
        local value = Master.rule(key)
        if type(value) == "number" then return value end
        return default
    end
    return {
        winterTorso = number("winter.torsoMin", 0.9), winterLegs = number("winter.legMin", 0.4),
        winterFoot = number("winter.footMin", 0.4), winterOuter = number("winter.outerMin", 0.5),
        winterHead = number("winter.headMin", 0.3), summerTorso = number("summer.torsoMax", 0.6),
        summerOuter = number("summer.outerMax", 0.5), summerHat = number("summer.hatMax", 0.5),
        springMin = number("spring.torsoMin", 0.25), springMax = number("spring.torsoMax", 1.4),
        autumnMin = number("autumn.torsoMin", 0.6), autumnMax = number("autumn.torsoMax", 1.8),
        capTorso = number("cap.torso", 2), capLegs = number("cap.legs", 1.5),
    }
end

function Health.outerOk(rec, minimum)
    if rec.category == "jacket" then return rec.insulation >= minimum end
    if rec.category == "fullbody" then return rec.insulation >= minimum and rec.location ~= "base:jackethat" end
    return false
end

function Health.headOk(rec, minimum)
    if rec.category == "scarf" then return true end
    local suffix = ProjectALife.ClothingAdvisor.suffix(rec.location)
    if suffix == "jackethat" or suffix == "jackethat_bulky" or suffix == "sweaterhat" then return true end
    return rec.category == "hat" and rec.insulation >= minimum and rec.subcategory ~= "helmet"
end

function Health.names(list, limit)
    local out = {}
    for index, name in ipairs(list) do
        if index <= (limit or 3) then out[#out + 1] = name end
    end
    local text = table.concat(out, ", ")
    if #list > #out then text = text .. " +" .. tostring(#list - #out) end
    return text
end

function Health.add(issues, code, text, slot, id, extra)
    local issue = { code = code, weight = Health.WEIGHT[code] or 1, text = text, slot = slot, id = id }
    if extra ~= nil then
        for key, value in pairs(extra) do issue[key] = value end
    end
    issues[#issues + 1] = issue
    return issue
end

function Health.slotFacts(slot, ids, none, rules)
    local Master = ProjectALife.ClothingMaster
    local facts = { slot = slot, ids = ids, recs = {}, none = none, torsoMin = 0, torsoMax = 0, legsMin = 0, legsMax = 0,
        torsoAll = not none, legsAll = not none, shoesAll = not none, outerAll = not none, headAll = not none,
        unknown = false }
    local first = true
    local footMin
    for index, id in ipairs(ids) do
        local rec = Master.get(id)
        facts.recs[index] = rec or false
        if rec == nil then
            facts.unknown = true
            facts.torsoAll, facts.legsAll, facts.shoesAll, facts.outerAll, facts.headAll = false, false, false, false, false
        else
            local suffix = ProjectALife.ClothingAdvisor.suffix(rec.location)
            local torso = Health.TORSO[suffix] and math.min(rec.insulation, rules.capTorso) or 0
            local legs = Health.LEGS[suffix] and math.min(rec.insulation, rules.capLegs) or 0
            if first then
                facts.torsoMin, facts.torsoMax, facts.legsMin, facts.legsMax = torso, torso, legs, legs
                first = false
            else
                facts.torsoMin, facts.torsoMax = math.min(facts.torsoMin, torso), math.max(facts.torsoMax, torso)
                facts.legsMin, facts.legsMax = math.min(facts.legsMin, legs), math.max(facts.legsMax, legs)
            end
            if not Health.TORSO[suffix] then facts.torsoAll = false end
            if not Health.LEGS[suffix] then facts.legsAll = false end
            if suffix ~= "shoes" then
                facts.shoesAll = false
            else
                footMin = footMin == nil and rec.insulation or math.min(footMin, rec.insulation)
            end
            if not Health.outerOk(rec, rules.winterOuter) then facts.outerAll = false end
            if not Health.headOk(rec, rules.winterHead) then facts.headAll = false end
        end
    end
    if none then facts.torsoMin, facts.legsMin = 0, 0 end
    facts.footMin = footMin
    return facts
end

function Health.itemRules(issues, slots, season, role)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    local ctx = Advisor.context(nil, season, role, false)
    local buckets, order = {}, {}
    local function note(code, slot, rec, detail)
        local bucket = buckets[code]
        if bucket == nil then
            bucket = { names = {}, slot = slot, id = rec.id, ids = {}, details = {} }
            buckets[code] = bucket
            order[#order + 1] = code
        end
        bucket.names[#bucket.names + 1] = Advisor.fullName(rec)
        bucket.ids[#bucket.ids + 1] = { slot = slot, id = rec.id }
        if detail ~= nil then bucket.details[#bucket.details + 1] = detail end
    end
    for _, facts in ipairs(slots) do
        for index = 1, #facts.ids do
            local rec = facts.recs[index]
            if rec then
                if season ~= nil and rec.seasons[season] == 0 then note("SEASON_ITEM_0", facts.slot, rec) end
                if role ~= nil and role.serious then
                    if Advisor.forbiddenForSerious(rec, ctx) then
                        note("SERIOUS_FORBIDDEN", facts.slot, rec)
                    elseif Advisor.isNovelty(rec) then
                        note("SERIOUS_NOVELTY", facts.slot, rec)
                    end
                end
                if role ~= nil and role.civilianBloc and Advisor.protectiveOnCivilian(rec) then
                    note("PROTECTIVE_ON_CIVILIAN", facts.slot, rec)
                end
                if rec.anachronism == "medium" or rec.anachronism == "high" then
                    note("ANACHRONISM", facts.slot, rec, Master.avoidOf(rec)[1])
                end
                if rec.flags.improvised and not (role ~= nil and role.eraExempt) then
                    note("IMPROVISED", facts.slot, rec)
                end
            end
        end
    end
    local seasonWord = season ~= nil and string.lower(Health.SEASON_WORD[season]) or "this season"
    for _, code in ipairs(order) do
        local bucket = buckets[code]
        local list = Health.names(bucket.names)
        local text
        if code == "SEASON_ITEM_0" then
            text = list .. " is not suited to " .. seasonWord .. " (rated 0)"
        elseif code == "SERIOUS_FORBIDDEN" then
            text = list .. " breaks the uniform rule for this role (no shorts, tank tops, swimwear or sandals)"
        elseif code == "SERIOUS_NOVELTY" then
            text = list .. " is a novelty or costume item on a serious role"
        elseif code == "PROTECTIVE_ON_CIVILIAN" then
            text = list .. " is protective gear that civilians do not wear"
        elseif code == "ANACHRONISM" then
            text = list .. " is out of era for July 1993"
            if bucket.details[1] ~= nil then text = text .. " (" .. bucket.details[1] .. ")" end
        else
            text = list .. " is a crafted post-outbreak item"
        end
        Health.add(issues, code, text, bucket.slot, bucket.id, { items = bucket.ids })
    end
end

function Health.collisionRules(issues, slots, services)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    local pairsSeen = 0
    for i = 1, #slots - 1 do
        for j = i + 1, #slots do
            local a, b = slots[i], slots[j]
            for ia, idA in ipairs(a.ids) do
                local recA = a.recs[ia] or nil
                local normA, rawA, engineA = Health.locations(idA, recA, services)
                for ib, idB in ipairs(b.ids) do
                    local recB = b.recs[ib] or nil
                    local normB, rawB, engineB = Health.locations(idB, recB, services)
                    pairsSeen = pairsSeen + 1
                    if normA ~= nil and normB ~= nil
                            and Health.collides(rawA, rawB, normA, normB, services, engineA, engineB) then
                        local nameA, nameB = Advisor.nameOf(idA), Advisor.nameOf(idB)
                        local reason = Master.collision(normA, normB)
                        local text = nameA .. " (" .. a.slot .. ") collides with " .. nameB .. " (" .. b.slot .. ")"
                        if normA == normB then
                            text = text .. ": both use the same body location"
                        elseif reason ~= nil and reason ~= "" then
                            text = text .. ": " .. reason
                        end
                        Health.add(issues, "COLLISION", text, a.slot, idA, { items = { { slot = a.slot, id = idA },
                            { slot = b.slot, id = idB } }, pairSlot = b.slot, pairId = idB })
                    end
                end
            end
        end
    end
    return pairsSeen
end

function Health.climateRules(issues, slots, season, rules, unknown)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    local torsoMin, torsoMax, legsMin, legsMax = 0, 0, 0, 0
    local hasTorso, hasLegs, hasShoes, outerOk, headOk = false, false, false, false, false
    local footMin
    local shoesSlot
    local summerOuter, summerHat, scarf, breathable = {}, {}, {}, {}
    for _, facts in ipairs(slots) do
        torsoMin, torsoMax = torsoMin + facts.torsoMin, torsoMax + facts.torsoMax
        legsMin, legsMax = legsMin + facts.legsMin, legsMax + facts.legsMax
        if facts.torsoAll then hasTorso = true end
        if facts.legsAll then hasLegs = true end
        if facts.shoesAll then
            hasShoes = true
            shoesSlot = facts.slot
            if facts.footMin ~= nil then footMin = footMin == nil and facts.footMin or math.max(footMin, facts.footMin) end
        end
        if facts.outerAll then outerOk = true end
        if facts.headAll then headOk = true end
        for index = 1, #facts.ids do
            local rec = facts.recs[index]
            if rec then
                local suffix = Advisor.suffix(rec.location)
                if (rec.category == "jacket" or rec.category == "fullbody") and rec.insulation > rules.summerOuter then
                    summerOuter[#summerOuter + 1] = { slot = facts.slot, id = rec.id, name = Advisor.fullName(rec) }
                end
                if rec.category == "hat" and rec.insulation > rules.summerHat and rec.subcategory ~= "helmet" then
                    summerHat[#summerHat + 1] = { slot = facts.slot, id = rec.id, name = Advisor.fullName(rec) }
                end
                if rec.category == "scarf" then
                    scarf[#scarf + 1] = { slot = facts.slot, id = rec.id, name = Advisor.fullName(rec) }
                end
                if rec.cooling == "breathable" and (suffix == "shoes" or Health.BREATHABLE[suffix]) then
                    breathable[#breathable + 1] = { slot = facts.slot, id = rec.id, name = Advisor.fullName(rec) }
                end
            end
        end
    end
    local function names(list)
        local out = {}
        for index, entry in ipairs(list) do out[index] = entry.name end
        return Health.names(out)
    end
    local function fmt(value)
        return tostring(math.floor(value * 100 + 0.5) / 100)
    end
    if not unknown then
        if not hasTorso then Health.add(issues, "NO_TORSO", "No torso garment in every variant of this outfit", "Top") end
        if not hasLegs then Health.add(issues, "NO_LEGS", "No trousers, skirt or dress in every variant of this outfit", "Pants") end
        if not hasShoes then Health.add(issues, "NO_SHOES", "No shoes in every variant of this outfit", "Shoes") end
    end
    if season == 4 then
        if hasTorso and torsoMin < rules.winterTorso then
            Health.add(issues, "WINTER_LOW_TORSO", "Winter: torso too thin (" .. fmt(torsoMin) .. " of "
                .. fmt(rules.winterTorso) .. " warmth needed)", "Jacket")
        end
        if not outerOk and not unknown then
            Health.add(issues, "WINTER_NO_OUTER", "Winter: no outer layer (a jacket or coverall of "
                .. fmt(rules.winterOuter) .. " warmth or more)", "Jacket")
        end
        if not headOk and not unknown then
            Health.add(issues, "WINTER_COLD_HEAD", "Winter: bare head (no warm hat, hood or scarf)", "Hat")
        end
        if hasLegs and legsMin < rules.winterLegs then
            Health.add(issues, "WINTER_LIGHT_LEGS", "Winter: legs too light (" .. fmt(legsMin) .. " of "
                .. fmt(rules.winterLegs) .. " warmth needed)", "Pants")
        end
        if hasShoes and footMin ~= nil and footMin < rules.winterFoot then
            Health.add(issues, "WINTER_COLD_FEET", "Winter: shoes too light (" .. fmt(footMin) .. " of "
                .. fmt(rules.winterFoot) .. " warmth needed)", shoesSlot)
        end
        if #breathable > 0 then
            Health.add(issues, "WINTER_BREATHABLE", "Winter: summer wear on the outside (" .. names(breathable) .. ")",
                breathable[1].slot, breathable[1].id, { items = breathable })
        end
    elseif season == 2 then
        if torsoMax > rules.summerTorso then
            Health.add(issues, "SUMMER_HEAVY_TORSO", "Summer: torso layers too heavy (" .. fmt(torsoMax) .. ", at most "
                .. fmt(rules.summerTorso) .. ")", "Top")
        end
        if #summerOuter > 0 then
            Health.add(issues, "SUMMER_HEAVY_OUTER", "Summer: heavy outer layer (" .. names(summerOuter) .. ")",
                summerOuter[1].slot, summerOuter[1].id, { items = summerOuter })
        end
        if #summerHat > 0 then
            Health.add(issues, "SUMMER_WARM_HAT", "Summer: warm hat (" .. names(summerHat) .. ")",
                summerHat[1].slot, summerHat[1].id, { items = summerHat })
        end
        if #scarf > 0 then
            Health.add(issues, "SUMMER_SCARF", "Summer: scarf (" .. names(scarf) .. ")", scarf[1].slot, scarf[1].id,
                { items = scarf })
        end
    elseif season == 1 then
        if hasTorso and torsoMin < rules.springMin then
            Health.add(issues, "SPRING_COLD", "Spring: torso too thin (" .. fmt(torsoMin) .. " of "
                .. fmt(rules.springMin) .. ")", "Jacket")
        end
        if torsoMax > rules.springMax then
            Health.add(issues, "SPRING_HOT", "Spring: torso layers too heavy (" .. fmt(torsoMax) .. ", at most "
                .. fmt(rules.springMax) .. ")", "Jacket")
        end
    elseif season == 3 then
        if hasTorso and torsoMin < rules.autumnMin then
            Health.add(issues, "AUTUMN_THIN", "Autumn: torso too thin (" .. fmt(torsoMin) .. " of "
                .. fmt(rules.autumnMin) .. ")", "Jacket")
        end
        if torsoMax > rules.autumnMax then
            Health.add(issues, "AUTUMN_HOT", "Autumn: torso layers too heavy (" .. fmt(torsoMax) .. ", at most "
                .. fmt(rules.autumnMax) .. ")", "Jacket")
        end
    end
    return { torsoMin = torsoMin, torsoMax = torsoMax, legsMin = legsMin, legsMax = legsMax, footMin = footMin }
end

function Health.before(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    if a.code ~= b.code then return a.code < b.code end
    return tostring(a.text) < tostring(b.text)
end

function Health.evaluate(pools, season, role, services)
    local Master = ProjectALife.ClothingMaster
    if type(pools) ~= "table" or not Master.available() then return nil end
    Health.stats.evaluated = Health.stats.evaluated + 1
    local rules = Health.rules()
    local slots, unknown, known = {}, false, 0
    for slot, pool in pairs(pools) do
        local ids, none = Health.choices(pool)
        if #ids > 0 then
            local facts = Health.slotFacts(slot, ids, none, rules)
            slots[#slots + 1] = facts
            if facts.unknown then unknown = true end
            for index = 1, #ids do
                if facts.recs[index] then known = known + 1 end
            end
        end
    end
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    local issues = {}
    Health.collisionRules(issues, slots, services)
    Health.itemRules(issues, slots, season, role)
    local totals = Health.climateRules(issues, slots, season, rules, unknown)
    table.sort(issues, Health.before)
    return { ok = #issues == 0, issues = issues, season = season, empty = #slots == 0, known = known,
        unknown = unknown, totals = totals }
end

function Health.summary(result, season)
    local word = season ~= nil and string.lower(Health.SEASON_WORD[season]) or "any season"
    if result == nil then return "NO CLOTHING DATA" end
    if result.empty then return "EMPTY SET" end
    if result.ok then return "VALID FOR " .. string.upper(word) end
    local count = #result.issues
    return tostring(count) .. (count == 1 and " ISSUE" or " ISSUES") .. " FOR " .. string.upper(word)
end

function Health.detail(result, season)
    local lines = { Health.summary(result, season) }
    if result ~= nil then
        for _, issue in ipairs(result.issues) do lines[#lines + 1] = "- " .. issue.text end
    end
    return table.concat(lines, "\n")
end

function Health.fits(id, slot, pools, season, role, services)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    local rec = Master.get(id)
    if rec == nil then return false end
    local ctx = Advisor.context(slot, season, role, false)
    local rating = Advisor.rate({ id = rec.id, label = rec.name }, ctx)
    if rating.group == nil then return false end
    if season ~= nil and rec.seasons[season] < 2 then return false end
    if Health.collisionFor({ id = rec.id }, pools, slot, services) ~= nil then return false end
    return true
end

function Health.roleKey(role)
    if role == nil then return "civilian" end
    return role.key or role.kind or "civilian"
end

function Health.picks(season, role, category)
    local Master = ProjectALife.ClothingMaster
    local list = Master.shortlist(season, Health.roleKey(role), category)
    if list == nil then list = Master.shortlist(season, "civilian", category) end
    return list or {}
end

function Health.proposalFor(slot, pools, oldId, newId, note)
    local Advisor = ProjectALife.ClothingAdvisor
    local value = Health.poolWith(pools[slot], oldId, newId)
    local proposal = { slot = slot, value = value, id = newId, note = note }
    if newId ~= nil then proposal.name = Advisor.nameOf(newId) end
    if oldId ~= nil then proposal.replaces = Advisor.nameOf(oldId) end
    return proposal
end

function Health.addPicks(out, limit, slot, category, pools, season, role, services, oldId, filter, note)
    if season == nil then return end
    for _, id in ipairs(Health.picks(season, role, category)) do
        if #out >= limit then return end
        local rec = ProjectALife.ClothingMaster.get(id)
        local duplicate = false
        for _, existing in ipairs(out) do
            if existing.id == id and existing.slot == slot then duplicate = true end
        end
        if not duplicate and rec ~= nil and (filter == nil or filter(rec))
                and Health.fits(id, slot, pools, season, role, services) then
            out[#out + 1] = Health.proposalFor(slot, pools, oldId, id, note)
        end
    end
end

function Health.suggest(issue, pools, season, role, services, limit)
    local Master, Advisor = ProjectALife.ClothingMaster, ProjectALife.ClothingAdvisor
    Health.stats.suggested = Health.stats.suggested + 1
    limit = limit or 4
    local out = {}
    if issue == nil or type(pools) ~= "table" then return out end
    local rules = Health.rules()
    local code = issue.code
    local seasonName = season ~= nil and string.lower(Health.SEASON_WORD[season]) or nil
    local note = seasonName ~= nil and ("suits " .. seasonName) or nil
    if code == "COLLISION" and issue.items ~= nil and issue.items[2] ~= nil then
        local first, second = issue.items[1], issue.items[2]
        local recA, recB = Master.get(first.id), Master.get(second.id)
        local alt = Health.alternative(recA, recB, services)
        if alt ~= nil then
            local slot = alt.side == "candidate" and first.slot or second.slot
            out[#out + 1] = Health.proposalFor(slot, pools, alt.from, alt.id, "compatible variant")
        end
        out[#out + 1] = Health.proposalFor(second.slot, pools, second.id, nil, "removes the clash")
        if #out < limit then out[#out + 1] = Health.proposalFor(first.slot, pools, first.id, nil, "removes the clash") end
        return out
    end
    if code == "NO_TORSO" then
        Health.addPicks(out, limit, "Top", "top", pools, season, role, services, nil, nil, note)
    elseif code == "NO_LEGS" then
        Health.addPicks(out, limit, "Pants", "bottom", pools, season, role, services, nil, nil, note)
    elseif code == "NO_SHOES" then
        Health.addPicks(out, limit, "Shoes", "shoes", pools, season, role, services, nil, nil, note)
    elseif code == "WINTER_NO_OUTER" or code == "WINTER_LOW_TORSO" or code == "SPRING_COLD" or code == "AUTUMN_THIN" then
        local minimum = code == "WINTER_NO_OUTER" and rules.winterOuter or 0.5
        Health.addPicks(out, limit, "Jacket", "jacket", pools, season, role, services, nil,
            function(rec) return rec.insulation >= minimum end, note)
    elseif code == "WINTER_COLD_HEAD" then
        Health.addPicks(out, limit, "Hat", "hat", pools, season, role, services, nil,
            function(rec) return Health.headOk(rec, rules.winterHead) end, note)
        Health.addPicks(out, limit, "Scarf", "scarf", pools, season, role, services, nil, nil, note)
    elseif code == "WINTER_LIGHT_LEGS" then
        Health.addPicks(out, limit, "Pants", "bottom", pools, season, role, services, nil,
            function(rec) return rec.insulation >= rules.winterLegs end, note)
    elseif code == "WINTER_COLD_FEET" then
        Health.addPicks(out, limit, "Shoes", "shoes", pools, season, role, services, nil,
            function(rec) return rec.insulation >= rules.winterFoot end, note)
    elseif issue.items ~= nil and issue.items[1] ~= nil then
        local target = issue.items[1]
        local rec = Master.get(target.id)
        if rec ~= nil and season ~= nil then
            local slot = target.slot
            Health.addPicks(out, limit - 1, slot, rec.category, pools, season, role, services, target.id, nil, note)
        end
        if #out < limit then
            out[#out + 1] = Health.proposalFor(target.slot, pools, target.id, nil, "removes " .. Advisor.nameOf(target.id))
        end
    elseif issue.slot ~= nil and issue.id ~= nil then
        out[#out + 1] = Health.proposalFor(issue.slot, pools, issue.id, nil, "removes " .. Advisor.nameOf(issue.id))
    end
    return out
end

return Health
