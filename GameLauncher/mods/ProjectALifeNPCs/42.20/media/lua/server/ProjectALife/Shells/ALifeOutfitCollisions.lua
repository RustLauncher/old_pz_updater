ProjectALife = ProjectALife or {}

local Outfits = {
    locations = {}, keys = {}, locationCount = 0, locationCap = 2048,
    verdicts = {}, verdictCount = 0, verdictCap = 8192,
    metrics = { passes = 0, resolved = 0, redrawn = 0, swapped = 0, dropped = 0 },
}
ProjectALife.OutfitCollisions = Outfits

Outfits.rank = {
    Wrist = 6, Fingers = 5, Ears = 8, Faces = 9, Eyes = 10, Mask = 12, Neck = 14, Belt = 15, Holster = 16,
    Scarf = 20, AmmoStrap = 22, Back = 25, Hands = 28, Hat = 30,
    Vest = 60, Sweater = 70, Jacket = 80, Top = 90, Tshirt = 90, TankTop = 90, Pants = 100, Socks = 96,
    Shoes = 98, Underwear = 99,
}
Outfits.defaultRank = 50
Outfits.maxPasses = 12
Outfits.maxChoices = 4

Outfits.hoodDown = {
    ["Base.Jacket_Padded"] = "Base.Jacket_PaddedDOWN",
    ["Base.Jacket_Padded_HuntingCamo"] = "Base.Jacket_Padded_HuntingCamoDOWN",
    ["Base.HoodieUP_WhiteTINT"] = "Base.HoodieDOWN_WhiteTINT",
    ["Base.Hoodie_Hide_UP"] = "Base.Hoodie_Hide_DOWN",
    ["Base.Hoodie_HuntingCamo_UP"] = "Base.Hoodie_HuntingCamo_DOWN",
}

function Outfits.group()
    if BodyLocations == nil or type(BodyLocations.getGroup) ~= "function" then return nil end
    local ok, group = pcall(BodyLocations.getGroup, "Human")
    if not ok or group == nil or type(group.isExclusive) ~= "function" then return nil end
    return group
end

function Outfits.locationOf(itemType)
    local known = Outfits.locations[itemType]
    if known ~= nil then return known or nil end
    local hydrator = ProjectALife.ProfileHydrator
    local location = nil
    if hydrator ~= nil and type(hydrator.scriptLocation) == "function" then
        location = hydrator.scriptLocation(itemType)
    end
    if Outfits.locationCount >= Outfits.locationCap then
        Outfits.locations, Outfits.keys, Outfits.locationCount = {}, {}, 0
    end
    Outfits.locations[itemType] = location or false
    if location ~= nil then Outfits.keys[itemType] = tostring(location) end
    Outfits.locationCount = Outfits.locationCount + 1
    return location
end

function Outfits.keyOf(itemType)
    if Outfits.locations[itemType] == nil then Outfits.locationOf(itemType) end
    return Outfits.keys[itemType]
end

function Outfits.collides(group, itemA, itemB)
    local keyA, keyB = Outfits.keyOf(itemA), Outfits.keyOf(itemB)
    if keyA == nil or keyB == nil then return false end
    local row = Outfits.verdicts[keyA]
    if row ~= nil and row[keyB] ~= nil then return row[keyB] end
    local first, second = Outfits.locations[itemA], Outfits.locations[itemB]
    if not first or not second then return false end
    local verdict
    if keyA == keyB or first == second then
        verdict = not (type(group.isMultiItem) == "function" and group:isMultiItem(first) == true)
    else
        verdict = group:isExclusive(first, second) == true
    end
    if Outfits.verdictCount >= Outfits.verdictCap then Outfits.verdicts, Outfits.verdictCount = {}, 0 end
    row = Outfits.verdicts[keyA]
    if row == nil then
        row = {}
        Outfits.verdicts[keyA] = row
    end
    row[keyB] = verdict
    Outfits.verdictCount = Outfits.verdictCount + 1
    return verdict
end

function Outfits.itemCollides(group, itemType, entries, skip)
    if Outfits.keyOf(itemType) == nil then return false end
    for _, other in ipairs(entries) do
        if other ~= skip and type(other.itemType) == "string" and Outfits.collides(group, itemType, other.itemType) then
            return true
        end
    end
    return false
