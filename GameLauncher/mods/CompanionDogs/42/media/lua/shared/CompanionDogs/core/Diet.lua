CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Dieta efetiva de uma raca: o default do base mais o `diet` que o addon declarou no registerBreed.
-- Os campos de tipo sao sets de FoodType/fullType; os de nome sao pedacos de nome em MINUSCULO,
-- comparados por string.find contra o getType() do item.

CD.DIET_CACHE = CD.DIET_CACHE or {}

CD.DIET_FIELDS = {
    bad = "set", badParts = "parts",
    protein = "set", proteinParts = "parts",
    nonProtein = "set",
    trough = "set", troughItems = "set",
}

local function copySet(src)
    local out = {}
    if src then
        for k, v in pairs(src) do
            if v then
                out[k] = true
            end
        end
    end
    return out
end

local function partsSet(list)
    local out = {}
    if list then
        for _, part in ipairs(list) do
            out[string.lower(part)] = true
        end
    end
    return out
end

local function applyOverride(set, override)
    if type(override) ~= "table" then return end
    for k, v in pairs(override) do
        if type(k) == "string" then
            set[k] = v and true or nil
        end
    end
end

local function applyPartsOverride(set, override)
    if type(override) ~= "table" then return end
    for k, v in pairs(override) do
        if type(k) == "string" then
            set[string.lower(k)] = v and true or nil
        end
    end
end

local function setToList(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function buildDiet(breedKey)
    local def = breedKey and CD.BREEDS and CD.BREEDS[breedKey]
    local d = def and def.diet
    local replace = type(d) == "table" and d.replace == true

    local bad, badParts, protein, proteinParts, nonProtein, trough, troughItems
    if replace then
        bad, protein, nonProtein, trough, troughItems = {}, {}, {}, {}, {}
        badParts, proteinParts = {}, {}
    else
        bad = copySet(CD.BAD_FOOD_TYPES)
        badParts = partsSet(CD.BAD_FOOD_NAME_PARTS)
        protein = copySet(CD.PROTEIN_FOOD_TYPES)
        proteinParts = partsSet(CD.PROTEIN_NAME_PARTS)
        nonProtein = copySet(CD.NON_PROTEIN_FOOD_TYPES)
        trough = copySet(CD.TROUGH_EAT_TYPES)
        troughItems = copySet(CD.TROUGH_EAT_ITEMS)
    end

    if type(d) == "table" then
        applyOverride(bad, d.bad)
        applyPartsOverride(badParts, d.badParts)
        applyOverride(protein, d.protein)
        applyPartsOverride(proteinParts, d.proteinParts)
        applyOverride(nonProtein, d.nonProtein)
        applyOverride(trough, d.trough)
        applyOverride(troughItems, d.troughItems)
    end

    return {
        bad = bad,
        badParts = setToList(badParts),
        protein = protein,
        proteinParts = setToList(proteinParts),
        nonProtein = nonProtein,
        trough = trough,
        troughItems = troughItems,
    }
end

---@param breedKey string|nil breed key; nil or unknown falls back to the base diet
---@return table diet { bad, badParts, protein, proteinParts, nonProtein, trough, troughItems }
---@nodiscard
function CD.dietFor(breedKey)
    local key = breedKey or ""
    local cached = CD.DIET_CACHE[key]
    if not cached then
        cached = buildDiet(breedKey)
        CD.DIET_CACHE[key] = cached
    end
    return cached
end

---Drops every cached diet, so dietFor rebuilds each one from the current breed table.
function CD.clearDietCache()
    CD.DIET_CACHE = {}
end
