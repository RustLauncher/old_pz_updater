ProjectALife = ProjectALife or {}

local Generator = {}
ProjectALife.SeasonalOutfitGenerator = Generator
Generator.seasons = { A = "spring", B = "summer", C = "autumn", D = "winter" }
Generator.letters = { "A", "B", "C", "D" }
Generator.slots = {
    hat = "Hat", fullhat = "Hat", eyes = "Eyes", mask = "Mask", maskeyes = "Mask", scarf = "Scarf",
    shirt = "Top", shortsleeveshirt = "Top", tshirt = "Tshirt", tanktop = "Tshirt", sweater = "Sweater", sweaterhat = "Sweater",
    jacket = "Jacket", jacket_bulky = "Jacket", jacket_down = "Jacket", jackethat_bulky = "Jacket", jacketsuit = "Jacket", jackethat = "Jacket",
    pants = "Pants", pants_skinny = "Pants", shortpants = "Pants", shortsshort = "Pants", shoes = "Shoes", hands = "Hands",
    boilersuit = "FullSuit", fullsuit = "FullSuit", fullsuithead = "FullSuit", torsoextravestbullet = "Vest", torsoextravest = "Vest",
}
Generator.uniform = {
    military = { Top = "Base.Shirt_CamoGreen", Tshirt = "Base.Tshirt_ArmyGreen", Pants = "Base.Trousers_CamoGreen", Jacket = "Base.Jacket_ArmyOliveDrab", Shoes = "Base.Shoes_ArmyBoots" },
    law = { Top = "Base.Shirt_PoliceBlue", Tshirt = "Base.Tshirt_PoliceBlue", Pants = "Base.Trousers_Police", Jacket = "Base.Jacket_Police", Shoes = "Base.Shoes_Black" },
    fire = { Top = "Base.Tshirt_Profession_FiremanBlue", Tshirt = "Base.Tshirt_Profession_FiremanBlue", Pants = "Base.Trousers_Fireman", Jacket = "Base.Jacket_Fireman", Shoes = "Base.Shoes_WorkBoots" },
    medical = { Top = "Base.Shirt_Scrubs", Tshirt = "Base.Tshirt_Scrubs", Pants = "Base.Trousers_Scrubs", Jacket = "Base.Jacket_NavyBlue", Shoes = "Base.Shoes_TrainerTINT" },
    civilian = { Top = "Base.Shirt_Denim", Tshirt = "Base.Tshirt_DefaultTEXTURE_TINT", Pants = "Base.Trousers_Denim", Jacket = "Base.Jacket_Padded", Shoes = "Base.Shoes_WorkBoots" },
}
function Generator.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Generator.copy(child) end
    return out
end
function Generator.nonempty(outfit)
    if type(outfit) ~= "table" then return false end
    for _, value in pairs(outfit) do if value ~= nil and value ~= "" and value ~= "none" then return true end end
    return false
end
function Generator.ownOutfit(profile, letter)
    return profile.outfitSets and profile.outfitSets[letter]
        or profile["outfit" .. letter]
        or profile.outfits and profile.outfits[letter]
