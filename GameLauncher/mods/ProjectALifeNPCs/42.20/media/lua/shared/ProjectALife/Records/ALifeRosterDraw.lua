require "ProjectALife/Records/ALifeCatalog"

ProjectALife = ProjectALife or {}

local Draw = {
    dupeFactor = 0.25,
    metrics = { picks = 0, avoided = 0, exhausted = 0, lookShifted = 0 },
    lookKeys = setmetatable({}, { __mode = "k" }),
}
ProjectALife.RosterDraw = Draw

function Draw.weight(profile)
    local general = type(profile) == "table" and type(profile.general) == "table" and profile.general or nil
    return math.max(0, tonumber(general and general.spawnWeight) or 1)
end

function Draw.idOf(profile)
    if type(profile) == "table" then return profile.id end
    return profile
end

function Draw.checksum(text)
    local value = 5381
    for index = 1, #text do value = (value * 33 + string.byte(text, index)) % 2147483647 end
    return value
end

function Draw.outfitText(profile)
    local parts = {}
    local sets = { profile.clothing, profile.outfitA, profile.outfitB, profile.outfitC, profile.outfitD }
    local named = type(profile.outfitSets) == "table" and profile.outfitSets or nil
    if named ~= nil then sets = { profile.clothing, named.A, named.B, named.C, named.D } end
    for position = 1, 5 do
        local set = sets[position]
        if type(set) == "table" then
            local slots = {}
            for slot, value in pairs(set) do slots[#slots + 1] = tostring(slot) .. "=" .. tostring(value) end
            table.sort(slots)
            parts[#parts + 1] = position .. ":" .. table.concat(slots, ",")
        end
    end
    return table.concat(parts, ";")
end

function Draw.lookKey(profile)
    if type(profile) ~= "table" then return "" end
    local known = Draw.lookKeys[profile]
    if known ~= nil then return known end
    local general = type(profile.general) == "table" and profile.general or {}
    local key = table.concat({
        general.female == true and "f" or "m", tostring(general.skin or 0),
        tostring(general.hairStyle or ""), tostring(general.hairColor or ""),
        tostring(general.beardStyle or ""), tostring(general.beardColor or ""),
        tostring(Draw.checksum(Draw.outfitText(profile))),
    }, "|")
    Draw.lookKeys[profile] = key
    return key
end

function Draw.begin(taken)
    local state = { ids = {}, looks = {}, count = 0 }
    if type(taken) == "table" then
        for _, id in ipairs(taken) do
            if type(id) == "string" then
                state.ids[id] = true
                state.count = state.count + 1
            end
        end
    end
    return state
end

function Draw.fractionOf(source)
    if type(source) == "function" then return source() end
    return source
end

function Draw.open(roster, state, penalised)
    local weights, total = {}, 0
    for position, profile in ipairs(roster) do
        local weight = Draw.weight(profile)
        if weight > 0 and state.ids[Draw.idOf(profile)] == true then weight = 0 end
        if weight > 0 and penalised and state.looks[Draw.lookKey(profile)] == true then
            weight = weight * Draw.dupeFactor
        end
        weights[position] = weight
        total = total + weight
    end
    return weights, total
end

function Draw.pick(roster, state, fraction)
    if type(roster) ~= "table" or type(state) ~= "table" or #roster == 0 then return nil end
    local full = 0
    for _, profile in ipairs(roster) do full = full + Draw.weight(profile) end
    if full <= 0 then return nil end
    local roll = tonumber(Draw.fractionOf(fraction))
    local catalog = ProjectALife.Catalog
    if roll == nil and type(catalog) == "table" and type(catalog.randomFraction) == "function" then
        roll = catalog.randomFraction()
    end
    roll = math.max(0, math.min(0.999999999, tonumber(roll) or 0))
    local legacy = nil
    if type(catalog) == "table" and type(catalog.weightedProfile) == "function" then
        legacy = catalog.weightedProfile(roster, roll)
    end
    local weights, total = Draw.open(roster, state, true)
    local exhausted = false
    if total <= 0 then
        exhausted = true
        state.ids, state.looks, state.count = {}, {}, 0
        weights, total = Draw.open(roster, state, true)
        Draw.metrics.exhausted = Draw.metrics.exhausted + 1
    end
    local needle, chosen, last = roll * total, nil, nil
    for position, profile in ipairs(roster) do
        local weight = weights[position]
        if weight > 0 then
            last = profile
            needle = needle - weight
            if needle < 0 then chosen = profile break end
        end
    end
    chosen = chosen or last
    if chosen == nil then return nil end
    Draw.metrics.picks = Draw.metrics.picks + 1
    if not exhausted and legacy ~= nil and state.ids[Draw.idOf(legacy)] == true then
        Draw.metrics.avoided = Draw.metrics.avoided + 1
    end
    if legacy ~= nil and legacy ~= chosen and state.ids[Draw.idOf(legacy)] ~= true
            and state.looks[Draw.lookKey(legacy)] == true then
        Draw.metrics.lookShifted = Draw.metrics.lookShifted + 1
    end
    state.ids[Draw.idOf(chosen)] = true
    state.looks[Draw.lookKey(chosen)] = true
    state.count = state.count + 1
    return chosen, exhausted
end

function Draw.squad(roster, count, fraction)
    local state, picked = Draw.begin(), {}
    for _ = 1, math.max(0, math.floor(tonumber(count) or 0)) do
        local profile = Draw.pick(roster, state, fraction)
        if profile == nil then break end
        picked[#picked + 1] = profile
    end
    return picked
end

function Draw.qaPart()
    local m = Draw.metrics
    return "rosterRepeatsAvoided=" .. tostring(m.avoided)
end

return Draw