end

function Outfits.rankOf(entry)
    return Outfits.rank[tostring(entry.slot)] or Outfits.defaultRank
end

function Outfits.firstConflict(group, entries)
    local count = #entries
    local keys = {}
    for index = 1, count do
        local item = entries[index].itemType
        keys[index] = type(item) == "string" and Outfits.keyOf(item) or false
    end
    local verdicts = Outfits.verdicts
    for first = 1, count - 1 do
        local keyA = keys[first]
        if keyA then
            local row = verdicts[keyA]
            for second = first + 1, count do
                local keyB = keys[second]
                if keyB then
                    local known = nil
                    if row ~= nil then known = row[keyB] end
                    if known == nil then
                        known = Outfits.collides(group, entries[first].itemType, entries[second].itemType)
                    end
                    if known then return entries[first], entries[second] end
                end
            end
        end
    end
    return nil, nil
end

function Outfits.choices(raw)
    local list = {}
    if type(raw) ~= "string" then return list end
    for choice in string.gmatch(raw .. "|", "(.-)|") do
        choice = string.match(choice, "^%s*(.-)%s*$")
        if choice ~= "" and #list < Outfits.maxChoices then list[#list + 1] = choice end
    end
    return list
end

function Outfits.known(itemType)
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator == nil or type(hydrator.itemKnown) ~= "function" then return true end
    return hydrator.itemKnown(itemType) == true
end

function Outfits.redraw(group, entries, loser, selected, seed)
    local list = Outfits.choices(type(selected) == "table" and selected[loser.slot] or nil)
    local count = #list
    if count < 2 then return false end
    local appearance = ProjectALife.Appearance
    local start = 0
    if appearance ~= nil and type(appearance.unit) == "function" then
        start = math.floor(appearance.unit(seed, tostring(loser.slot) .. "|redraw") * count)
    end
    for step = 0, count - 1 do
        local candidate = list[1 + (start + step) % count]
        if candidate ~= loser.itemType and string.lower(candidate) ~= "none" and Outfits.known(candidate)
                and not Outfits.itemCollides(group, candidate, entries, loser) then
            loser.itemType = candidate
            Outfits.metrics.redrawn = Outfits.metrics.redrawn + 1
            return true
        end
    end
    return false
end

function Outfits.unhood(group, entries, first, second)
    for _, entry in ipairs({ first, second }) do
        local down = Outfits.hoodDown[entry.itemType]
        if down ~= nil and Outfits.known(down) and not Outfits.itemCollides(group, down, entries, entry) then
            entry.itemType = down
            Outfits.metrics.swapped = Outfits.metrics.swapped + 1
            return true
        end
    end
    return false
end

function Outfits.remove(entries, loser)
    for index, entry in ipairs(entries) do
        if entry == loser then
            table.remove(entries, index)
            Outfits.metrics.dropped = Outfits.metrics.dropped + 1
            return true
        end
    end
    return false
end

function Outfits.resolve(plan, selected, seed)
    local entries = type(plan) == "table" and plan.clothing or nil
    if type(entries) ~= "table" or #entries < 2 then return 0 end
    local group = Outfits.group()
    if group == nil then return 0 end
    Outfits.metrics.passes = Outfits.metrics.passes + 1
    local resolved = 0
    for _ = 1, Outfits.maxPasses do
        local first, second = Outfits.firstConflict(group, entries)
        if first == nil then break end
        local loser = first
        if Outfits.rankOf(second) < Outfits.rankOf(first) then loser = second end
        if not Outfits.redraw(group, entries, loser, selected, seed)
                and not Outfits.unhood(group, entries, first, second)
                and not Outfits.remove(entries, loser) then
            break
        end
        resolved = resolved + 1
    end
    if resolved > 0 then
        Outfits.metrics.resolved = Outfits.metrics.resolved + resolved
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator ~= nil and type(hydrator.renderOrder) == "function" then hydrator.renderOrder(entries) end
    end
    return resolved
end

return Outfits
