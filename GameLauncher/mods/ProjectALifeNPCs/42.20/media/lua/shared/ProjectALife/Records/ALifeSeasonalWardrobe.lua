ProjectALife = ProjectALife or {}

local Wardrobe = { ids = { "A", "B", "C", "D" },
    seasons = { A = "spring", B = "summer", C = "autumn", D = "winter" },
    labels = { A = "Spring", B = "Summer", C = "Autumn", D = "Winter" } }
ProjectALife.SeasonalWardrobe = Wardrobe

function Wardrobe.signature(clothing)
    local slots = {}
    for slot, value in pairs(type(clothing) == "table" and clothing or {}) do
        local choices, seen = {}, {}
        for item in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
            item = string.match(item, "^%s*(.-)%s*$")
            if item ~= "" and item ~= "none" and not seen[item] then
                seen[item] = true
                choices[#choices + 1] = item
            end
        end
        if #choices > 0 then
            table.sort(choices)
            slots[#slots + 1] = tostring(slot) .. "=" .. table.concat(choices, "|")
        end
    end
    table.sort(slots)
    return table.concat(slots, ";")
end

function Wardrobe.rows(faction)
    faction = type(faction) == "table" and faction or {}
    local rows = {}
    for _, id in ipairs(Wardrobe.ids) do
        local name = type(faction.outfitNames) == "table" and faction.outfitNames[id] or nil
        if type(name) ~= "string" or string.find(name, "%S") == nil then name = Wardrobe.labels[id] .. " outfit" end
        rows[#rows + 1] = { id = id, season = Wardrobe.seasons[id], label = Wardrobe.labels[id],
            name = name, clothing = type(faction["outfit" .. id]) == "table" and faction["outfit" .. id] or {},
            tints = type(faction["tint" .. id]) == "table" and faction["tint" .. id] or {} }
    end
    return rows
end

function Wardrobe.coverage(faction)
    local count, seen = 0, {}
    local seasons = type(faction) == "table" and faction.outfitSeason or nil
    for _, row in ipairs(Wardrobe.rows(faction)) do
        local signature = Wardrobe.signature(row.clothing)
        if type(seasons) == "table" and seasons[row.id] == row.season and signature ~= ""
                and not seen[signature] then
            seen[signature], count = true, count + 1
        end
    end
    return count
end

return Wardrobe