end
function Generator.signature(outfit)
    local entries = {}
    for key, value in pairs(outfit or {}) do if value ~= "none" and value ~= "" then entries[#entries + 1] = tostring(key) .. ":" .. tostring(value) end end
    table.sort(entries)
    return table.concat(entries, ";")
end
Generator.stockBloc = {
    alife_police = "law", alife_guard = "military", alife_cordon = "military",
    alife_fire = "rescue", alife_riverside = "civilian", alife_kettle = "worker",
}
Generator.uniformBloc = { law = "law", military = "military", elite = "military" }
Generator.plainBloc = {
    civilian = true, family = true, worker = true, crime = true,
    raider = true, club = true, gang = true, federation = true,
}
Generator.classWords = {
    { "fire", { fireman = true, firemen = true, firefighter = true, firefighters = true, firehouse = true, firehall = true, vfd = true, fire = true } },
    { "medical", { medical = true, medic = true, medics = true, infirmary = true, scrubs = true, nurse = true, nurses = true,
        doctor = true, doctors = true, paramedic = true, paramedics = true, ems = true } },
    { "law", { police = true, sheriff = true, sheriffs = true, trooper = true, troopers = true, law = true,
        corrections = true, ranger = true, rangers = true, federal = true, swat = true } },
    { "military", { military = true, army = true, camo = true, guard = true, armor = true, airborne = true,
        cordon = true, infantry = true, reservist = true, reservists = true } },
}
Generator.classPhrases = { { "law", " prison guard " }, { "military", " special forces " } }
function Generator.blocOf(faction)
    if type(faction) ~= "table" then return nil end
    local relations = type(faction.relations) == "table" and faction.relations or nil
    local bloc = relations ~= nil and relations.bloc or nil
    if type(bloc) == "string" and bloc ~= "" then return string.lower(bloc) end
    return Generator.stockBloc[tostring(faction.id)]
end
function Generator.words(value, set, list)
    local text = string.gsub(string.lower(tostring(value or "")), "in[%s%-]+law", " ")
    for word in string.gmatch(text, "%a+") do
        set[word] = true
        list[#list + 1] = word
    end
end
function Generator.wordClass(set, list)
    local joined = " " .. table.concat(list, " ") .. " "
    for _, phrase in ipairs(Generator.classPhrases) do
        if string.find(joined, phrase[2], 1, true) then return phrase[1] end
    end
    for _, entry in ipairs(Generator.classWords) do
        for word in pairs(entry[2]) do
            if set[word] then return entry[1] end
        end
    end
    return nil
end
function Generator.classOf(profile, faction)
    local bloc = Generator.blocOf(faction)
    if bloc ~= nil and Generator.uniformBloc[bloc] ~= nil then return Generator.uniformBloc[bloc] end
    local plain = bloc ~= nil and Generator.plainBloc[bloc] == true
    local set, list = {}, {}
    local records = plain and { faction } or { profile or {}, faction or {} }
    for _, record in ipairs(records) do
        local general = type(record.general) == "table" and record.general or {}
        local category = plain and "" or general.category
        for _, value in ipairs({ record.id or "", general.name or "", general.tags or "", general.profession or "", category or "" }) do
            Generator.words(value, set, list)
        end
    end
    local kind = Generator.wordClass(set, list)
    if kind ~= nil then return kind end
    if plain then return "civilian" end
    set, list = {}, {}
    for _, record in ipairs({ profile or {}, faction or {} }) do
        for _, value in pairs(record.clothing or record.outfitA or (record.outfits and record.outfits.A) or {}) do Generator.words(value, set, list) end
    end
    return Generator.wordClass(set, list) or "civilian"
end
function Generator.location(id)
    if type(getScriptManager) ~= "function" then return nil end
    local manager = getScriptManager()
    if manager == nil or type(manager.FindItem) ~= "function" then return nil end
    local item = manager:FindItem(id)
    if item == nil then return false end
    if type(item.getBodyLocation) ~= "function" then return "" end
    return string.gsub(string.lower(tostring(item:getBodyLocation() or "")), "^base:", "")
end
function Generator.forbidden(id)
    local text = string.lower(tostring(id))
    for _, token in ipairs({ "shorts_", "swim", "bikini", "sandals", "flipflop", "vest_defaulttexture", "briefs", "boxers", "croptop", "skirt_mini", "skirt_short" }) do if string.find(text, token, 1, true) then return true end end
    local loc = Generator.location(id)
    return loc == "tanktop" or loc == "shortpants" or loc == "shortsshort" or (type(loc) == "string" and string.find(loc, "underwear", 1, true) ~= nil)
end
function Generator.seasonal(base, season, kind)
    local out, uniform = {}, Generator.uniform[kind] or Generator.uniform.civilian
    local keys = {}
    for key in pairs(base or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, slot in ipairs(keys) do
        for id in string.gmatch(tostring(base[slot]), "[^|]+") do
            if id ~= "none" and id ~= "" then
                if not string.find(id, ".", 1, true) then id = "Base." .. id end
                local location = Generator.location(id)
                local target = Generator.slots[location] or slot
                if kind ~= "civilian" and Generator.forbidden(id) then id = uniform[target] end
                if season ~= "summer" and id ~= nil and Generator.forbidden(id) then id = uniform[target] end
                if id ~= nil and location ~= false then
                    if out[target] == nil then out[target] = id
                    elseif not string.find("|" .. out[target] .. "|", "|" .. id .. "|", 1, true) then out[target] = out[target] .. "|" .. id end
                end
            end
        end
    end
    if out.Top == nil and out.Tshirt == nil and out.FullSuit == nil then out.Tshirt = uniform.Tshirt end
    if out.Pants == nil and out.FullSuit == nil then out.Pants = uniform.Pants end
    if out.Shoes == nil then out.Shoes = uniform.Shoes end
    if season == "summer" then
        out.Jacket = nil; out.Sweater = nil; out.Scarf = nil; out.Hands = nil
        if out.Top ~= nil then out.Top = nil; out.Tshirt = uniform.Tshirt end
    elseif season == "spring" then
        out.Hands = nil; out.Scarf = nil; out.Sweater = nil
        out.Jacket = (out.Jacket or uniform.Jacket) .. "|none"
    elseif season == "autumn" then
        out.Jacket = out.Jacket or uniform.Jacket
        out.Sweater = "Base.Jumper_RoundNeck"; out.Hands = nil; out.Scarf = nil
    elseif season == "winter" then
        out.Jacket = out.Jacket or uniform.Jacket
        out.Hands = "Base.Gloves_LeatherGlovesBlack"
        out.Hat = "Base.Hat_Beany"
        out.Sweater = out.Sweater or "Base.Jumper_RoundNeck"
    end
    return out
end
function Generator.summary()
    return { changed = false, addedOutfits = 0, addedTags = 0, warnings = {}, complete = true }
end
function Generator.deleted(record)
    local value = type(record) == "table" and type(record.general) == "table" and record.general.deleted
    return value == true or value == "true"
end
function Generator.inspect(out, summary, faction)
    local seen, kind = {}, Generator.classOf(out, faction)
    for _, letter in ipairs(Generator.letters) do
        local outfit = out.outfits and out.outfits[letter] or out["outfit" .. letter]
        local signature = Generator.signature(outfit)
        if seen[signature] or signature == "" then summary.warnings[#summary.warnings + 1] = "Preserved missing or duplicate outfit " .. letter; summary.complete = false end
        seen[signature] = true
        local tag = (out.outfitSeason or {})[letter]
        if tag ~= Generator.seasons[letter] and not Generator.untagged(out, letter) then summary.warnings[#summary.warnings + 1] = "Preserved different season tag " .. letter; summary.complete = false end
        for _, value in pairs(outfit or {}) do for id in string.gmatch(tostring(value), "[^|]+") do
            if id ~= "none" and kind ~= "civilian" and Generator.forbidden(id) then summary.warnings[#summary.warnings + 1] = "Preserved authored uniform conflict " .. letter .. ": " .. id; summary.complete = false end
        end end
        if letter == "D" then for _, slot in ipairs({ "Jacket", "Hands", "Hat" }) do
            local value = outfit and outfit[slot]
            if value == nil or value == "" or string.find("|" .. tostring(value) .. "|", "|none|", 1, true) then summary.warnings[#summary.warnings + 1] = "Preserved authored winter outfit lacks guaranteed " .. slot; summary.complete = false end
        end end
    end
end
function Generator.occupied(outfit)
    if type(outfit) ~= "table" then return false end
    for _ in pairs(outfit) do return true end
    return false
end
function Generator.untagged(profile, letter)
    local tag = type(profile.outfitSeason) == "table" and profile.outfitSeason[letter] or nil
    return tag == nil or tag == "" or string.lower(tostring(tag)) == "random"
end
function Generator.synthetic(profile, letter)
    local Custom = ProjectALife.CustomProfiles
    if letter ~= "A" or type(Custom) ~= "table" or type(Custom.syntheticOutfit) ~= "function" then return false end
    return Custom.syntheticOutfit(profile, letter) == true
end
function Generator.enabled(profile, letter)
    return type(profile.outfitEnabled) ~= "table" or profile.outfitEnabled[letter] ~= false
end
function Generator.keepsAuthored(profile)
    local kept = {}
    for _, letter in ipairs({ "A", "B", "C", "D", "E", "F" }) do
        if Generator.occupied(Generator.ownOutfit(profile, letter)) and Generator.enabled(profile, letter)
                and Generator.untagged(profile, letter) and not Generator.synthetic(profile, letter) then
            kept[#kept + 1] = letter
        end
    end
    if #kept == 0 then return nil, 0 end
    local open = 0
    for _, letter in ipairs(Generator.letters) do
        if not (Generator.occupied(Generator.ownOutfit(profile, letter)) and Generator.enabled(profile, letter)) then open = open + 1 end
    end
    return kept, open
end
function Generator.profile(profile, faction)
    local out = Generator.copy(profile)
    local summary = Generator.summary()
    if Generator.deleted(profile) then summary.skipped = true; summary.reason = "deleted"; return out, summary end
    local outfits = Generator.copy(out.outfits or {})
    for _, letter in ipairs({ "A", "B", "C", "D", "E", "F" }) do
        local own = Generator.ownOutfit(out, letter)
        if own ~= nil then outfits[letter] = own end
    end
    out.outfits = outfits
    out.outfitSeason = out.outfitSeason or {}
    out.outfitEnabled = out.outfitEnabled or {}
    local kept, open = Generator.keepsAuthored(out)
    if kept ~= nil then
        out.outfitSets = outfits
        summary.skipped, summary.reason, summary.kept, summary.openSeasons = true, "authored", kept, open
        return out, summary
    end
    local base = out.clothing
    if not Generator.nonempty(base) then base = out.outfits.A or out.outfitA or {} end
    local kind = Generator.classOf(out, faction)
    for _, letter in ipairs(Generator.letters) do
        local season = Generator.seasons[letter]
        local own = out.outfits[letter] or out["outfit" .. letter]
        local tagIt = false
        if not Generator.occupied(own) then
            out.outfits[letter] = Generator.seasonal(base, season, kind)
            out.outfitEnabled[letter] = true
            summary.changed = true; summary.addedOutfits = summary.addedOutfits + 1
            tagIt = true
        else
            if out.outfits[letter] == nil then out.outfits[letter] = Generator.copy(own) end
            tagIt = Generator.enabled(out, letter) and Generator.synthetic(out, letter)
        end
        if tagIt and Generator.untagged(out, letter) then
            out.outfitSeason[letter] = season
            summary.changed = true; summary.addedTags = summary.addedTags + 1
        end
    end
    out.outfitSets = out.outfits
    Generator.inspect(out, summary, faction)
    return out, summary
end
function Generator.faction(faction, members)
    local out, summary = Generator.copy(faction), Generator.summary()
    if Generator.deleted(faction) then summary.skipped = true; summary.reason = "deleted"; return out, summary end
    local candidates = {}
    for _, member in pairs(members or {}) do if type(member) == "table" and not Generator.deleted(member) and member.general and member.general.faction == faction.id then candidates[#candidates + 1] = member end end
    table.sort(candidates, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local member = candidates[1] or { general = {}, clothing = {} }
    local kind = Generator.classOf(member, faction)
    out.outfitSeason = out.outfitSeason or {}; out.outfitNames = out.outfitNames or {}
    for _, letter in ipairs(Generator.letters) do
        local season = Generator.seasons[letter]
        if not Generator.nonempty(out["outfit" .. letter]) then
            local base = Generator.ownOutfit(member, letter) or member.clothing or {}
            out["outfit" .. letter] = Generator.seasonal(base, season, kind)
            summary.changed = true; summary.addedOutfits = summary.addedOutfits + 1
        end
        if out.outfitSeason[letter] == nil or out.outfitSeason[letter] == "" then out.outfitSeason[letter] = season; summary.changed = true; summary.addedTags = summary.addedTags + 1 end
        if out.outfitNames[letter] == nil or out.outfitNames[letter] == "" then out.outfitNames[letter] = tostring((out.general or {}).name or out.id or "Faction") .. " - " .. season .. " " .. kind .. " kit"; summary.changed = true end
    end
    Generator.inspect(out, summary, faction)
    return out, summary
end
