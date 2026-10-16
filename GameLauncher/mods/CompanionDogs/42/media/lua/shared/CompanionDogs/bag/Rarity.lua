CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.rarityIndex = nil

---Loot weight by item short name, summed over the procedural lists and scaled by how often each list is used; built once.
---@return table<string, number> index
function CD.buildRarityIndex()
    if CD.rarityIndex then return CD.rarityIndex end
    local idx = {}
    local refs = {}
    local function walk(t, depth)
        if depth > 5 or type(t) ~= "table" then return end
        local pl = t.procList
        if type(pl) == "table" then
            for i = 1, #pl do
                local e = pl[i]
                if type(e) == "table" and type(e.name) == "string" then
                    refs[e.name] = (refs[e.name] or 0) + 1
                end
            end
        end
        for _, v in pairs(t) do
            if type(v) == "table" then
                walk(v, depth + 1)
            end
        end
    end
    walk(Distributions, 0)

    local list = ProceduralDistributions.list
    local function addAll(items, mult)
        if type(items) ~= "table" then return end
        local i = 1
        while i < #items do
            local n, w = items[i], items[i + 1]
            if type(n) == "string" and type(w) == "number" then
                local short = string.match(n, "([^.]+)$") or n
                idx[short] = (idx[short] or 0) + w * mult
            end
            i = i + 2
        end
    end
    for name, tab in pairs(list) do
        if type(tab) == "table" then
            local mult = refs[name] or 0
            if mult < 1 then
                mult = 1
            end
            addAll(tab.items, mult)
            if type(tab.junk) == "table" then
                addAll(tab.junk.items, mult)
            end
        end
    end
    CD.rarityIndex = idx
    return CD.rarityIndex
end

---@param fullType string|nil
---@return number|nil weight summed loot weight; nil when the item never shows up as loot
function CD.itemAbundance(fullType)
    if not fullType then return nil end
    local idx = CD.buildRarityIndex()
    local short = string.match(tostring(fullType), "([^.]+)$")
    return short and idx[short] or nil
end

---@param item InventoryItem|nil
---@return boolean true when the item weighs at most FETCH_MAX_WEIGHT
---@nodiscard
function CD.fetchCanCarry(item)
    if not item then return false end
    return CD.itemWeight(item) <= CD.FETCH_MAX_WEIGHT
end

---With fetch rarity on, rare loot falls toward FETCH_RARITY_MIN and common loot rises toward TRICK_FETCH_CHANCE.
---@param fullType string
---@return number|nil chance nil when rarity is on and the item never shows up as loot
function CD.fetchNightChance(fullType)
    local cap = CD.TRICK_FETCH_CHANCE
    if not CD.fetchRarityEnabled() then return cap end
    local ab = CD.itemAbundance(fullType)
    if not ab or ab <= 0 then return nil end
    local minChance = CD.FETCH_RARITY_MIN
    local fullAt = CD.FETCH_RARITY_FULL
    local t = math.log(1 + ab) / math.log(1 + fullAt)
    if t > 1 then t = 1 elseif t < 0 then t = 0 end
    local e = CD.FETCH_RARITY_EXP
    return minChance + (cap - minChance) * (t ^ e)
end
