local VANILLA = {
    ["Shoes_TrainerTINT"] = true,
    ["Shoes_BlueTrainers"] = true,
    ["Shoes_RedTrainers"] = true,
    ["Base.Shoes_TrainerTINT"] = true,
    ["Base.Shoes_BlueTrainers"] = true,
    ["Base.Shoes_RedTrainers"] = true,
}

local PREFIX = "RandomSneakers."

local function isOurs(name)
    return type(name) == "string" and string.sub(name, 1, string.len(PREFIX)) == PREFIX
end

local function forEachItemList(fn)
    local seen = {}
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "table" then
                if k == "items" then
                    if not seen[v] then
                        seen[v] = true
                        fn(v)
                    end
                else
                    walk(v)
                end
            end
        end
    end
    if ProceduralDistributions and ProceduralDistributions.list then walk(ProceduralDistributions.list) end
    if SuburbsDistributions then walk(SuburbsDistributions) end
    if VehicleDistributions then walk(VehicleDistributions) end
end

local function collectOurs()
    local set, list = {}, {}
    forEachItemList(function(items)
        for i = 1, #items, 2 do
            local name = items[i]
            if isOurs(name) and not set[name] then
                set[name] = true
                list[#list + 1] = name
            end
        end
    end)
    table.sort(list)
    return list
end

local function replaceIn(items, ours)
    local n = #items
    local removed, total, hasOurs = 0, 0, false
    for i = 1, n - 1, 2 do
        local name, chance = items[i], items[i + 1]
        if VANILLA[name] and type(chance) == "number" then
            removed = removed + 1
            total = total + chance
        elseif isOurs(name) then
            hasOurs = true
        end
    end
    if removed == 0 then return 0, false end

    local out = {}
    local placed = hasOurs
    local share = total / #ours
    for i = 1, n, 2 do
        local name, chance = items[i], items[i + 1]
        if VANILLA[name] and type(chance) == "number" then
            if not placed then
                for _, item in ipairs(ours) do
                    out[#out + 1] = item
                    out[#out + 1] = share
                end
                placed = true
            end
        else
            out[#out + 1] = name
            out[#out + 1] = chance
        end
    end
    for i = 1, #out do
        items[i] = out[i]
    end
    for i = n, #out + 1, -1 do
        items[i] = nil
    end
    return removed, not hasOurs
end

local function replaceVanillaSneakers()
    local ours = collectOurs()
    if #ours == 0 then
        print("[RandomSneakers] replace vanilla: no Random Sneakers found in the loot tables, nothing changed")
        return
    end
    local removed, lists, added = 0, 0, 0
    forEachItemList(function(items)
        local r, a = replaceIn(items, ours)
        if r > 0 then
            removed = removed + r
            lists = lists + 1
            if a then added = added + 1 end
        end
    end)
    print("[RandomSneakers] replace vanilla: " .. removed .. " vanilla sneaker entries removed from " .. lists ..
          " loot lists; " .. #ours .. " Random Sneakers added to the " .. added .. " lists that had none")
end

Events.OnPostDistributionMerge.Add(replaceVanillaSneakers)
